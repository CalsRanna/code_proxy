import 'dart:convert';

/// 请求数据
class RequestData {
  /// 请求头
  final Map<String, String> headers;

  /// 请求体
  final String body;

  const RequestData({
    required this.headers,
    required this.body,
  });

  Map<String, dynamic> toJson() {
    return {
      'headers': headers,
      'body': body,
    };
  }

  factory RequestData.fromJson(Map<String, dynamic> json) {
    return RequestData(
      headers: Map<String, String>.from(json['headers'] as Map),
      body: json['body'] as String,
    );
  }
}

/// 响应数据
class ResponseData {
  /// 响应头
  final Map<String, String> headers;

  /// 响应体
  final String body;

  const ResponseData({
    required this.headers,
    required this.body,
  });

  Map<String, dynamic> toJson() {
    return {
      'headers': headers,
      'body': body,
    };
  }

  factory ResponseData.fromJson(Map<String, dynamic> json) {
    return ResponseData(
      headers: Map<String, String>.from(json['headers'] as Map),
      body: json['body'] as String,
    );
  }
}

/// 请求日志文件模型（存储到 JSONL 文件）
class RequestLogFile {
  /// 日志 ID
  final String id;

  /// 时间戳
  final int timestamp;

  /// 端点 ID
  final String endpointId;

  /// 端点名称
  final String endpointName;

  /// 请求路径
  final String path;

  /// 请求方法
  final String method;

  /// HTTP 状态码
  final int? statusCode;

  /// 请求数据
  final RequestData request;

  /// 响应数据
  final ResponseData response;

  const RequestLogFile({
    required this.id,
    required this.timestamp,
    required this.endpointId,
    required this.endpointName,
    required this.path,
    required this.method,
    this.statusCode,
    required this.request,
    required this.response,
  });

  /// 转换为 JSON（用于写入文件）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp,
      'endpointId': endpointId,
      'endpointName': endpointName,
      'path': path,
      'method': method,
      'statusCode': statusCode,
      'request': request.toJson(),
      'response': response.toJson(),
    };
  }

  /// 从 JSON 反序列化
  factory RequestLogFile.fromJson(Map<String, dynamic> json) {
    return RequestLogFile(
      id: json['id'] as String,
      timestamp: json['timestamp'] as int,
      endpointId: json['endpointId'] as String,
      endpointName: json['endpointName'] as String,
      path: json['path'] as String,
      method: json['method'] as String,
      statusCode: json['statusCode'] as int?,
      request: RequestData.fromJson(json['request'] as Map<String, dynamic>),
      response:
          ResponseData.fromJson(json['response'] as Map<String, dynamic>),
    );
  }

  /// 转换为 JSONL 行（单行 JSON 字符串）
  String toJsonLine() {
    return jsonEncode(toJson());
  }

  /// 从 JSONL 行解析
  factory RequestLogFile.fromJsonLine(String line) {
    final json = jsonDecode(line) as Map<String, dynamic>;
    return RequestLogFile.fromJson(json);
  }

  @override
  String toString() {
    return 'RequestLogFile(id: $id, path: $path, method: $method, statusCode: $statusCode)';
  }
}
