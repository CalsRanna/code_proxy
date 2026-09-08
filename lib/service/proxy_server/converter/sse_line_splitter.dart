import 'dart:convert';

/// UTF-8 字节流 → SSE 行的流式切分器。
///
/// 处理两类边界：
/// - 多字节 UTF-8 字符跨 chunk 截断（chunked decoder 维护 carry 字节）
/// - 一行 data: {...} 跨 chunk 截断（行缓冲）
class SseLineSplitter {
  final StringBuffer _decodedBuffer = StringBuffer();
  late final ByteConversionSink _decodeSink;
  String _pending = '';

  SseLineSplitter() {
    _decodeSink = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(
          // StringBuffer 不是 Sink<String>，需经 StringConversionSink 桥接
          StringConversionSink.fromStringSink(_decodedBuffer),
        );
  }

  /// 输入一个字节块，返回其中完整的行（不含换行符）。
  List<String> add(List<int> chunk) {
    _decodeSink.add(chunk);
    final text = _decodedBuffer.toString();
    _decodedBuffer.clear();
    if (text.isEmpty) return const [];

    _pending += text;
    return _drainCompleteLines();
  }

  /// 流结束时冲刷 decoder 尾部缓冲，并把未换行的剩余内容作为最后一行返回。
  List<String> flush() {
    _decodeSink.close();
    final tail = _decodedBuffer.toString();
    _decodedBuffer.clear();
    if (tail.isNotEmpty) _pending += tail;

    if (_pending.isNotEmpty) {
      final last = _pending;
      _pending = '';
      return [..._drainCompleteLines(), last];
    }
    return _drainCompleteLines();
  }

  List<String> _drainCompleteLines() {
    final lines = <String>[];
    var idx = _pending.indexOf('\n');
    while (idx >= 0) {
      lines.add(_pending.substring(0, idx));
      _pending = _pending.substring(idx + 1);
      idx = _pending.indexOf('\n');
    }
    // 去除 \r（CRLF 行尾兼容）
    return [
      for (final l in lines)
        l.endsWith('\r') ? l.substring(0, l.length - 1) : l,
    ];
  }
}
