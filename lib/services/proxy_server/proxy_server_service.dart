import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/proxy_server_config_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

class ProxyServerService {
  final ProxyServerConfigEntity config;
  final void Function(
    EndpointEntity,
    ProxyServerRequest,
    ProxyServerResponse,
  )? onRequestCompleted;
  final void Function(EndpointEntity)? onEndpointUnavailable;

  HttpServer? _server;
  final http.Client _httpClient = http.Client();
  final Map<String, int> _failureCount = {};
  List<EndpointEntity> _endpoints = [];

  /// 最大连续失败次数
  static const int _maxConsecutiveFailures = 3;

  ProxyServerService({
    required this.config,
    this.onRequestCompleted,
    this.onEndpointUnavailable,
  });

  set endpoints(List<EndpointEntity> endpoints) => _endpoints = endpoints;

  bool get isRunning => _server != null;

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
    _failureCount.clear();
  }

  String _decodeBytes(List<List<int>> bytes) {
    try {
      return utf8.decode(bytes.expand((x) => x).toList(), allowMalformed: true);
    } catch (e) {
      return '';
    }
  }

  Future<shelf.Response> _forwardRequest(
    shelf.Request request,
    EndpointEntity endpoint,
    List<List<int>> bodyBytes,
  ) async {
    final uri = Uri.parse(endpoint.url).replace(
      path: request.url.path,
      query: request.url.query.isEmpty ? null : request.url.query,
    );
    final headers = Map<String, String>.from(request.headers);
    headers['x-api-key'] = endpoint.apiKey ?? '';

    final forwardRequest = http.Request(request.method, uri)
      ..headers.addAll(headers)
      ..bodyBytes = bodyBytes.expand((x) => x).toList();

    final response = await _httpClient.send(forwardRequest);
    final responseBody = await response.stream.toBytes();

    return shelf.Response(
      response.statusCode,
      headers: response.headers,
      body: responseBody,
    );
  }

  void _handleFailure(EndpointEntity endpoint) {
    _failureCount[endpoint.id] = (_failureCount[endpoint.id] ?? 0) + 1;

    if (_failureCount[endpoint.id]! >= _maxConsecutiveFailures) {
      onEndpointUnavailable?.call(endpoint);
      LoggerUtil.instance.e(
        'Endpoint ${endpoint.name} reached $_maxConsecutiveFailures failures',
      );
    }
  }

  Future<shelf.Response> _proxyHandler(shelf.Request request) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final bodyBytes = await request.read().toList();
    final triedEndpoints = <String>{};

    for (var endpoint in _endpoints) {
      for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
        triedEndpoints.add(endpoint.id);

        try {
          final response = await _forwardRequest(request, endpoint, bodyBytes);
          final responseTime =
              DateTime.now().millisecondsSinceEpoch - startTime;
          final responseBodyBytes = await response.read().toList();
          final flattenedResponse = responseBodyBytes.expand((x) => x).toList();
          final statusCode = response.statusCode;

          // 记录请求（异步，不阻塞响应）
          _recordRequest(
            endpoint: endpoint,
            request: request,
            statusCode: statusCode,
            responseTime: responseTime,
            requestBytes: bodyBytes,
            responseBytes: flattenedResponse,
            responseHeaders: response.headers,
          );

          // 根据状态码处理
          if (statusCode >= 200 && statusCode < 300) {
            // 2xx 成功
            _failureCount[endpoint.id] = 0;
            return shelf.Response(
              statusCode,
              body: flattenedResponse,
              headers: response.headers,
            );
          } else if (statusCode >= 400 && statusCode < 500) {
            // 4xx 客户端错误，不重试
            _handleFailure(endpoint);
            return shelf.Response(
              statusCode,
              body: flattenedResponse,
              headers: response.headers,
            );
          } else {
            // 5xx 服务器错误，可重试
            _handleFailure(endpoint);
            if (attempt < config.maxRetries) {
              continue;
            }
            return shelf.Response(
              statusCode,
              body: flattenedResponse,
              headers: response.headers,
            );
          }
        } catch (e) {
          _recordException(
            endpoint: endpoint,
            request: request,
            startTime: startTime,
            bodyBytes: bodyBytes,
            error: e,
          );
          _handleFailure(endpoint);

          if (attempt < config.maxRetries) {
            continue;
          }

          return shelf.Response(
            502,
            body: 'Bad Gateway: $e',
            headers: {'content-type': 'text/plain'},
          );
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
    required List<List<int>> bodyBytes,
    required Object error,
  }) {
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: _decodeBytes(bodyBytes),
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

  void _recordRequest({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required int statusCode,
    required int responseTime,
    required List<List<int>> requestBytes,
    required List<int> responseBytes,
    required Map<String, String> responseHeaders,
  }) {
    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: _decodeBytes(requestBytes),
      headers: request.headers,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: statusCode,
      body: utf8.decode(responseBytes, allowMalformed: true),
      headers: responseHeaders,
      responseTime: responseTime,
    );

    onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }
}
