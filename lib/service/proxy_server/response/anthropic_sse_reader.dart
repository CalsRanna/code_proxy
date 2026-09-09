import 'dart:convert';

import 'package:code_proxy/service/proxy_server/response/sse_text_line_buffer.dart';

/// Anthropic SSE 文本读取器：逐行解析一次，同时维护流状态与可选的模型名改写。
///
/// 此前这两件事分别由 AnthropicSseScanner 与 AnthropicSseModelRewriter 各做
/// 一遍：同一份 data 行被 jsonDecode 两次，行缓冲也各维护一份。合并后每个
/// data 行只解析一次，解析结果同时供 usage/完成信号与 message_start 的模型名
/// 改写使用。
///
/// [add] 的返回契约：
/// - null 表示本段无需改写，调用方可原样转发原始字节；
/// - 非 null 表示应转发该文本，可能是空串（整段被行缓冲扣住，等下一段补全）。
///
/// 调用方必须按 null 判断，不能用引用相等：行缓冲会扣住不完整的尾行，此时
/// 即使没有改写也不能把原始字节放过去，否则该行会在补全后被重发一次。
class AnthropicSseReader {
  /// [spoofedModel] 非空时启用响应模型伪装：message_start 的 model 换成它。
  AnthropicSseReader({String? spoofedModel}) : _spoofedModel = spoofedModel;

  final String? _spoofedModel;
  final SseTextLineBuffer _lineBuffer = SseTextLineBuffer();

  bool _sawCompletionSignal = false;
  bool _sawContentDelta = false;

  int? _inputTokens;
  int? _outputTokens;
  int? _cacheCreationTokens;
  int? _cacheReadTokens;

  /// 是否已收到 Anthropic 的流完成信号（`message_stop`）。
  bool get sawCompletionSignal => _sawCompletionSignal;

  /// 是否已收到首个内容 delta（任意类型的 `content_block_delta`）。
  ///
  /// 流式处理器在喂入每个 chunk 后检查，首次翻转的时刻即首字用时的终点。
  /// message_start / content_block_start / ping 不算内容：它们在上游开始
  /// 生成前就会到达，按它们计时只能得到接近 TTFB 的常量。
  bool get sawContentDelta => _sawContentDelta;

  /// 是否解析到过任何 usage 字段。
  ///
  /// 供非流式路径区分「usage 全为 0」与「文本里根本没有 usage」——
  /// 后者应向上报 null，而不是一组 null 值的 map。
  bool get hasUsage =>
      _inputTokens != null ||
      _outputTokens != null ||
      _cacheCreationTokens != null ||
      _cacheReadTokens != null;

  /// 累积到当前为止的 usage。
  Map<String, int?> get usage => {
    'input': _inputTokens,
    'output': _outputTokens,
    'cache_creation': _cacheCreationTokens,
    'cache_read': _cacheReadTokens,
  };

  /// 一次性消费整段 SSE 文本并收尾，返回其中的 usage；没有则返回 null。
  static Map<String, int?>? scanUsage(String text) {
    final reader = AnthropicSseReader()..add(text);
    reader.flush();
    return reader.hasUsage ? reader.usage : null;
  }

  /// 喂入一段已解码文本；返回应转发的文本，null 表示可原样转发原始字节。
  String? add(String text) {
    final lines = _lineBuffer.add(text);
    if (_spoofedModel == null) {
      for (final line in lines) {
        _parseLine(line);
      }
      return null;
    }

    final output = StringBuffer();
    var rewritten = false;
    for (final line in lines) {
      final parsed = _parseLine(line);
      final emitted = _rewriteLine(line, parsed);
      if (!identical(emitted, line)) rewritten = true;
      output
        ..write(emitted)
        ..write('\n');
    }
    // 有改写要发改写后的文本；扣住了不完整尾行则只能发完整行的部分，
    // 否则该尾行会在下一段补全后重复出现。
    if (rewritten || _lineBuffer.hasPending) return output.toString();
    return null;
  }

  /// 流结束时处理没有换行结尾的残留行，返回应转发的文本（可能为空）。
  String flush() {
    final remainder = _lineBuffer.flush();
    if (remainder.isEmpty) return '';
    final parsed = _parseLine(remainder);
    if (_spoofedModel == null) return '';
    return _rewriteLine(remainder, parsed);
  }

  /// 解析一行并更新流状态，返回解析出的 JSON 对象；非 JSON 行返回 null。
  Map<String, dynamic>? _parseLine(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;

    if (line.startsWith('event:')) {
      if (line.substring('event:'.length).trim() == 'message_stop') {
        _sawCompletionSignal = true;
      }
      return null;
    }

    final payload = line.startsWith('data:')
        ? line.substring('data:'.length).trim()
        : line;
    if (!payload.startsWith('{')) return null;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;

      if (decoded['type'] == 'message_stop') _sawCompletionSignal = true;
      if (decoded['type'] == 'content_block_delta') _sawContentDelta = true;

      // message_start 的 usage 在 message.usage 下，message_delta 在顶层
      final Object? usageValue;
      if (decoded['type'] == 'message_start') {
        final message = decoded['message'];
        usageValue = message is Map<String, dynamic> ? message['usage'] : null;
      } else {
        usageValue = decoded['usage'];
      }
      if (usageValue is Map<String, dynamic>) _accumulate(usageValue);
      return decoded;
    } catch (_) {
      // 非 JSON 或损坏的行：忽略。真正的截断由完成信号缺失体现。
      return null;
    }
  }

  /// 按需改写 message_start 的模型名；不满足条件时原样返回 [line]。
  String _rewriteLine(String line, Map<String, dynamic>? parsed) {
    final spoofed = _spoofedModel;
    if (spoofed == null || parsed == null) return line;
    if (parsed['type'] != 'message_start') return line;

    final message = parsed['message'];
    if (message is! Map<String, dynamic>) return line;
    if (message['model'] is! String) return line;

    final match = _dataLinePattern.firstMatch(line);
    if (match == null) return line;

    message['model'] = spoofed;
    // 保留原行的前导空白、"data:" 后的间隔与行尾 CR，只替换 payload
    return '${match.group(1)}${match.group(2)}${jsonEncode(parsed)}${match.group(4)}';
  }

  void _accumulate(Map<String, dynamic> usage) {
    _inputTokens = (usage['input_tokens'] as int?) ?? _inputTokens;
    final output = usage['output_tokens'] as int?;
    if (output != null) _outputTokens = output;
    _cacheCreationTokens =
        (usage['cache_creation_input_tokens'] as int?) ?? _cacheCreationTokens;
    _cacheReadTokens =
        (usage['cache_read_input_tokens'] as int?) ?? _cacheReadTokens;
  }

  /// `data:` 行匹配：前导空白 + `data:` + 间隔 + payload + 可选行尾 CR。
  ///
  /// 用 `[\s\S]*?` 而非 `.`：ECMAScript 的 `.` 不匹配 CR，若用 `.`，
  /// CRLF 流的所有 data 行都匹配不上，模型伪装会静默失效。
  static final RegExp _dataLinePattern = RegExp(r'^(\s*data:)(\s*)([\s\S]*?)(\r?)$');
}
