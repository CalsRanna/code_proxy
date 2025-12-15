import 'dart:async';
import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_router.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

/// 响应处理器 - 协调者
class ProxyServerResponseHandler {
  final ResponseProcessor _processor;
  final HeaderCleaner _headerCleaner;
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  _onRequestCompleted;

  ProxyServerResponseHandler({
    void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
    onRequestCompleted,
  }) : _processor = const ResponseProcessor(),
       _headerCleaner = const HeaderCleaner(),
       _onRequestCompleted = onRequestCompleted;

  /// 处理HTTP响应并判断是否需要继续
  /// 返回值：
  /// - 非null的 shelf.Response: 这是最终响应，停止循环
  /// - null: 需要继续循环（重试或转移）
  Future<shelf.Response?> handleResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> requestBodyBytes,
    int startTime, {
    List<int>? mappedRequestBodyBytes,
  }) async {
    final statusCode = response.statusCode;
    final requestBodyToLog = mappedRequestBodyBytes ?? requestBodyBytes;
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    // 根据状态码判断下一步操作
    if (statusCode >= 200 && statusCode < 300) {
      // 成功响应 → 处理并返回给客户端
      return await _processAndReturnResponse(
        response,
        endpoint,
        request,
        requestBodyToLog,
        startTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
      );
    } else if (statusCode >= 400 && statusCode < 500) {
      // 客户端错误 → 处理并返回给客户端（但不重试）
      return await _processAndReturnResponse(
        response,
        endpoint,
        request,
        requestBodyToLog,
        startTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
      );
    } else if (statusCode >= 500) {
      // 服务器错误 → 记录日志后继续循环（重试或转移）
      final responseBodyBytes = await response.stream.toBytes();
      _recordRequestWithBody(
        endpoint: endpoint,
        request: request,
        requestBodyBytes: requestBodyBytes,
        response: response,
        responseBodyBytes: responseBodyBytes,
        responseTime: responseTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
      );
      return null;
    } else {
      // 1xx 或其他未知状态码，按成功处理
      return await _processAndReturnResponse(
        response,
        endpoint,
        request,
        requestBodyToLog,
        startTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
      );
    }
  }

  /// 根据状态码获取HandleResult（供外部调用）
  HandleResult getHandleResult(http.StreamedResponse response) {
    final statusCode = response.statusCode;

    if (statusCode >= 200 && statusCode < 300) {
      return HandleResult.success;
    } else if (statusCode >= 400 && statusCode < 500) {
      return HandleResult.clientError;
    } else if (statusCode >= 500) {
      return HandleResult.serverError;
    } else {
      return HandleResult.success;
    }
  }

  /// 处理响应并返回给客户端（仅在成功或客户端错误时调用）
  Future<shelf.Response> _processAndReturnResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> requestBodyBytes,
    int startTime, {
    List<int>? mappedRequestBodyBytes,
  }) async {
    final isStream = _processor.isStream(response.headers);
    final cleanHeaders = _headerCleaner.clean(response.headers);
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    if (isStream) {
      return _processor.processStreamResponse(
        response,
        cleanHeaders,
        (List<int>? responseBodyBytes) => _recordRequestWithBody(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          response: response,
          responseBodyBytes: responseBodyBytes,
          responseTime: responseTime,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
        ),
        (Object error) => recordException(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          startTime: startTime,
          error: error,
        ),
      );
    } else {
      return await _processor.processNormalResponse(
        response,
        cleanHeaders,
        (List<int>? responseBodyBytes) => _recordRequestWithBody(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          response: response,
          responseBodyBytes: responseBodyBytes,
          responseTime: responseTime,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
        ),
      );
    }
  }

  /// 记录请求统计 - 包含响应体的记录
  void _recordRequestWithBody({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required List<int> requestBodyBytes,
    required http.StreamedResponse response,
    required List<int>? responseBodyBytes,
    required int responseTime,
    List<int>? mappedRequestBodyBytes,
  }) {
    // 使用映射后的请求体（如果提供），否则使用原始请求体
    final bodyBytesToUse = mappedRequestBodyBytes ?? requestBodyBytes;
    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: utf8.decode(bodyBytesToUse, allowMalformed: true),
      headers: request.headers,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: response.statusCode,
      body: responseBodyBytes != null
          ? utf8.decode(responseBodyBytes, allowMalformed: true)
          : '',
      headers: response.headers,
      responseTime: responseTime,
      timeToFirstByte: null,
    );

    _onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }

  /// 记录异常 - 网络错误等情况
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
