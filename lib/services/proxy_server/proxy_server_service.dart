import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/proxy_server_config_entity.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:http/http.dart' as http;
import '../claude_code_config_manager.dart';

/// 代理请求数据
class ProxyRequest {
  final String path;
  final String method;
  final String body;
  final Map<String, String> headers;

  ProxyRequest({
    required this.path,
    required this.method,
    required this.body,
    required this.headers,
  });
}

/// 代理响应数据
class ProxyResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  ProxyResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });
}

/// 请求完成回调
typedef RequestCompletedCallback =
    void Function({
      required String endpointId,
      required String endpointName,
      required bool success,
      required int responseTime,
      required ProxyRequest request,
      required ProxyResponse response,
      String? error,
    });

/// 端点不可用回调
typedef EndpointUnavailableCallback =
    void Function(String endpointId, String endpointName);

class ProxyServer {
  final ProxyServerConfigEntity config;
  final List<EndpointEntity> Function() getEndpoints;
  final ClaudeCodeConfigManager claudeCodeConfigManager;

  /// 回调：请求完成（成功或失败）
  final RequestCompletedCallback? onRequestCompleted;

  /// 回调：端点不可用
  final EndpointUnavailableCallback? onEndpointUnavailable;

  HttpServer? _server;
  final http.Client _httpClient = http.Client();
  final Map<String, int> _failureCount = {};
  static const int _maxConsecutiveFailures = 3;

  ProxyServer({
    required this.config,
    required this.getEndpoints,
    required this.claudeCodeConfigManager,
    this.onRequestCompleted,
    this.onEndpointUnavailable,
  });

  // =========================
  // 服务器控制
  // =========================

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

  bool get isRunning => _server != null;

  Future<shelf.Response> _proxyHandler(shelf.Request request) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final bodyBytes = await request.read().toList();
    final triedEndpoints = <String>{};

    // 重试循环
    for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
      final endpoint = _selectAvailableEndpoint(triedEndpoints);

      if (endpoint == null) {
        return _handleNoEndpoints(request, startTime, bodyBytes);
      }

      triedEndpoints.add(endpoint.id);

      try {
        final response = await _forwardRequest(request, endpoint, bodyBytes);
        final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;
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

    return shelf.Response(
      500,
      body: 'Internal Server Error',
      headers: {'content-type': 'text/plain'},
    );
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

  EndpointEntity? _selectAvailableEndpoint(Set<String> triedEndpoints) {
    final allEndpoints = getEndpoints();
    for (final endpoint in allEndpoints) {
      if (endpoint.enabled && !triedEndpoints.contains(endpoint.id)) {
        return endpoint;
      }
    }
    return null;
  }

  shelf.Response _handleNoEndpoints(
    shelf.Request request,
    int startTime,
    List<List<int>> bodyBytes,
  ) {
    final error = 'No available endpoints';
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    final proxyRequest = ProxyRequest(
      path: request.url.path,
      method: request.method,
      body: _decodeBytes(bodyBytes),
      headers: request.headers,
    );

    final proxyResponse = ProxyResponse(
      statusCode: 503,
      body: error,
      headers: {'content-type': 'text/plain'},
    );

    onRequestCompleted?.call(
      endpointId: 'unknown',
      endpointName: 'unknown',
      success: false,
      responseTime: responseTime,
      request: proxyRequest,
      response: proxyResponse,
      error: error,
    );

    return shelf.Response(
      503,
      body: 'Service Unavailable: $error',
      headers: {'content-type': 'text/plain'},
    );
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
    Future(() {
      try {
        final success = statusCode >= 200 && statusCode < 300;

        final proxyRequest = ProxyRequest(
          path: request.url.path,
          method: request.method,
          body: _decodeBytes(requestBytes),
          headers: request.headers,
        );

        final proxyResponse = ProxyResponse(
          statusCode: statusCode,
          body: utf8.decode(responseBytes, allowMalformed: true),
          headers: responseHeaders,
        );

        onRequestCompleted?.call(
          endpointId: endpoint.id,
          endpointName: endpoint.name,
          success: success,
          responseTime: responseTime,
          request: proxyRequest,
          response: proxyResponse,
          error: success ? null : 'HTTP $statusCode',
        );
      } catch (e) {
        LoggerUtil.instance.e('Failed to record request: $e');
      }
    });
  }

  void _recordException({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required int startTime,
    required List<List<int>> bodyBytes,
    required Object error,
  }) {
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    final proxyRequest = ProxyRequest(
      path: request.url.path,
      method: request.method,
      body: _decodeBytes(bodyBytes),
      headers: request.headers,
    );

    final proxyResponse = ProxyResponse(statusCode: 0, body: '', headers: {});

    onRequestCompleted?.call(
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      success: false,
      responseTime: responseTime,
      request: proxyRequest,
      response: proxyResponse,
      error: error.toString(),
    );
  }

  void _handleFailure(EndpointEntity endpoint) {
    _failureCount[endpoint.id] = (_failureCount[endpoint.id] ?? 0) + 1;

    if (_failureCount[endpoint.id]! >= _maxConsecutiveFailures) {
      onEndpointUnavailable?.call(endpoint.id, endpoint.name);
      LoggerUtil.instance.e(
        'Endpoint ${endpoint.name} reached $_maxConsecutiveFailures failures',
      );
    }
  }

  String _decodeBytes(List<List<int>> bytes) {
    try {
      return utf8.decode(bytes.expand((x) => x).toList(), allowMalformed: true);
    } catch (e) {
      return '';
    }
  }

  Future<void> dispose() async {
    await stop();
    _httpClient.close();
  }
}
