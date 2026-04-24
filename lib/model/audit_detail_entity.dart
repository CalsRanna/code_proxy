class AuditDetailEntity {
  final Map<String, String> originalRequestHeaders;
  final Map<String, String> forwardedRequestHeaders;
  final String requestBody;
  final Map<String, String> originalResponseHeaders;
  final Map<String, String> forwardedResponseHeaders;
  final String responseBody;

  const AuditDetailEntity({
    required this.originalRequestHeaders,
    required this.forwardedRequestHeaders,
    required this.requestBody,
    required this.originalResponseHeaders,
    required this.forwardedResponseHeaders,
    required this.responseBody,
  });
}