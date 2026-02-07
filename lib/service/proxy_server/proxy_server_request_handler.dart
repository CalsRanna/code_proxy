import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_model_mapper.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

/// 请求处理器 - 负责请求准备和转发
class ProxyServerRequestHandler {
  final http.Client _httpClient;
  final ProxyServerConfig config;

  ProxyServerRequestHandler(this.config) : _httpClient = http.Client();

  void close() {
    _httpClient.close();
  }

  /// 转发HTTP请求
  Future<http.StreamedResponse> forwardRequest(http.Request request) async {
    final response = await _httpClient
        .send(request)
        .timeout(Duration(milliseconds: config.apiTimeoutMs));
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
    // 将 accept-encoding 限制为 gzip, deflate
    //
    // 原因：Dart 标准库仅支持 gzip/deflate 解压，不支持 brotli(br)/zstd。
    // 客户端（如 Claude Code CLI）原始请求中携带 accept-encoding: gzip, deflate, br, zstd，
    // 当上游 API 返回 brotli 压缩的响应时，代理无法解压以提取 token 使用量和记录审计日志。
    // 修改此头不会影响上游处理请求，accept-encoding 是标准的 HTTP 内容协商头，
    // 各类代理和 CDN 在链路中修改它是常规行为。
    //
    // 替代方案：引入第三方包支持 brotli/zstd 解压，保持请求头不变：
    //   - brotli (pub.dev/packages/brotli): 纯 Dart 实现，推荐，无 FFI 依赖
    //   - es_compression (pub.dev/packages/es_compression): FFI 实现，
    //     同时支持 brotli/lz4/zstd，性能更好但需要预编译二进制
    headers['accept-encoding'] = 'gzip, deflate';
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
