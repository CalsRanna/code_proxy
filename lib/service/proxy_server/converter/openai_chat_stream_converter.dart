import 'dart:convert';

import 'package:code_proxy/service/proxy_server/converter/anthropic_sse_writer.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_chat_response_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_usage_extractor.dart';
import 'package:code_proxy/util/logger_util.dart';

import 'openai_sse_converter.dart';
import 'sse_line_splitter.dart';

/// OpenAI Chat Completions 流式响应（SSE）→ Anthropic Messages 流式事件
/// 的有状态转换器。
///
/// 输出为标准 Anthropic SSE 事件序列：
/// ```
/// message_start ─► ping ─► content_block_start ─► content_block_delta* ─►
/// content_block_stop ─► message_delta(stop_reason, usage) ─► message_stop
/// ```
///
/// 设计要点：
/// - message_start/ping 在构造时立即产出，保证客户端尽快收到 TTFB 响应
/// - text block 惰性开启：收到首个文本分片才发 content_block_start，
///   纯工具调用响应不产生多余空块
/// - 工具参数分片直接转发 partial_json（增量协议，客户端负责拼装）
/// - usage 从任意携带它的 chunk 中捕获（配合 include_usage 请求参数，
///   通常出现在最后一个 chunk）
///
/// 典型用法：
/// ```dart
/// final converter = OpenAiChatSseStreamConverter(originalModel: 'claude-sonnet-4-5');
/// final head = converter.initialEvents();      // message_start + ping
/// ...
/// final out = converter.handleData(chunk);     // 逐块转换
/// final tail = converter.handleDone();         // 收尾事件
/// final usage = converter.finalUsage;          // 最终 token 用量
/// ```
class OpenAiChatSseStreamConverter implements OpenAiSseConverter {
  /// 客户端请求的原始模型名，回填到 message_start 中
  final String? originalModel;

  final AnthropicSseWriter _writer = AnthropicSseWriter();
  final SseLineSplitter _lineSplitter = SseLineSplitter();

  /// OpenAI tool_call index → 状态
  final Map<int, ToolBlockState> _tools = {};

  String _stopReason = 'end_turn';

  /// 是否已收到 [DONE]
  bool _done = false;

  /// 是否收到过任意 finish_reason（部分网关发完 finish_reason 后不发 [DONE]，
  /// 此时仍应视为正常完成）
  bool _receivedFinishReason = false;

  OpenAiChatSseStreamConverter({this.originalModel});

  /// 构造时立即产出的头部事件：message_start + ping。
  ///
  /// 与官方 Anthropic API 行为一致：message_start 在首字节就返回。
  @override
  List<int> initialEvents() => _writer.initialEvents(originalModel);

  /// 处理一个上游字节块，返回转换后的 Anthropic SSE 字节。
  @override
  List<int> handleData(List<int> chunk) {
    for (final line in _lineSplitter.add(chunk)) {
      _processLine(line);
    }
    return takeOutput();
  }

  /// 上游流正常结束：冲刷解码缓冲、关闭未闭合的 block、输出收尾事件。
  @override
  List<int> handleDone() {
    for (final line in _lineSplitter.flush()) {
      _processLine(line);
    }
    return _finishSequence();
  }

  /// 上游流异常中断：输出 error 事件后终止。
  ///
  /// Anthropic 协议允许在流中途发送 error 事件，客户端会中断处理。
  @override
  List<int> handleError(Object error) => _writer.handleError(error);

  /// 最终 token 用量（供日志与统计），无 usage 数据时字段为 null。
  @override
  Map<String, int?> get finalUsage => _writer.finalUsage;

  /// 是否收到过完成信号（[DONE] 或任意 finish_reason chunk）。
  @override
  bool get isComplete => _done || _receivedFinishReason;

  @override
  Object? get error => null;

  @override
  bool get hasContentDelta => _writer.hasContentDelta;

  /// 取走当前累计的输出并清空缓冲。
  @override
  List<int> takeOutput() => _writer.takeOutput();

  void _processLine(String rawLine) {
    var line = rawLine.trimRight();
    if (line.isEmpty || !line.startsWith('data:')) return;

    final payload = line.substring(5).trim();
    if (_done) return;
    if (payload == '[DONE]') {
      _done = true;
      return;
    }
    if (payload.isEmpty) return;

    dynamic chunkJson;
    try {
      chunkJson = jsonDecode(payload);
    } catch (e) {
      LoggerUtil.instance.w('OpenAI SSE: failed to parse chunk, skipped: $e');
      return;
    }
    if (chunkJson is! Map) return;

    // usage 可随任意 chunk 到达（include_usage 时通常在最后一个数据 chunk 或其后单独的 chunk）
    final usage = chunkJson['usage'];
    if (usage is Map) _updateUsage(usage);

    final choices = chunkJson['choices'];
    if (choices is! List || choices.isEmpty) return;

    // finish_reason 可能出现在任意 choice 上，遍历提取
    for (final c in choices) {
      if (c is! Map) continue;
      final fr = c['finish_reason'];
      if (fr != null) {
        _stopReason = OpenAiChatResponseConverter.mapStopReason(fr);
        _receivedFinishReason = true;
        // 不 break 后续处理：后续 chunk 可能仍携带 usage
      }
    }

    final choice = choices.first;
    if (choice is! Map) return;

    final delta = choice['delta'];
    if (delta is! Map) return;

    // 首个 chunk 通常只有 delta.role="assistant"，role 已由 message_start 表达，跳过

    final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
    if (reasoning is String && reasoning.isNotEmpty) {
      _writer.writeThinking(reasoning);
    }

    final content = delta['content'];
    if (content is String && content.isNotEmpty) {
      _writer.writeText(content);
    }

    final toolCalls = delta['tool_calls'];
    if (toolCalls is List) {
      for (final tc in toolCalls) {
        if (tc is Map) _processToolCallDelta(tc);
      }
    }
  }

  void _processToolCallDelta(Map tc) {
    final tcIndex = tc['index'] is int ? tc['index'] as int : 0;
    final state = _tools.putIfAbsent(tcIndex, ToolBlockState.new);

    final id = tc['id'];
    if (id is String && id.isNotEmpty) state.id = id;

    final function = tc['function'];
    if (function is Map) {
      final name = function['name'];
      if (name is String && name.isNotEmpty) state.name = name;

      if (state.id != null && state.name != null && !state.started) {
        // 工具调用开始前先关闭已打开的 text block
        _writer.startToolBlock(state);
      }

      final arguments = function['arguments'];
      if (arguments is String &&
          arguments.isNotEmpty &&
          state.started &&
          state.claudeIndex != null) {
        _writer.writeEvent('content_block_delta', {
          'type': 'content_block_delta',
          'index': state.claudeIndex,
          'delta': {'type': 'input_json_delta', 'partial_json': arguments},
        });
      }
    }
  }

  List<int> _finishSequence() {
    if (_writer.finished) return const [];
    _writer.finish(_stopReason, _tools.values);
    return takeOutput();
  }

  void _updateUsage(Map usage) {
    // 多个 chunk 携带 usage 时以最后一个为准（流式总量在末尾才完整）
    _writer.updateUsage(
      extractOpenAiUsage(
        usage,
        totalInputKey: 'prompt_tokens',
        outputKey: 'completion_tokens',
        detailsKey: 'prompt_tokens_details',
      ),
    );
  }
}
