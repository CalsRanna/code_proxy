import 'dart:async';
import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_router.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

/// 响应处理器 - 协调者
class ProxyServerResponseHandler {
  final ResponseProcessor _processor;
  final TokenExtractor _tokenExtractor;
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  _onRequestCompleted;

  ProxyServerResponseHandler({
    void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
    onRequestCompleted,
  }) : _processor = const ResponseProcessor(),
       _tokenExtractor = const TokenExtractor(),
       _onRequestCompleted = onRequestCompleted;

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

  /// 处理HTTP响应并判断是否需要继续
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

    // 根据状态码判断下一步操作
    if (statusCode >= 200 && statusCode < 300) {
      return await _processAndReturnResponse(
        response,
        endpoint,
        request,
        requestBodyToLog,
        startTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
      );
    } else if (statusCode >= 400 && statusCode < 500) {
      // 客户端错误 → 读取错误响应体，记录日志，返回响应（不重试）
      final responseBodyBytes = await response.stream.toBytes();
      final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

      // 解码响应体以保存错误信息
      final bodyStr = utf8.decode(responseBodyBytes, allowMalformed: true);

      // 记录请求日志（包含错误信息）
      _recordRequestWithBody(
        endpoint: endpoint,
        request: request,
        requestBodyBytes: requestBodyBytes,
        response: response,
        responseTime: responseTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
        errorBody: bodyStr,
      );

      // 清理响应头
      final cleanHeaders = Map<String, String>.from(response.headers)
        ..remove('transfer-encoding')
        ..remove('content-encoding')
        ..remove('content-length');

      // 返回错误响应给客户端
      return shelf.Response(
        response.statusCode,
        headers: cleanHeaders,
        body: responseBodyBytes,
      );
    } else if (statusCode >= 500) {
      // 服务器错误 → 记录日志，返回响应（调用方决定是否重试）
      final responseBodyBytes = await response.stream.toBytes();
      final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

      // 尝试提取 token（服务器错误也可能包含 usage）
      final bodyStr = utf8.decode(responseBodyBytes, allowMalformed: true);
      final usage = _tokenExtractor.extractUsage(bodyStr);

      _recordRequestWithBody(
        endpoint: endpoint,
        request: request,
        requestBodyBytes: requestBodyBytes,
        response: response,
        responseTime: responseTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
        tokenUsage: usage,
        errorBody: bodyStr,
      );

      final cleanHeaders = Map<String, String>.from(response.headers)
        ..remove('transfer-encoding')
        ..remove('content-encoding')
        ..remove('content-length');

      return shelf.Response(
        response.statusCode,
        headers: cleanHeaders,
        body: responseBodyBytes,
      );
    } else {
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

  void recordException({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required List<int> requestBodyBytes,
    required int? startTime,
    required Object error,
    List<int>? mappedRequestBodyBytes,
  }) {
    // 如果 startTime 为 null，说明在请求准备阶段就失败了，没有真正发起 API 请求
    final responseTime = startTime != null
        ? DateTime.now().millisecondsSinceEpoch - startTime
        : 0;
    final bodyBytesToUse = mappedRequestBodyBytes ?? requestBodyBytes;

    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: utf8.decode(bodyBytesToUse, allowMalformed: true),
      headers: request.headers,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: 502, // Bad Gateway - 代理服务器无法从上游端点获得有效响应
      headers: {},
      responseTime: responseTime,
      errorBody: error.toString(),
    );

    _onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }

