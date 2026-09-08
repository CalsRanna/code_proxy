import 'dart:convert';

/// Anthropic SSE 流的扫描器 —— 完成信号与 usage 的**唯一**解析实现。
///
/// 按行喂入，边流边维护「是否见过完成信号」与累积的 usage。此前这两件事
/// 都在流结束时对整个响应体重做一遍：先 join 出完整副本，再用 LineSplitter
/// 全量分行找 message_stop，再让 extractUsage 整体试一次 jsonDecode 并
/// split('\n') 逐行解析 —— 一个 5 MB 的 SSE 响应会在流结束瞬间同步烧掉
/// 几百毫秒主线程，而 handleData 里其实已经增量提取过一遍 token 了。
///
/// 行缓冲同时消除了跨 chunk 的行截断：只处理到最后一个换行为止，剩余部分
/// 留到下一个 chunk 或 [flush]。
///
/// 非流式与压缩流拿不到逐 chunk 的可读文本，但同样走这里：一次 [add] 整段
/// 文本再 [flush] 即可。协议解析只此一份，新增 usage 字段不会漏改路径。
class AnthropicSseScanner {
  final StringBuffer _pending = StringBuffer();
  bool _sawCompletionSignal = false;

  int? _inputTokens;
  int? _outputTokens;
  int? _cacheCreationTokens;
  int? _cacheReadTokens;

  /// 是否已收到 Anthropic 的流完成信号（`message_stop`）。
  bool get sawCompletionSignal => _sawCompletionSignal;

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
    final scanner = AnthropicSseScanner()..add(text);
    scanner.flush();
    return scanner.hasUsage ? scanner.usage : null;
  }

  /// 喂入一段已解码文本。不完整的尾行会留在内部缓冲。
  void add(String text) {
    if (text.isEmpty) return;
    _pending.write(text);

    final buffered = _pending.toString();
    final lastNewline = buffered.lastIndexOf('\n');
    if (lastNewline < 0) return;

    _pending
      ..clear()
      ..write(buffered.substring(lastNewline + 1));

    for (final line in buffered.substring(0, lastNewline).split('\n')) {
      _processLine(line);
    }
  }

  /// 流结束时处理最后一行没有换行结尾的残留。
  void flush() {
    final remainder = _pending.toString();
    _pending.clear();
    if (remainder.isNotEmpty) _processLine(remainder);
  }

  void _processLine(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return;

    if (line.startsWith('event:')) {
      if (line.substring('event:'.length).trim() == 'message_stop') {
        _sawCompletionSignal = true;
      }
      return;
    }

    final payload = line.startsWith('data:')
        ? line.substring('data:'.length).trim()
        : line;
    if (!payload.startsWith('{')) return;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return;

      if (decoded['type'] == 'message_stop') _sawCompletionSignal = true;

      // message_start 的 usage 在 message.usage 下，message_delta 在顶层
      final Object? usageValue;
      if (decoded['type'] == 'message_start') {
        final message = decoded['message'];
        usageValue = message is Map<String, dynamic> ? message['usage'] : null;
      } else {
        usageValue = decoded['usage'];
      }
      if (usageValue is Map<String, dynamic>) _accumulate(usageValue);
    } catch (_) {
      // 非 JSON 或损坏的行：忽略。真正的截断由完成信号缺失体现。
    }
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
}
