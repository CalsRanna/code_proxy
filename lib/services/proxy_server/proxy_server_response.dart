/// 代理服务器响应
class ProxyServerResponse {
  /// HTTP 状态码
  final int statusCode;

  /// 响应头
  final Map<String, String> headers;

  /// 响应体
  final String body;

  /// 响应时间（毫秒）
  final int responseTime;

  const ProxyServerResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.responseTime,
  });
}
