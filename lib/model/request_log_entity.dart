/// 请求日志模型
class RequestLogEntity {
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

  /// 实际使用的模型
  final String? model;

  /// 客户端请求的原始模型（映射前）
  final String? originalModel;

  /// 输入 token 数量
  final int? inputTokens;

  /// 输出 token 数量
  final int? outputTokens;

  /// 错误信息（仅在非成功请求时保存）
  final String? errorMessage;

  const RequestLogEntity({
    required this.id,
    required this.timestamp,
    required this.endpointId,
    required this.endpointName,
    required this.path,
    this.method = 'GET',
    this.statusCode,
    this.responseTime,
    this.model,
    this.originalModel,
    this.inputTokens,
    this.outputTokens,
    this.errorMessage,
  });

  /// 从 JSON 反序列化
  factory RequestLogEntity.fromJson(Map<String, dynamic> json) {
    return RequestLogEntity(
      id: json['id'] as String,
      timestamp: json['timestamp'] as int,
      endpointId: json['endpointId'] as String,
      endpointName: json['endpointName'] as String,
      path: json['path'] as String,
      method: json['method'] as String? ?? 'GET',
      statusCode: json['statusCode'] as int?,
      responseTime: json['responseTime'] as int?,
      model: json['model'] as String?,
      originalModel: json['originalModel'] as String?,
      inputTokens: json['inputTokens'] as int?,
      outputTokens: json['outputTokens'] as int?,
      errorMessage: json['errorMessage'] as String?,
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
      'model': model,
      'originalModel': originalModel,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'errorMessage': errorMessage,
    };
  }

  @override
  String toString() {
    return 'RequestLog(id: $id, method: $method, path: $path, statusCode: $statusCode)';
  }

  /// 复制并修改部分字段
  RequestLogEntity copyWith({
    String? id,
    int? timestamp,
    String? endpointId,
    String? endpointName,
    String? path,
    String? method,
    int? statusCode,
    int? responseTime,
    String? model,
    String? originalModel,
    int? inputTokens,
    int? outputTokens,
    String? errorMessage,
  }) {
    return RequestLogEntity(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      endpointId: endpointId ?? this.endpointId,
      endpointName: endpointName ?? this.endpointName,
      path: path ?? this.path,
      method: method ?? this.method,
      statusCode: statusCode ?? this.statusCode,
      responseTime: responseTime ?? this.responseTime,
      model: model ?? this.model,
      originalModel: originalModel ?? this.originalModel,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
