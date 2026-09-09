import 'dart:convert';

import 'package:code_proxy/service/proxy_server/response/anthropic_sse_scanner.dart';

/// Token 提取器 - 从 API 响应中提取 token 使用量
///
/// [extractUsage] 使用 JSON 解析精确提取 usage 对象中的各字段，支持非流式
/// （单个 JSON 对象）和 SSE 文本两种格式。返回值遵循 Anthropic 口径：
/// input 仅表示未缓存输入，缓存创建与读取分别保存在独立字段中，不能从
/// input 再次扣减。
///
/// SSE 文本一律交给 [AnthropicSseScanner]，与流式路径共用同一份协议解析。
class TokenExtractor {
  const TokenExtractor();

  /// 从完整响应文本中提取 usage。
  ///
  /// 先尝试解析为单个 JSON 对象（非流式响应），
  /// 失败后按 SSE 文本扫描（网关未声明 text/event-stream 却回了事件流）。
  Map<String, int?>? extractUsage(String text) {
    final singleJsonUsage = _tryExtractFromJson(text);
    if (singleJsonUsage != null) return singleJsonUsage;

    return AnthropicSseScanner.scanUsage(text);
  }

  Map<String, int?>? _tryExtractFromJson(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      final usage = json['usage'] as Map<String, dynamic>?;
      if (usage != null) {
        return _extractFromUsageMap(usage);
      }
    } catch (_) {}
    return null;
  }

  Map<String, int?> _extractFromUsageMap(Map<String, dynamic> usage) {
    return {
      'input': usage['input_tokens'] as int?,
      'output': usage['output_tokens'] as int?,
      'cache_creation': usage['cache_creation_input_tokens'] as int?,
      'cache_read': usage['cache_read_input_tokens'] as int?,
    };
  }
}
