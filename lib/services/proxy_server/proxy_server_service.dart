import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

class ProxyServerService {
  static final _defaultAnthropicDefaultHaikuModel = 'claude-haiku-4-5-20251001';
  static final _defaultAnthropicDefaultSonnetModel =
      'claude-sonnet-4-5-20250929';
  static final _defaultAnthropicDefaultOpusModel = 'claude-opus-4-5-20251101';
  static final _defaultAnthropicModel = 'claude-sonnet-4-5-20250929';
  static final _defaultAnthropicSmallFastModel = 'claude-haiku-4-5-20251001';

  final ProxyServerConfig config;
  final void Function(EndpointEntity)? onEndpointUnavailable;
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  onRequestCompleted;
  List<EndpointEntity> _endpoints = [];

  final http.Client _httpClient = http.Client();

  HttpServer? _server;

  ProxyServerService({
    required this.config,
    this.onRequestCompleted,
    this.onEndpointUnavailable,
  });

  set endpoints(List<EndpointEntity> endpoints) => _endpoints = endpoints;

  Future<void> dispose() async {
    await stop();
    _httpClient.close();
  }

  Future<void> start() async {
    if (_server != null) {
      throw StateError('Server is already running');
    }

    _server = await shelf_io.serve(
      _proxyHandler,
      config.address,
      config.port,
      poweredByHeader: null,
    );
  }

  Future<void> stop() async {
    if (_server == null) return;
    await _server!.close(force: false);
    _server = null;
  }

