/// 代理服务器请求
class ProxyServerRequest {
  /// HTTP 方法 (GET, POST, PUT, DELETE 等)
  final String method;

  /// 请求路径
  final String path;

  /// 请求头
  final Map<String, String> headers;

  /// 请求体
  final String body;

  const ProxyServerRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });
}
