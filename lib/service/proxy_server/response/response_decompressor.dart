import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/util/logger_util.dart';

/// 响应体解压工具
class ResponseDecompressor {
  /// 根据 content-encoding 解压响应体字节
  /// 返回解压后的字节，如果不需要解压或不支持的格式则返回原始字节
  static List<int> decompress(List<int> bytes, String? contentEncoding) {
    if (contentEncoding == null || contentEncoding.isEmpty) return bytes;

    try {
      switch (contentEncoding.toLowerCase()) {
        case 'gzip':
          return gzip.decode(bytes);
        case 'deflate':
          return zlib.decode(bytes);
        case 'br':
          LoggerUtil.instance.w(
            'Brotli decompression not supported, raw bytes used for logging',
          );
          return bytes;
        case 'zstd':
          LoggerUtil.instance.w(
            'Zstd decompression not supported, raw bytes used for logging',
          );
          return bytes;
        default:
          return bytes;
      }
    } catch (e) {
      LoggerUtil.instance.w(
        'Failed to decompress response body ($contentEncoding): $e',
      );
      return bytes;
    }
  }

  /// 将响应体字节转换为适合日志记录的文本。
  /// 如果无法得到可读文本，则返回包含编码和数据摘要的占位描述。
  static String decodeForLogging(List<int> bytes, String? contentEncoding) {
    if (bytes.isEmpty) return '';

    final decompressedBytes = decompress(bytes, contentEncoding);
    final bodyStr = utf8.decode(decompressedBytes, allowMalformed: true);
    if (_isReadableText(bodyStr)) {
      return bodyStr;
    }

    // 只对前若干字节做 base64：整体编码一个 10 MB 的二进制体会先生成约
    // 13 MB 字符串再丢弃，而这里只需要 120 个字符的预览。
    // 90 字节正好编码成 120 个 base64 字符。
    const previewByteCount = 90;
    final exceedsPreview = bytes.length > previewByteCount;
    final base64Preview = base64Encode(
      exceedsPreview ? bytes.sublist(0, previewByteCount) : bytes,
    );
    final preview = exceedsPreview ? '$base64Preview...' : base64Preview;
    final encodingLabel = contentEncoding == null || contentEncoding.isEmpty
        ? 'identity'
        : contentEncoding;

    return '[non-text response body, ${bytes.length} bytes, '
        'content-encoding: $encodingLabel, base64: $preview]';
  }

  static bool _isReadableText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (!trimmed.contains('\uFFFD')) return true;

    final replacementCount = '\uFFFD'.allMatches(trimmed).length;
    return replacementCount * 2 < trimmed.length;
  }
}
