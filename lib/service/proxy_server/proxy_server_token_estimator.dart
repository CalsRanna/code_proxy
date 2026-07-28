import 'dart:convert';

/// 基于字符序列的 token 数估算器，用于在本地近似
/// Anthropic `v1/messages/count_tokens` API 的返回值。
///
/// **设计目标:**
/// - 纯 Dart 实现，无额外依赖
/// - 允许请求统计在不需要上游支持 `count_tokens` 端点的情况下正常进行
/// - 误差在上游 API 返回值的合理范围内
///
/// **使用场景:**
/// - Claude Desktop 会在每次请求前调用 `count_tokens`
/// - 大部分上游端点不支持此端点（60% 返回 404）
/// - 本估算器在本地计算，避免无效网络往返
///
/// **启发式估算方法:**
/// - CJK 字符（中文/日文/韩文等）: 约 1 token/字符
/// - 其他字符（英语/西欧等）: 约 1 token / 4 字符
/// - 消息结构开销: 每个消息约 5 tokens（role 标记等）
/// - 工具定义开销: 每个工具约 20 tokens
///
/// **边界情况:**
/// - 空或无效输入返回 0
/// - 大规模请求体（含有大量工具定义）也能给出保守估算
class ProxyServerTokenEstimator {
  /// 估算一个文本字符串的 token 数
  static int estimate(String text) {
    if (text.isEmpty) return 0;

    var tokens = 0;
    var cjkBuffer = 0; // 连续的CJK字符
    var otherBuffer = 0; // 连续的非CJK字符

    for (var i = 0; i < text.length; i++) {
      final codeUnit = text.codeUnitAt(i);
      if (_isCJK(codeUnit)) {
        // CJK 字符: 约1 token/字符,先刷新 otherBuffer
        tokens += otherBuffer ~/ 4;
        otherBuffer = 0;
        cjkBuffer++;
      } else {
        // 非CJK字符: 约 4 字符/token,先刷新 cjkBuffer
        tokens += cjkBuffer;
        cjkBuffer = 0;
        otherBuffer++;
      }
    }
    // 刷新剩余缓冲区
    tokens += cjkBuffer + otherBuffer ~/ 4;

    return tokens > 0 ? tokens : 1; // 最小 1 token（必须有）
  }

  /// 估算完整请求体的 token 数
  ///
  /// 支持原始字节或已解析的 JSON body，与 Anthropic
  /// `count_tokens` API 的参数格式一致。
  static int estimateRequestBody(List<int> rawBody) {
    try {
      final bodyString = utf8.decode(rawBody, allowMalformed: true);
      if (bodyString.isEmpty) return 0;

      final body = jsonDecode(bodyString) as Map<String, dynamic>;
      var total = 0;

      // 1. system prompt
      final system = body['system'];
      if (system is String) {
        total += estimate(system);
      } else if (system is List) {
        // system 也可能是 content block 数组
        for (final block in system) {
          if (block is Map<String, dynamic>) {
            final text = block['text'];
            if (text is String) total += estimate(text);
          }
        }
      }

      // 2. messages
      final messages = body['messages'];
      if (messages is List) {
        for (final msg in messages) {
          if (msg is Map<String, dynamic>) {
            total += 5; // 消息结构开销
            final content = msg['content'];
            if (content is String) {
              total += estimate(content);
            } else if (content is List) {
              for (final block in content) {
                if (block is Map<String, dynamic>) {
                  final text = block['text'];
                  if (text is String) total += estimate(text);
                }
              }
            }
          }
        }
      }

      // 3. tools
      final tools = body['tools'];
      if (tools is List) {
        for (final tool in tools) {
          if (tool is Map<String, dynamic>) {
            total += estimate(jsonEncode(tool)) + 20;
          }
        }
      }

      return total;
    } catch (_) {
      return 0;
    }
  }

  /// CJK 统一表意文字相关区块:
  ///   - 基本表意文字 (4E00-9FFF)   夹 夹
  ///   - 扩展A区 (3400-4DBF)
  ///   - 兼容表意文字 (F900-FAFF)
  ///   - CJK标点 (3000-303F)
  ///   - 平假名 (3040-309F)
  ///   - 片假名 (30A0-30FF)
  ///   - 韩文音节 (AC00-D7AF)
  ///   - 全角形式 (FF00-FFEF)
  static bool _isCJK(int codeUnit) {
    return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) || // CJK统一表意文字
        (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) || // CJK扩展A
        (codeUnit >= 0xF900 && codeUnit <= 0xFAFF) || // CJK兼容表意文字
        (codeUnit >= 0x3000 && codeUnit <= 0x303F) || // CJK标点
        (codeUnit >= 0x3040 && codeUnit <= 0x309F) || // 平假名
        (codeUnit >= 0x30A0 && codeUnit <= 0x30FF) || // 片假名
        (codeUnit >= 0xAC00 && codeUnit <= 0xD7AF) || // 韩文音节
        (codeUnit >= 0xFF00 && codeUnit <= 0xFFEF); // 全角形式
  }
}
