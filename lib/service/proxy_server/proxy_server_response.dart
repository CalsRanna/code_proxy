/// 代理服务器响应
class ProxyServerResponse {
  /// HTTP 状态码
  final int statusCode;

  /// 原始响应头（上游 API 返回的）
  final Map<String, String> headers;

  /// 转发响应头（代理返回给客户端的，移除了 transfer-encoding 等）
  final Map<String, String>? forwardedHeaders;

  /// 响应时间（毫秒）- 总时间
  final int responseTime;

  /// 首字节时间（毫秒）- Time To First Byte
  /// 对于流式响应（如 SSE），这个值表示接收到第一个数据块的时间
  final int? timeToFirstByte;

  /// Token 使用量 {'input': inputTokens, 'output': outputTokens}
  /// 在 ResponseHandler 中统一解析（流式和非流式）
  /// 值可能为 null 表示解析失败
  final Map<String, int?>? usage;

  /// 错误响应体（仅在非成功状态码时保存）
  /// 包含完整的 API 错误响应或异常信息
  final String? errorBody;

  /// 完整响应体（用于审计日志）
  final String? responseBody;

  const ProxyServerResponse({
    required this.statusCode,
    required this.headers,
    required this.responseTime,
    this.forwardedHeaders,
    this.timeToFirstByte,
    this.usage,
    this.errorBody,
    this.responseBody,
  });
}