  String _decodeBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      return '';
    }
  }

  /// 转发请求
  Future<http.StreamedResponse> _forwardRequest(http.Request request) async {
    final response = await _httpClient.send(request);
    LoggerUtil.instance.d(
      'Forward request to ${request.url}, ${response.statusCode}',
    );
    return response;
  }

  Future<shelf.Response> _handleNormalResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> modifiedRequestBody,
    int startTime,
  ) async {
    final responseBodyBytes = await response.stream.toBytes();
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: utf8.decode(modifiedRequestBody, allowMalformed: true),
      headers: request.headers,
    );
    final proxyResponse = ProxyServerResponse(
      statusCode: response.statusCode,
      body: utf8.decode(responseBodyBytes, allowMalformed: true),
      headers: response.headers,
      responseTime: responseTime,
    );
    onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);

    // 清理响应头，移除可能导致问题的头部
    final cleanHeaders = Map<String, String>.from(response.headers);
    cleanHeaders.remove('transfer-encoding');
    cleanHeaders.remove('content-encoding');
    cleanHeaders.remove('content-length');

    return shelf.Response(
      response.statusCode,
      headers: cleanHeaders,
      body: responseBodyBytes,
    );
  }

  shelf.Response _handleStreamResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> modifiedRequestBody,
    int startTime,
  ) {
    final responseBodyBytes = <int>[];
    int? firstByteTime;

    final transformedStream = response.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (List<int> chunk, EventSink<List<int>> sink) {
          firstByteTime ??= DateTime.now().millisecondsSinceEpoch;
          responseBodyBytes.addAll(chunk);
          sink.add(chunk);
        },
        handleDone: (EventSink<List<int>> sink) {
          final endTime = DateTime.now().millisecondsSinceEpoch;
          final totalTime = endTime - startTime;
          final timeToFirstByte = firstByteTime ?? endTime - startTime;

          final proxyRequest = ProxyServerRequest(
            path: request.url.path,
            method: request.method,
            body: utf8.decode(modifiedRequestBody, allowMalformed: true),
            headers: request.headers,
          );

          final proxyResponse = ProxyServerResponse(
            statusCode: response.statusCode,
            body: utf8.decode(responseBodyBytes, allowMalformed: true),
            headers: response.headers,
            responseTime: totalTime,
            timeToFirstByte: timeToFirstByte,
          );

          onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
          sink.close();
        },
        handleError: (error, stackTrace, EventSink<List<int>> sink) {
          // 记录错误
          _recordException(
            endpoint: endpoint,
            request: request,
            startTime: startTime,
            modifiedRequestBody: modifiedRequestBody,
            error: error,
          );
          sink.addError(error, stackTrace);
        },
      ),
    );

    // 清理响应头，移除可能导致问题的头部
    final cleanHeaders = Map<String, String>.from(response.headers);
    cleanHeaders.remove('transfer-encoding');
    cleanHeaders.remove('content-encoding');
    cleanHeaders.remove('content-length');

    return shelf.Response(
      response.statusCode,
      headers: cleanHeaders,
      body: transformedStream,
    );
  }

  /// 检测是否是流式响应（SSE 或其他流式格式）
  bool _isStreamResponse(Map<String, String> headers) {
    final contentType = headers['content-type'] ?? '';
    return contentType.contains('text/event-stream') ||
        contentType.contains('application/stream+json');
  }

  /// 根据原始模型名称和端点配置获取映射后的模型
  String? _mapModel(String? originalModel, EndpointEntity endpoint) {
    return switch (originalModel) {
      'ANTHROPIC_DEFAULT_HAIKU_MODEL' =>
        endpoint.anthropicDefaultHaikuModel ??
            _defaultAnthropicDefaultHaikuModel,
      'ANTHROPIC_DEFAULT_SONNET_MODEL' =>
        endpoint.anthropicDefaultSonnetModel ??
            _defaultAnthropicDefaultSonnetModel,
      'ANTHROPIC_DEFAULT_OPUS_MODEL' =>
        endpoint.anthropicDefaultOpusModel ?? _defaultAnthropicDefaultOpusModel,
      'ANTHROPIC_MODEL' => endpoint.anthropicModel ?? _defaultAnthropicModel,
      'ANTHROPIC_SMALL_FAST_MODEL' =>
        endpoint.anthropicSmallFastModel ?? _defaultAnthropicSmallFastModel,
      _ => _defaultAnthropicModel,
    };
  }

  /// 替换请求 body 中的 model 字段
  List<int> _prepareBody(List<int> rawBody, EndpointEntity endpoint) {
    try {
      final bodyString = _decodeBytes(rawBody);
      if (bodyString.isEmpty) return rawBody;

      // 解析 JSON
      final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;

      // 如果有 model 字段,进行替换
      if (bodyJson.containsKey('model')) {
        final originalModel = bodyJson['model'] as String?;
        final mappedModel = _mapModel(originalModel, endpoint);

        if (mappedModel != null && mappedModel.isNotEmpty) {
          bodyJson['model'] = mappedModel;
          LoggerUtil.instance.d(
            'Model mapping: $originalModel → $mappedModel (${endpoint.name})',
          );
        }
      }

      // 重新编码为 JSON
      return utf8.encode(jsonEncode(bodyJson));
    } catch (e) {
      // 如果解析失败,返回原始 body
      LoggerUtil.instance.w('Failed to parse/replace model in body: $e');
      return rawBody;
    }
  }

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

  /// 准备转发请求，包括替换 headers、body 和组装 URL
  http.Request _prepareRequest(
    shelf.Request request,
    EndpointEntity endpoint,
    List<int> rawBody,
  ) {
    // 组装目标 URL
    Uri uri = _prepareUrl(endpoint, request);

    // 准备 headers
    Map<String, String> headers = _prepareHeaders(request, endpoint);

    // 替换 body 中的 model
    final body = _prepareBody(rawBody, endpoint);

    return http.Request(request.method, uri)
      ..headers.addAll(headers)
      ..bodyBytes = body;
  }

  Uri _prepareUrl(EndpointEntity endpoint, shelf.Request request) {
    final url =
        '${endpoint.anthropicBaseUrl}/${request.url.path}?${request.url.query}';
    final uri = Uri.parse(url);
    return uri;
  }

  Future<shelf.Response> _proxyHandler(shelf.Request request) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final rawBody = await request.read().expand((x) => x).toList();

    for (var endpoint in _endpoints) {
      // 准备完整的转发请求
      final forwardRequest = _prepareRequest(request, endpoint, rawBody);

      for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
        try {
          final response = await _forwardRequest(forwardRequest);
          final statusCode = response.statusCode;

          final isStreamResponse = _isStreamResponse(response.headers);
          if (isStreamResponse) {
            return _handleStreamResponse(
              response,
              endpoint,
              request,
              forwardRequest.bodyBytes,
              startTime,
            );
          } else {
            final shelfResponse = await _handleNormalResponse(
              response,
              endpoint,
              request,
              forwardRequest.bodyBytes,
              startTime,
            );

            if (statusCode >= 200 && statusCode < 300) {
              return shelfResponse;
            } else if (statusCode >= 400 && statusCode < 500) {
              return shelfResponse;
            } else {
              // 5xx 错误：重试当前端点
              if (attempt < config.maxRetries) {
                continue;
              }
              // 达到最大重试次数，尝试下一个端点
              break;
            }
          }
        } catch (e) {
          // 异常：重试当前端点
          if (attempt < config.maxRetries) {
            continue;
          }
          // 达到最大重试次数，记录异常并尝试下一个端点
          _recordException(
            endpoint: endpoint,
            request: request,
            startTime: startTime,
            modifiedRequestBody: forwardRequest.bodyBytes,
            error: e,
          );
          break;
        }
      }
    }
    return shelf.Response(
      500,
      body: 'Internal Server Error',
      headers: {'content-type': 'text/plain'},
    );
  }

  void _recordException({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required int startTime,
    required List<int> modifiedRequestBody,
    required Object error,
  }) {
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: utf8.decode(modifiedRequestBody, allowMalformed: true),
      headers: request.headers,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: 0,
      body: error.toString(),
      headers: {},
      responseTime: responseTime,
    );

    onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }
}
