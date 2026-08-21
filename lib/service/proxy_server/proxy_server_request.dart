/// 代理服务器请求
class ProxyServerRequest {
  /// HTTP 方法 (GET, POST, PUT, DELETE 等)
  final String method;

  /// 请求路径
  final String path;

  /// 原始请求头（客户端发给代理的）
  final Map<String, String> headers;

  /// 转发请求头（代理发给上游 API 的）
  final Map<String, String>? forwardedHeaders;

  /// 请求体（发往上游的，已完成模型映射与协议转换）
  final String body;

  /// 客户端请求的原始模型（映射前）
  final String? originalModel;

  /// 客户端发来的原始请求体（映射与协议转换前），用于审计对照。
  /// 仅在与 [body] 存在差异时由审计层持久化。
  final String? originalBody;

  const ProxyServerRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
    this.originalModel,
    this.originalBody,
    this.forwardedHeaders,
  });
}
