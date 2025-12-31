import 'dart:convert';

import 'package:code_proxy/util/logger_util.dart';

/// Token 提取器 - 从 API 响应中提取 token 使用量
class TokenExtractor {
  const TokenExtractor();

  /// 从普通 JSON 响应中提取 token 使用量
  /// 失败时打印日志并返回 null
  Map<String, int?>? extractFromResponse(String bodyStr) {
    try {
      final json = jsonDecode(bodyStr);
      if (json is! Map<String, dynamic> || !json.containsKey('usage')) {
        return null;
      }

      final usageData = json['usage'];
      if (usageData is! Map<String, dynamic>) {
        return null;
      }

      final inputTokens = _safeParseInt(usageData['input_tokens']);
      final outputTokens = _safeParseInt(usageData['output_tokens']);

      // 如果两个都解析失败，返回 null
      if (inputTokens == null && outputTokens == null) {
        return null;
      }

      return {'input': inputTokens, 'output': outputTokens};
    } catch (e) {
      LoggerUtil.instance.e('Token extraction failed: $e');
      return null;
    }
  }

  /// 从 SSE message_start 事件中提取 input tokens
  /// 失败时打印日志并返回 null
  int? extractInputFromMessageStart(Map<String, dynamic> json) {
    try {
      if (json['type'] != 'message_start' || !json.containsKey('message')) {
        return null;
      }

      final message = json['message'];
      if (message is! Map<String, dynamic> || !message.containsKey('usage')) {
        return null;
      }

      final usage = message['usage'];
      if (usage is! Map<String, dynamic>) {
        return null;
      }

      return _safeParseInt(usage['input_tokens']);
    } catch (e) {
      LoggerUtil.instance.e(
        'Failed to extract input tokens from message_start: $e',
      );
      return null;
    }
  }

  /// 从 SSE message_delta 事件中提取 output tokens
  /// 失败时打印日志并返回 null
  int? extractOutputFromMessageDelta(Map<String, dynamic> json) {
    try {
      if (json['type'] != 'message_delta' || !json.containsKey('usage')) {
        return null;
      }

      final usage = json['usage'];
      if (usage is! Map<String, dynamic>) {
        return null;
      }

      return _safeParseInt(usage['output_tokens']);
    } catch (e) {
      LoggerUtil.instance.e(
        'Failed to extract output tokens from message_delta: $e',
      );
      return null;
    }
  }

  /// 安全地将动态值转换为 int
  int? _safeParseInt(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }
}
