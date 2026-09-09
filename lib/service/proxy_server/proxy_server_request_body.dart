import 'dart:convert';

/// 单个代理请求的请求体：原始字节 + 懒解析的 JSON 视图。
///
/// 同一次请求的探针识别、模型映射、协议转换共用这一份解析结果，避免每个
/// 环节各自 jsonDecode 一遍整段请求体。长上下文请求可达数 MB，重复解析会
/// 直接拖慢转发，并卡住与代理同 isolate 的 UI。
///
/// 两条只读约定：
/// - [json] 返回的 Map 归调用方只读。需要改写（例如写入映射后的模型名）时
///   必须自行浅拷贝，否则故障转移到下一个端点会读到上一个端点写过的值。
/// - [bytes] 只读。同一个字节实例还被 http.Request.bodyBytes 与审计链路引用。
class ProxyServerRequestBody {
  ProxyServerRequestBody(this.bytes);

  /// 无请求体的场景（HEAD 探活）。
  ProxyServerRequestBody.empty() : bytes = const <int>[];

  final List<int> bytes;

  /// 懒解析的 JSON 对象；空字节、非法 JSON、非对象 JSON、非法 UTF-8
  /// 一律为 null，不抛异常。
  late final Map<String, dynamic>? json = _parse();

  /// 客户端请求的原始模型名（映射前）；字段缺失或不是字符串时为 null。
  late final String? originalModel = _readOriginalModel();

  Map<String, dynamic>? _parse() {
    if (bytes.isEmpty) return null;
    try {
      // 统一放宽 UTF-8：请求体不是合法 UTF-8 时仍需原样转发，不能因为
      // 解析失败就中断。allowMalformed 会把坏字节替换成 U+FFFD，
      // jsonDecode 随后多半抛 FormatException，最终仍是 null。
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _readOriginalModel() {
    final model = json?['model'];
    return model is String ? model : null;
  }
}
