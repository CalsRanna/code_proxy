import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_model_mapper.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

/// 请求处理器 - 负责请求准备和转发
class ProxyServerRequestHandler {
  final http.Client _httpClient;

  ProxyServerRequestHandler() : _httpClient = http.Client();

  void close() {
    _httpClient.close();
  }

  /// 转发HTTP请求
  Future<http.StreamedResponse> forwardRequest(http.Request request) async {
    final response = await _httpClient.send(request);
    return response;
  }

  /// 为端点准备HTTP请求
  http.Request prepareRequest(
    shelf.Request request,
    EndpointEntity endpoint,
    List<int> rawBody,
  ) {
    // 构建目标URL
    final uri = _buildTargetUrl(endpoint, request);

    // 准备请求头
    final headers = _prepareHeaders(request, endpoint);

    // 处理请求体中的模型映射
    final processedBody = _processRequestBody(rawBody, endpoint);

    return http.Request(request.method, uri)
      ..headers.addAll(headers)
      ..bodyBytes = processedBody;
  }

  /// 构建目标URL
  Uri _buildTargetUrl(EndpointEntity endpoint, shelf.Request request) {
    final url =
        '${endpoint.anthropicBaseUrl}/${request.url.path}?${request.url.query}';
    return Uri.parse(url);
  }

  /// 准备请求头
  Map<String, String> _prepareHeaders(
    shelf.Request request,
    EndpointEntity endpoint,
  ) {
    final headers = Map<String, String>.from(request.headers);
    headers['x-api-key'] = endpoint.anthropicAuthToken ?? '';
    headers.remove('authorization');
    headers.remove('host');
    headers.remove('content-length');
    return headers;
  }

  /// 处理请求体中的模型映射
  List<int> _processRequestBody(List<int> rawBody, EndpointEntity endpoint) {
    try {
      final bodyString = utf8.decode(rawBody, allowMalformed: true);
      if (bodyString.isEmpty) return rawBody;

      final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;

      if (bodyJson.containsKey('model')) {
        final originalModel = bodyJson['model'] as String?;
        final mappedModel = ProxyServerModelMapper.mapModel(
          originalModel,
          endpoint: endpoint,
        );

        LoggerUtil.instance.d(
          'Model mapping: endpoint=${endpoint.name}, original=$originalModel, mapped=$mappedModel',
        );

        if (mappedModel != null && mappedModel.isNotEmpty) {
          bodyJson['model'] = mappedModel;
        }
      }

      return utf8.encode(jsonEncode(bodyJson));
    } catch (e) {
      LoggerUtil.instance.w('Failed to parse/replace model in body: $e');
      return rawBody;
    }
  }
}
