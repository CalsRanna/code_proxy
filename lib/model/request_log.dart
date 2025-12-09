/// 日志级别枚举
enum LogLevel {
  info,
  warning,
  error,
}

/// 请求日志模型
class RequestLog {
  /// 日志 ID
  final String id;

  /// 时间戳
  final int timestamp;

  /// 端点 ID
  final String endpointId;

  /// 端点名称（冗余，便于显示）
  final String endpointName;

  /// 请求路径
  final String path;

  /// 请求方法
  final String method;

  /// HTTP 状态码
  final int? statusCode;

  /// 响应时间（毫秒）
  final int? responseTime;

  /// 是否成功
  final bool success;

  /// 错误信息
  final String? error;

  /// 日志级别
  final LogLevel level;

  /// 请求头
  final Map<String, dynamic>? header;

  /// 消息内容
  final String? message;

  /// 实际使用的模型
  final String? model;

  /// 输入 token 数量
  final int? inputTokens;

  /// 输出 token 数量
  final int? outputTokens;

  /// 原始请求头（String 格式）
  final String? rawHeader;

  /// 原始请求体（String 格式）
  final String? rawRequest;

  /// 原始响应体（String 格式）
  final String? rawResponse;

  const RequestLog({
    required this.id,
    required this.timestamp,
    required this.endpointId,
    required this.endpointName,
    required this.path,
    this.method = 'GET',
    this.statusCode,
    this.responseTime,
    this.success = true,
    this.error,
    this.level = LogLevel.info,
    this.header,
    this.message,
    this.model,
    this.inputTokens,
    this.outputTokens,
    this.rawHeader,
    this.rawRequest,
    this.rawResponse,
  });

  /// 从 JSON 反序列化
  factory RequestLog.fromJson(Map<String, dynamic> json) {
    return RequestLog(
      id: json['id'] as String,
      timestamp: json['timestamp'] as int,
      endpointId: json['endpointId'] as String,
      endpointName: json['endpointName'] as String,
      path: json['path'] as String,
      method: json['method'] as String? ?? 'GET',
      statusCode: json['statusCode'] as int?,
      responseTime: json['responseTime'] as int?,
      success: json['success'] as bool? ?? true,
      error: json['error'] as String?,
      level: _logLevelFromString(json['level'] as String?),
      header: json['header'] as Map<String, dynamic>?,
      message: json['message'] as String?,
      model: json['model'] as String?,
      inputTokens: json['inputTokens'] as int?,
      outputTokens: json['outputTokens'] as int?,
      rawHeader: json['rawHeader'] as String?,
      rawRequest: json['rawRequest'] as String?,
      rawResponse: json['rawResponse'] as String?,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp,
      'endpointId': endpointId,
      'endpointName': endpointName,
      'path': path,
      'method': method,
      'statusCode': statusCode,
      'responseTime': responseTime,
      'success': success,
      'error': error,
      'level': level.name,
      'header': header,
      'message': message,
      'model': model,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'rawHeader': rawHeader,
      'rawRequest': rawRequest,
      'rawResponse': rawResponse,
    };
  }

  @override
  String toString() {
    return 'RequestLog(id: $id, method: $method, path: $path, success: $success, statusCode: $statusCode)';
  }

  /// 将字符串转换为 LogLevel
  static LogLevel _logLevelFromString(String? value) {
    switch (value) {
      case 'info':
        return LogLevel.info;
      case 'warning':
        return LogLevel.warning;
      case 'error':
        return LogLevel.error;
      default:
        return LogLevel.info;
    }
  }
}
