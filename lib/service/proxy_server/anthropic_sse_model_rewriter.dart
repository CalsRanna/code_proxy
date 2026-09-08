import 'dart:convert';

import 'package:code_proxy/service/proxy_server/anthropic_sse_scanner.dart';

/// Anthropic SSE 流中的模型名改写器 —— 响应模型伪装。
///
/// 与 [AnthropicSseScanner] 一样按行喂入、内部行缓冲（跨 chunk 拼接），
/// 但输出的是改写后的文本：仅对 `message_start` 事件的 `message.model`
/// 做替换，其余行（事件名、其他 data 行、错误事件）原样透传，换行与
/// 事件边界结构不被改动。
///
/// 用法：每收到一个 chunk 调用 [add] 得到应转发给客户端的增量文本，
/// 流结束时再调用 [flush] 处理没有换行结尾的残留行。
class AnthropicSseModelRewriter {
  AnthropicSseModelRewriter(this._targetModel);

  /// 伪装目标模型名（客户端请求的原始模型名）
  final String _targetModel;

  final StringBuffer _pending = StringBuffer();

  /// 喂入一段已解码文本，返回改写后的增量文本。
  ///
  /// 不完整的尾行（没有换行结尾）会留在内部缓冲，与 [AnthropicSseScanner]
  /// 的语义一致。
  String add(String text) {
    if (text.isEmpty) return '';
    _pending.write(text);

    final buffered = _pending.toString();
    final lastNewline = buffered.lastIndexOf('\n');
    if (lastNewline < 0) return '';

    // 处理到最后一个换行（含），其后的内容才可能是未完成的行。
    // 以 \n 结尾（如事件分隔的空行）时整个缓冲都已是完整行。
    _pending
      ..clear()
      ..write(buffered.substring(lastNewline + 1));

    return _rewriteBlock(buffered.substring(0, lastNewline + 1));
  }

  /// 流结束时处理最后一行没有换行结尾的残留。
  String flush() {
    final remainder = _pending.toString();
    _pending.clear();
    return remainder.isEmpty ? '' : _rewriteBlock(remainder);
  }

  /// 逐行改写，保留原有的换行结构（`split.join` 不增删换行）。
  String _rewriteBlock(String text) {
    return text.split('\n').map(_rewriteLine).join('\n');
  }

  /// 改写单行：仅重写 message_start 的 data 行，其余原样返回。
  String _rewriteLine(String line) {
    final match = _dataLinePattern.firstMatch(line);
    if (match == null) return line;

    final payload = match.group(3)!;
    if (!payload.startsWith('{')) return line;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return line;
      if (decoded['type'] != 'message_start') return line;

      final message = decoded['message'];
      if (message is! Map<String, dynamic>) return line;
      if (message['model'] is! String) return line;

      message['model'] = _targetModel;
      // 保留原行的前导空白与 "data:" 后的间隔，只替换 payload
      return '${match.group(1)}${match.group(2)}${jsonEncode(decoded)}';
    } catch (_) {
      // 非 JSON 或损坏的行：原样透传
      return line;
    }
  }

  /// `data:` 行匹配：前导空白 + `data:` + 间隔 + payload。
  static final RegExp _dataLinePattern = RegExp(r'^(\s*data:)(\s*)(.*)$');
}