  Future<shelf.Response> _processAndReturnResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> requestBodyBytes,
    int startTime, {
    List<int>? mappedRequestBodyBytes,
  }) async {
    final isStream = _processor.isStream(response.headers);
    final cleanHeaders = Map<String, String>.from(response.headers)
      ..remove('transfer-encoding')
      ..remove('content-encoding')
      ..remove('content-length');

    if (isStream) {
      // 流式响应：在流完成时才计算响应时间
      return _processor.processStreamResponse(
        response,
        cleanHeaders,
        startTime,
        _tokenExtractor,
        (Map<String, int?>? tokenUsage, int responseTime) =>
            _recordRequestWithBody(
              endpoint: endpoint,
              request: request,
              requestBodyBytes: requestBodyBytes,
              response: response,
              responseTime: responseTime,
              mappedRequestBodyBytes: mappedRequestBodyBytes,
              tokenUsage: tokenUsage,
            ),
        (Object error) => recordException(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          startTime: startTime,
          error: error,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
        ),
      );
    } else {
      // 非流式响应：在读取完响应体后计算响应时间并提取 token
      return await _processor.processNormalResponse(
        response,
        cleanHeaders,
        startTime,
        _tokenExtractor,
        (int responseTime, Map<String, int?>? usage) => _recordRequestWithBody(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          response: response,
          responseTime: responseTime,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
          tokenUsage: usage,
        ),
      );
    }
  }

  void _recordRequestWithBody({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required List<int> requestBodyBytes,
    required http.StreamedResponse response,
    required int responseTime,
    List<int>? mappedRequestBodyBytes,
    Map<String, int?>? tokenUsage,
    String? errorBody,
  }) {
    final bodyBytesToUse = mappedRequestBodyBytes ?? requestBodyBytes;
    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: utf8.decode(bodyBytesToUse, allowMalformed: true),
      headers: request.headers,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      responseTime: responseTime,
      timeToFirstByte: null,
      usage: tokenUsage,
      errorBody: errorBody,
    );

    _onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }
}

class ResponseProcessor {
  const ResponseProcessor();

  bool isStream(Map<String, String> headers) {
    final contentType = headers['content-type'] ?? '';
    return contentType.contains('text/event-stream') ||
        contentType.contains('application/stream+json');
  }

  Future<shelf.Response> processNormalResponse(
    http.StreamedResponse response,
    Map<String, String> cleanHeaders,
    int startTime,
    TokenExtractor extractor,
    void Function(int responseTime, Map<String, int?>? usage) recordStats,
  ) async {
    final responseBodyBytes = await response.stream.toBytes();
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    // 提取 token 使用量（非流式响应）
    final bodyStr = utf8.decode(responseBodyBytes, allowMalformed: true);
    final usage = extractor.extractUsage(bodyStr);

    recordStats(responseTime, usage);

    return shelf.Response(
      response.statusCode,
      headers: cleanHeaders,
      body: responseBodyBytes,
    );
  }

  shelf.Response processStreamResponse(
    http.StreamedResponse response,
    Map<String, String> cleanHeaders,
    int startTime,
    TokenExtractor extractor,
    void Function(Map<String, int?>? tokenUsage, int responseTime) recordStats,
    void Function(Object error) recordException,
  ) {
    int? inputTokens;
    int? outputTokens;

    final transformedStream = response.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          sink.add(chunk);
          final text = utf8.decode(chunk, allowMalformed: true);
          inputTokens = extractor.extractInputTokens(text) ?? inputTokens;
          outputTokens = extractor.extractOutputTokens(text) ?? outputTokens;
        },
        handleDone: (sink) {
          final responseTime =
              DateTime.now().millisecondsSinceEpoch - startTime;
          recordStats({
            'input': inputTokens,
            'output': outputTokens,
          }, responseTime);
          sink.close();
        },
        handleError: (error, stackTrace, sink) {
          LoggerUtil.instance.w('Upstream stream error: $error');
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

/// Token 提取器 - 使用正则从 API 响应中提取 token 使用量
class TokenExtractor {
  static final _inputPattern = RegExp(r'"input_tokens"\s*:\s*(\d+)');
  static final _outputPattern = RegExp(r'"output_tokens"\s*:\s*(\d+)');

  const TokenExtractor();

  /// 从文本中提取 input_tokens
  int? extractInputTokens(String text) {
    final match = _inputPattern.firstMatch(text);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  /// 从文本中提取 output_tokens（取最后一个匹配，因为是累积值）
  int? extractOutputTokens(String text) {
    final matches = _outputPattern.allMatches(text);
    if (matches.isEmpty) return null;
    return int.tryParse(matches.last.group(1)!);
  }

  /// 从文本中提取完整的 usage
  Map<String, int?>? extractUsage(String text) {
    final input = extractInputTokens(text);
    final output = extractOutputTokens(text);
    if (input == null && output == null) return null;
    return {'input': input, 'output': output};
  }
}
