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

  String _decodeBytes(List<List<int>> bytes) {
    try {
      return utf8.decode(bytes.expand((x) => x).toList(), allowMalformed: true);
    } catch (e) {
      return '';
    }
  }

  Future<http.StreamedResponse> _forwardRequest(
    shelf.Request request,
    EndpointEntity endpoint,
    List<List<int>> bodyBytes,
  ) async {
    final uri = Uri.parse(endpoint.anthropicBaseUrl ?? '').replace(
      path: request.url.path,
      query: request.url.query.isEmpty ? null : request.url.query,
    );
    final headers = Map<String, String>.from(request.headers);
    // headers['authorization'] = 'Bearer ${endpoint.anthropicAuthToken ?? ''}';
    headers['x-api-key'] = endpoint.anthropicAuthToken ?? '';
    headers.remove('authorization');
    headers.remove('host');
    headers.remove('content-length');
    final forwardRequest = http.Request(request.method, uri)
      ..headers.addAll(headers)
      ..bodyBytes = bodyBytes.expand((x) => x).toList();

    return await _httpClient.send(forwardRequest);
  }

  Future<shelf.Response> _handleNormalResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<List<int>> requestBodyBytes,
    int startTime,
  ) async {
    final responseBodyBytes = await response.stream.toBytes();
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: _decodeBytes(requestBodyBytes),
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
    List<List<int>> requestBodyBytes,
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
            body: _decodeBytes(requestBodyBytes),
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
            bodyBytes: requestBodyBytes,
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

  Future<shelf.Response> _proxyHandler(shelf.Request request) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final bodyBytes = await request.read().toList();

    for (var endpoint in _endpoints) {
      for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
        try {
          final response = await _forwardRequest(request, endpoint, bodyBytes);
          final statusCode = response.statusCode;
          LoggerUtil.instance.d(
            'Forward request to ${endpoint.name}, $statusCode',
          );

          final isStreamResponse = _isStreamResponse(response.headers);
          if (isStreamResponse) {
            return _handleStreamResponse(
              response,
              endpoint,
              request,
              bodyBytes,
              startTime,
            );
          } else {
            final shelfResponse = await _handleNormalResponse(
              response,
              endpoint,
              request,
              bodyBytes,
              startTime,
            );

            if (statusCode >= 200 && statusCode < 300) {
              return shelfResponse;
            } else if (statusCode >= 400 && statusCode < 500) {
              return shelfResponse;
            } else {
              if (attempt < config.maxRetries) {
                continue;
              }
              return shelfResponse;
            }
          }
        } catch (e) {
          if (attempt < config.maxRetries) {
            continue;
          }
          _recordException(
            endpoint: endpoint,
            request: request,
            startTime: startTime,
            bodyBytes: bodyBytes,
            error: e,
          );
          return shelf.Response(
            500,
            body: 'Internal Server Error',
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
}
