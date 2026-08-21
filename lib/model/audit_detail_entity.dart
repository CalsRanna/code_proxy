class AuditDetailEntity {
  final Map<String, String> originalRequestHeaders;
  final Map<String, String> forwardedRequestHeaders;
  final String requestBody;

  /// 客户端发来的原始请求体（转换前）；无差异时为空串
  final String originalRequestBody;
  final Map<String, String> originalResponseHeaders;
  final Map<String, String> forwardedResponseHeaders;
  final String responseBody;

  /// 上游原始响应体（转换前）；无差异时为空串
  final String rawResponseBody;

  const AuditDetailEntity({
    required this.originalRequestHeaders,
    required this.forwardedRequestHeaders,
    required this.requestBody,
    this.originalRequestBody = '',
    required this.originalResponseHeaders,
    required this.forwardedResponseHeaders,
    required this.responseBody,
    this.rawResponseBody = '',
  });
}