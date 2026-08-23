import 'dart:convert';

import 'package:code_proxy/model/normalized_token_usage.dart';
import 'package:code_proxy/util/logger_util.dart';

/// OpenAI Chat Completions API → Anthropic Messages API 响应体转换器
/// （非流式 JSON 与错误体）。
///
/// 流式 SSE 转换见 [OpenAiSseStreamConverter]。
///
/// 转换输出为标准 Anthropic 格式，因此下游的 TokenExtractor、审计日志、
/// 断路器等组件无需感知上游协议差异。
class OpenAiCompatResponseConverter {
  const OpenAiCompatResponseConverter();

  /// 非流式响应转换。
  ///
  /// [openaiResponse] 为上游返回的 chat.completion JSON；
  /// [originalModel] 为客户端请求的原始模型名，回填到响应中，
  /// 保证 Claude Code 显示它认识的模型名。
  Map<String, dynamic> convertResponse(
    Map<String, dynamic> openaiResponse, {
    required String? originalModel,
  }) {
    final choices = openaiResponse['choices'];
    final choice = choices is List && choices.isNotEmpty ? choices.first : null;
    if (choice is! Map) {
      // 无 choices 的畸形响应：返回空消息而非抛错，避免代理 500
      LoggerUtil.instance.w(
        'OpenAI response has no choices: ${jsonEncode(openaiResponse)}',
      );
      return _emptyMessage(openaiResponse, originalModel);
    }

    final message = choice['message'];
    final contentBlocks = <Map<String, dynamic>>[];

    if (message is Map) {
      // 思考内容置于 content 首位（Anthropic 规范：thinking block 在 text 前）
      final reasoning = message['reasoning_content'] ?? message['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) {
        contentBlocks.add({'type': 'thinking', 'thinking': reasoning});
      }
      final text = message['content'];
      if (text is String && text.isNotEmpty) {
        contentBlocks.add({'type': 'text', 'text': text});
      }
      final toolCalls = message['tool_calls'];
      if (toolCalls is List) {
        for (final toolCall in toolCalls) {
          final block = _convertToolCall(toolCall);
          if (block != null) contentBlocks.add(block);
        }
      }
    }

    if (contentBlocks.isEmpty) {
      contentBlocks.add(const {'type': 'text', 'text': ''});
    }

    return {
      'id':
          openaiResponse['id'] ??
          'msg_${DateTime.now().microsecondsSinceEpoch}',
      'type': 'message',
      'role': 'assistant',
      'model': originalModel ?? openaiResponse['model'],
      'content': contentBlocks,
      'stop_reason': mapStopReason(choice['finish_reason']),
      'stop_sequence': null,
      'usage': convertUsage(openaiResponse['usage']),
    };
  }

  /// 上游错误响应 → Anthropic 错误格式。
  ///
  /// 解析失败（非 JSON / 空体）时保留原文包进 api_error，
  /// 确保 Claude Code 能以可读形式展示错误。
  Map<String, dynamic> convertErrorBody(String rawErrorBody) {
    String message = rawErrorBody.trim();
    String type = 'api_error';

    if (message.isEmpty) {
      return {
        'type': 'error',
        'error': {'type': type, 'message': ''},
      };
    }

    try {
      final json = jsonDecode(message);
      if (json is Map) {
        final error = json['error'];
        if (error is Map) {
          final rawMessage = error['message'];
          if (rawMessage is String && rawMessage.isNotEmpty) {
            message = rawMessage;
          } else if (message.length > 500) {
            message = message.substring(0, 500);
          }
          type = mapErrorType(error['type'], error['code']);
          return {
            'type': 'error',
            'error': {'type': type, 'message': message},
          };
        }
      }
    } catch (_) {
      // 非 JSON 错误体，保留原文
    }

    if (message.length > 2000) message = message.substring(0, 2000);
    return {
      'type': 'error',
      'error': {'type': type, 'message': message},
    };
  }

