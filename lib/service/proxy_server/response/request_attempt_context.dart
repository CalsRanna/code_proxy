import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:shelf/shelf.dart' as shelf;

/// 单次上游尝试的请求数据；重试之间不共享计时和转发内容。
class RequestAttemptContext {
  final EndpointEntity endpoint;
  final shelf.Request request;
  final List<int> originalRequestBodyBytes;
  final List<int>? mappedRequestBodyBytes;
  final Map<String, String>? forwardedHeaders;

  /// 客户端请求的原始模型名（映射前）。
  final String? originalModel;

  /// 本次尝试实际写进转发请求体的模型名；请求体不可解析时为 null。
  final String? mappedModel;

  /// 请求准备阶段失败时为 null，发送后的耗时不包含此前退避。
  final int? startTime;

  RequestAttemptContext({
    required this.endpoint,
    required this.request,
    required this.originalRequestBodyBytes,
    required this.originalModel,
    required this.startTime,
    this.mappedModel,
    this.mappedRequestBodyBytes,
    this.forwardedHeaders,
  });

  List<int> get forwardedRequestBodyBytes =>
      mappedRequestBodyBytes ?? originalRequestBodyBytes;
}
