import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:shelf/shelf.dart' as shelf;

/// 单次上游尝试的请求数据；重试之间不共享计时和转发内容。
class RequestAttemptContext {
  final EndpointEntity endpoint;
  final shelf.Request request;
  final List<int> originalRequestBodyBytes;
  final List<int>? mappedRequestBodyBytes;
  final Map<String, String>? forwardedHeaders;

  /// 请求准备阶段失败时为 null，发送后的耗时不包含此前退避。
  final int? startTime;

  RequestAttemptContext({
    required this.endpoint,
    required this.request,
    required this.originalRequestBodyBytes,
    required this.startTime,
    this.mappedRequestBodyBytes,
    this.forwardedHeaders,
  });

  List<int> get forwardedRequestBodyBytes =>
      mappedRequestBodyBytes ?? originalRequestBodyBytes;

  late final String? originalModel = _extractOriginalModel();

  String? _extractOriginalModel() {
    try {
      final body = utf8.decode(originalRequestBodyBytes, allowMalformed: true);
      if (body.isEmpty) return null;
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['model'] as String?;
    } catch (_) {
      return null;
    }
  }
}
