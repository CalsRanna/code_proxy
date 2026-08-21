import 'dart:convert';

import 'package:code_proxy/util/logger_util.dart';

/// OpenAI Responses API（POST /v1/responses）→ Anthropic Messages API
/// 响应体转换器（非流式 JSON 与错误体）。
///
/// 流式 SSE 转换见 [OpenAiResponsesSseStreamConverter]。
///
/// 与 Chat Completions 响应转换器相同的约定：转换输出为标准 Anthropic
/// 格式，下游的 TokenExtractor、审计日志、断路器等组件无需感知上游协议
/// 差异；错误体结构与 Chat Completions 同构，直接复用其错误转换逻辑。
class OpenAiResponsesResponseConverter {
  const OpenAiResponsesResponseConverter();

  /// 非流式响应转换。
  ///
  /// [responsesResponse] 为上游返回的 response object JSON；
  /// [originalModel] 为客户端请求的原始模型名，回填到响应中，
  /// 保证 Claude Code 显示它认识的模型名。
  Map<String, dynamic> convertResponse(
    Map<String, dynamic> responsesResponse, {
    required String? originalModel,
  }) {
    final output = responsesResponse['output'];
    final converted = output is List
        ? _convertOutputItems(output)
        : const (blocks: <Map<String, dynamic>>[], hasToolUse: false);

    final contentBlocks = converted.blocks;
    if (contentBlocks.isEmpty) {
      // 空输出/畸形响应：返回空消息而非抛错，避免代理 500
      LoggerUtil.instance.w(
        'Responses API response has no usable output: '
        '${jsonEncode(responsesResponse)}',
      );
      contentBlocks.add(const {'type': 'text', 'text': ''});
    }

    final stopReason = converted.hasToolUse
        ? 'tool_use'
        : mapStopReason(responsesResponse);

    return {
      'id': responsesResponse['id'] ?? 'msg_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'message',
      'role': 'assistant',
      'model': originalModel ?? responsesResponse['model'],
      'content': contentBlocks,
      'stop_reason': stopReason,
      'stop_sequence': null,
      'usage': convertUsage(responsesResponse['usage']),
    };
  }

  /// 按序遍历 output[] items → Anthropic content blocks。
  ///
  /// - reasoning item：summary 数组中的文本拼接为 thinking block
  ///   （Anthropic 规范：thinking block 在 text 前，output[] 天然满足）
  /// - message item：content[].output_text / refusal 合并为 text block
  /// - function_call item：arguments 解析为 tool_use block 的 input
  ({List<Map<String, dynamic>> blocks, bool hasToolUse}) _convertOutputItems(
    List output,
  ) {
    final blocks = <Map<String, dynamic>>[];
    final textParts = <String>[];
    var hasToolUse = false;

    void flushText() {
      if (textParts.isNotEmpty) {
        blocks.add({'type': 'text', 'text': textParts.join('')});
        textParts.clear();
      }
    }

    for (final item in output) {
      if (item is! Map) continue;
      switch (item['type']) {
        case 'reasoning':
          final thinking = _reasoningItemText(item);
          if (thinking != null && thinking.isNotEmpty) {
            flushText();
            blocks.add({'type': 'thinking', 'thinking': thinking});
          }
        case 'message':
          for (final part in _messageItemParts(item)) {
            textParts.add(part);
          }
        case 'function_call':
          final block = _convertFunctionCall(item);
          if (block != null) {
            flushText();
            blocks.add(block);
            hasToolUse = true;
          }
        // web_search_call / file_search_call 等内置工具项无法映射，剥离
      }
    }
    flushText();

    return (blocks: blocks, hasToolUse: hasToolUse);
  }

  /// reasoning item 的 summary 文本拼接。无 summary 时返回 null。
  String? _reasoningItemText(Map item) {
    final summary = item['summary'];
    if (summary is! List || summary.isEmpty) return null;
    final parts = <String>[];
    for (final s in summary) {
      if (s is Map && s['type'] == 'summary_text' && s['text'] is String) {
        parts.add(s['text'] as String);
      }
    }
    return parts.join('\n');
  }

  /// message item 的 content parts 文本列表。
  List<String> _messageItemParts(Map item) {
    final parts = <String>[];
    final content = item['content'];
    if (content is! List) return parts;
    for (final p in content) {
      if (p is! Map) continue;
      if ((p['type'] == 'output_text' || p['type'] == 'refusal') &&
          p['text'] is String) {
        parts.add(p['text'] as String);
      }
    }
    return parts;
  }

  /// function_call item → tool_use block。
  /// arguments 解析失败时兜底 {"raw_arguments": "..."}，不让单个坏参毁掉整个响应。
  Map<String, dynamic>? _convertFunctionCall(Map item) {
    final name = item['name'];
    if (name is! String || name.isEmpty) return null;

    Object? input;
    final arguments = item['arguments'];
    if (arguments is String && arguments.isNotEmpty) {
      try {
        final decoded = jsonDecode(arguments);
        input = decoded is Map ? decoded : {'value': decoded};
      } catch (_) {
        input = {'raw_arguments': arguments};
      }
    }

    return {
      'type': 'tool_use',
      'id': item['call_id'] ?? item['id'] ?? 'toolu_${DateTime.now().microsecondsSinceEpoch}',
      'name': name,
      'input': input ?? <String, dynamic>{},
    };
  }

  /// Responses API 响应 → Anthropic stop_reason。
  ///
  /// 优先级：incomplete(max_output_tokens) → max_tokens；
  /// status=incomplete 其他原因 → max_tokens（最接近的语义）；
  /// 其余按 end_turn 处理（tool_use 判定由调用方在含 function_call 时覆盖）。
  static String mapStopReason(Map<String, dynamic> response) {
    final status = response['status'];
    if (status == 'incomplete') {
      final details = response['incomplete_details'];
      final reason = details is Map ? details['reason'] : null;
      if (reason == 'max_output_tokens') return 'max_tokens';
      return 'end_turn';
    }
    return 'end_turn';
  }

  /// Responses API usage → Anthropic usage。
  ///
  /// input_tokens_details.cached_tokens 映射为 cache_read_input_tokens，
  /// 与 prompt cache 统计口径对齐。
  static Map<String, dynamic> convertUsage(dynamic rawUsage) {
    int inputTokens = 0;
    int outputTokens = 0;
    int cacheReadTokens = 0;

    if (rawUsage is Map) {
      inputTokens = _asInt(rawUsage['input_tokens']);
      outputTokens = _asInt(rawUsage['output_tokens']);
      final details = rawUsage['input_tokens_details'];
      if (details is Map) {
        cacheReadTokens = _asInt(details['cached_tokens']);
      }
    }

    return {
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      if (cacheReadTokens > 0) 'cache_read_input_tokens': cacheReadTokens,
      'cache_creation_input_tokens': 0,
    };
  }

  static int _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value') ?? 0;
}
