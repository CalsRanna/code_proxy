import 'dart:async';
import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

/// 响应处理器 - 协调者
class ProxyServerResponseHandler {
  final ResponseProcessor _processor;
  final HeaderCleaner _headerCleaner;
  final StatsRecorder _statsRecorder;

  ProxyServerResponseHandler({
    void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
    onRequestCompleted,
  }) : _processor = const ResponseProcessor(),
       _headerCleaner = const HeaderCleaner(),
       _statsRecorder = StatsRecorder(onRequestCompleted: onRequestCompleted);

  /// 处理HTTP响应
  Future<shelf.Response> handleResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> requestBodyBytes,
    int startTime, {
    List<int>? mappedRequestBodyBytes,
  }) async {
    final isStream = _processor.isStream(response.headers);
    final cleanHeaders = _headerCleaner.clean(response.headers);

    void recordStats(List<int>? responseBodyBytes) => _statsRecorder.record(
      endpoint: endpoint,
      request: request,
      requestBodyBytes: mappedRequestBodyBytes ?? requestBodyBytes,
      response: response,
      responseBodyBytes: responseBodyBytes,
      responseTime: DateTime.now().millisecondsSinceEpoch - startTime,
      timeToFirstByte: null,
    );

    void recordException(Object error) => _statsRecorder.recordException(
      endpoint: endpoint,
      request: request,
      requestBodyBytes: requestBodyBytes,
      startTime: startTime,
      error: error,
    );

    if (isStream) {
      return _processor.processStreamResponse(
        response,
        cleanHeaders,
        recordStats,
        recordException,
      );
    } else {
      return await _processor.processNormalResponse(
        response,
        cleanHeaders,
        recordStats,
      );
    }
  }
}

/// 响应处理器 - 专注流式/非流式转换
class ResponseProcessor {
  const ResponseProcessor();

  /// 检测是否是流式响应（SSE 或其他流式格式）
  bool isStream(Map<String, String> headers) {
    final contentType = headers['content-type'] ?? '';
    return contentType.contains('text/event-stream') ||
        contentType.contains('application/stream+json');
  }

  /// 处理非流式响应
  Future<shelf.Response> processNormalResponse(
    http.StreamedResponse response,
    Map<String, String> cleanHeaders,
    void Function(List<int>? responseBodyBytes) recordStats,
  ) async {
    final responseBodyBytes = await response.stream.toBytes();
    recordStats(responseBodyBytes);

    return shelf.Response(
      response.statusCode,
      headers: cleanHeaders,
      body: responseBodyBytes,
    );
  }

  /// 处理流式响应（SSE）
  shelf.Response processStreamResponse(
    http.StreamedResponse response,
    Map<String, String> cleanHeaders,
    void Function(List<int>? responseBodyBytes) recordStats,
    void Function(Object error) recordException,
  ) {
    final buffer = <int>[];

    final transformedStream = response.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (List<int> chunk, EventSink<List<int>> sink) {
          buffer.addAll(chunk);
          sink.add(chunk);
        },
        handleDone: (EventSink<List<int>> sink) {
          recordStats(buffer);
          sink.close();
        },
        handleError: (error, stackTrace, EventSink<List<int>> sink) {
          recordException(error);
          sink.addError(error, stackTrace);
        },
      ),
    );

    return shelf.Response(
      response.statusCode,
      headers: cleanHeaders,
      body: transformedStream,
    );
  }
}

/// 头部清理器 - 专注头部处理
class HeaderCleaner {
  static const Set<String> _headersToRemove = {
    'transfer-encoding',
    'content-encoding',
    'content-length',
  };

  const HeaderCleaner();

  /// 清理响应头，移除可能导致问题的头部
  Map<String, String> clean(Map<String, String> headers) {
    return Map.from(headers)
      ..removeWhere((key, _) => _headersToRemove.contains(key));
  }
}

/// 统计记录器 - 专注数据记录
class StatsRecorder {
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  _onRequestCompleted;

  StatsRecorder({
    required void Function(
      EndpointEntity,
      ProxyServerRequest,
      ProxyServerResponse,
    )?
    onRequestCompleted,
  }) : _onRequestCompleted = onRequestCompleted;

  /// 记录请求统计
  void record({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required List<int> requestBodyBytes,
    required http.StreamedResponse response,
    required List<int>? responseBodyBytes,
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
      body: responseBodyBytes != null
          ? utf8.decode(responseBodyBytes, allowMalformed: true)
          : '',
      headers: response.headers,
      responseTime: responseTime,
      timeToFirstByte: timeToFirstByte,
    );

    _onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }

  /// 记录异常
  void recordException({
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
