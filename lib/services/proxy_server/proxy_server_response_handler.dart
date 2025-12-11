import 'dart:async';
import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

/// 响应处理器 - 负责处理流式和非流式响应
class ProxyServerResponseHandler {
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  _onRequestCompleted;

  ProxyServerResponseHandler({
    void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
    onRequestCompleted,
  }) : _onRequestCompleted = onRequestCompleted;

  /// 处理HTTP响应
  Future<shelf.Response> handleResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> requestBodyBytes,
    int startTime, {
    List<int>? mappedRequestBodyBytes,
  }) async {
    final isStreamResponse = _isStreamResponse(response.headers);

    if (isStreamResponse) {
      return _handleStreamResponse(
        response,
        endpoint,
        request,
        requestBodyBytes,
        startTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
      );
    } else {
      return await _handleNormalResponse(
        response,
        endpoint,
        request,
        requestBodyBytes,
        startTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
      );
    }
  }

  /// 处理非流式响应
  Future<shelf.Response> _handleNormalResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> requestBodyBytes,
    int startTime, {
    List<int>? mappedRequestBodyBytes,
  }) async {
    final responseBodyBytes = await response.stream.toBytes();
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    _recordRequest(
      endpoint: endpoint,
      request: request,
      requestBodyBytes: mappedRequestBodyBytes ?? requestBodyBytes,
      response: response,
      responseBodyBytes: responseBodyBytes,
      responseTime: responseTime,
      timeToFirstByte: null,
    );

    // 清理响应头
    final cleanHeaders = ProxyServerResponseHandler.cleanResponseHeaders(
      response.headers,
    );

    return shelf.Response(
      response.statusCode,
      headers: cleanHeaders,
      body: responseBodyBytes,
    );
  }

  /// 处理流式响应（SSE）
  shelf.Response _handleStreamResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> requestBodyBytes,
    int startTime, {
    List<int>? mappedRequestBodyBytes,
  }) {
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

          _recordRequest(
            endpoint: endpoint,
            request: request,
            requestBodyBytes: mappedRequestBodyBytes ?? requestBodyBytes,
            response: response,
            responseBodyBytes: responseBodyBytes,
            responseTime: totalTime,
            timeToFirstByte: timeToFirstByte,
          );

          sink.close();
        },
        handleError: (error, stackTrace, EventSink<List<int>> sink) {
          // 记录错误统计
          _recordException(
            endpoint: endpoint,
            request: request,
            requestBodyBytes: requestBodyBytes,
            startTime: startTime,
            error: error,
          );
          sink.addError(error, stackTrace);
        },
      ),
    );

    // 清理响应头
    final cleanHeaders = ProxyServerResponseHandler.cleanResponseHeaders(
      response.headers,
    );

    return shelf.Response(
      response.statusCode,
      headers: cleanHeaders,
      body: transformedStream,
    );
  }

  /// 清理响应头，移除可能导致问题的头部
  static Map<String, String> cleanResponseHeaders(Map<String, String> headers) {
    final cleanHeaders = Map<String, String>.from(headers);
    cleanHeaders.remove('transfer-encoding');
    cleanHeaders.remove('content-encoding');
    cleanHeaders.remove('content-length');
    return cleanHeaders;
  }

  /// 检测是否是流式响应（SSE 或其他流式格式）
  bool _isStreamResponse(Map<String, String> headers) {
    final contentType = headers['content-type'] ?? '';
    return contentType.contains('text/event-stream') ||
        contentType.contains('application/stream+json');
  }

  /// 记录请求统计
  void _recordRequest({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required List<int> requestBodyBytes,
    required http.StreamedResponse response,
    required List<int> responseBodyBytes,
    required int responseTime,
    required int? timeToFirstByte,
  }) {
    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: utf8.decode(requestBodyBytes, allowMalformed: true),
      headers: request.headers,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: response.statusCode,
      body: utf8.decode(responseBodyBytes, allowMalformed: true),
      headers: response.headers,
      responseTime: responseTime,
      timeToFirstByte: timeToFirstByte,
    );

    _onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }

  /// 记录异常
  void _recordException({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required List<int> requestBodyBytes,
    required int startTime,
    required Object error,
  }) {
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: utf8.decode(requestBodyBytes, allowMalformed: true),
      headers: request.headers,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: 0,
      body: error.toString(),
      headers: {},
      responseTime: responseTime,
    );

    _onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }
}
