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

  /// 请求体
  final String body;

  /// 客户端请求的原始模型（映射前）
  final String? originalModel;

  const ProxyServerRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
    this.originalModel,
    this.forwardedHeaders,
  });
}
