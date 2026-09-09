/// 已解码文本的 SSE 行缓冲：处理到最后一个换行为止，残余尾行留给下一次
/// [add] 或 [flush]。
///
/// 与字节级的 [SseLineSplitter]（converter/）不同，本类接受已解码文本，
/// 供 Anthropic 透传路径的 [AnthropicSseScanner] 与
/// [AnthropicSseModelRewriter] 共用同一份行边界处理。
class SseTextLineBuffer {
  final StringBuffer _pending = StringBuffer();

  /// 返回自上次调用以来完整的行（不含行尾换行符）。
  List<String> add(String text) {
    if (text.isEmpty) return const [];
    _pending.write(text);

    final buffered = _pending.toString();
    final lastNewline = buffered.lastIndexOf('\n');
    if (lastNewline < 0) return const [];

    _pending
      ..clear()
      ..write(buffered.substring(lastNewline + 1));

    return buffered.substring(0, lastNewline).split('\n');
  }

  /// 返回没有换行结尾的残余（可能为空字符串）。
  String flush() {
    final remainder = _pending.toString();
    _pending.clear();
    return remainder;
  }
}