  /// 按 HTTP 状态码推断错误类型（错误体中无类型信息时使用）。
  static String mapErrorTypeFromStatus(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'invalid_request_error';
      case 401:
        return 'authentication_error';
      case 403:
        return 'permission_error';
      case 404:
        return 'not_found_error';
      case 429:
        return 'rate_limit_error';
      default:
        return 'api_error';
    }
  }

  /// OpenAI 错误体的 type/code 字段 → Anthropic 错误类型。
  ///
  /// code 比 type 更具体（如 type=invalid_request_error 但
  /// code=invalid_api_key 实为认证错误），优先匹配。
  static String mapErrorType(dynamic type, dynamic code) {
    final t = '$type'.toLowerCase();
    final c = '$code'.toLowerCase();

    if (c.contains('api_key') || c.contains('auth') || t.contains('auth')) {
      return 'authentication_error';
    }
    if (t.contains('quota') || t.contains('billing') || c.contains('billing')) {
      return 'billing_error';
    }
    if (t.contains('rate_limit') || c.contains('rate_limit')) {
      return 'rate_limit_error';
    }
    if (t.contains('not_found') || c.contains('model_not_found')) {
      return 'not_found_error';
    }
    if (t.contains('permission')) return 'permission_error';
    if (t.contains('overloaded')) return 'overloaded_error';
    if (t.contains('invalid_request')) return 'invalid_request_error';
    return 'api_error';
  }

  /// OpenAI finish_reason → Anthropic stop_reason。
  static String mapStopReason(dynamic finishReason) {
    switch (finishReason) {
      case 'length':
        return 'max_tokens';
      case 'tool_calls':
      case 'function_call':
        return 'tool_use';
      case 'stop_sequence':
        return 'stop_sequence';
      default:
        return 'end_turn';
    }
  }

  /// OpenAI usage → Anthropic usage。
  ///
  /// OpenAI 的 prompt_tokens 是包含缓存的总输入；Anthropic 的
  /// input_tokens 只表示未缓存输入。这里在协议边界拆成互斥的三类，
  /// 避免统计和计费再次把缓存 token 算入普通输入。
  static Map<String, dynamic> convertUsage(dynamic rawUsage) {
    if (rawUsage is! Map) return NormalizedTokenUsage.zero.toAnthropicUsage();

    final details = rawUsage['prompt_tokens_details'];
    return (NormalizedTokenUsage.fromOpenAi(
              totalInputTokens: rawUsage['prompt_tokens'],
              outputTokens: rawUsage['completion_tokens'],
              cacheReadInputTokens: details is Map
                  ? details['cached_tokens']
                  : null,
              cacheCreationInputTokens: details is Map
                  ? details['cache_write_tokens']
                  : null,
            ) ??
            NormalizedTokenUsage.zero)
        .toAnthropicUsage();
  }

  /// OpenAI tool_call → tool_use block。
  /// arguments 解析失败时兜底 {"raw_arguments": "..."}，不让单个坏参毁掉整个响应。
  Map<String, dynamic>? _convertToolCall(dynamic toolCall) {
    if (toolCall is! Map) return null;
    if (toolCall['type'] != null && toolCall['type'] != 'function') return null;

    final function = toolCall['function'];
    if (function is! Map) return null;

    final name = function['name'];
    if (name is! String || name.isEmpty) return null;

    Object? input;
    final arguments = function['arguments'];
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
      'id': toolCall['id'] ?? 'toolu_${DateTime.now().microsecondsSinceEpoch}',
      'name': name,
      'input': input ?? <String, dynamic>{},
    };
  }

  Map<String, dynamic> _emptyMessage(
    Map<String, dynamic> openaiResponse,
    String? originalModel,
  ) {
    return {
      'id': openaiResponse['id'] ?? 'msg_empty',
      'type': 'message',
      'role': 'assistant',
      'model': originalModel ?? openaiResponse['model'],
      'content': const [
        {'type': 'text', 'text': ''},
      ],
      'stop_reason': 'end_turn',
      'stop_sequence': null,
      'usage': convertUsage(openaiResponse['usage']),
    };
  }
}
