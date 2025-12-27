import 'dart:async';
import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_router.dart';
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
      final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

      // 尝试提取 token（服务器错误也可能包含 usage）
      Map<String, int>? usage;
      try {
        final bodyStr = utf8.decode(responseBodyBytes, allowMalformed: true);
        final json = jsonDecode(bodyStr);
        if (json is Map<String, dynamic> && json.containsKey('usage')) {
          final usageData = json['usage'];
          if (usageData is Map<String, dynamic>) {
            usage = {
              'input': usageData['input_tokens'] as int? ?? 0,
              'output': usageData['output_tokens'] as int? ?? 0,
            };
          }
        }
      } catch (e) {
        // 忽略解析错误
      }

      _recordRequestWithBody(
        endpoint: endpoint,
        request: request,
        requestBodyBytes: requestBodyBytes,
        response: response,
        responseTime: responseTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
        tokenUsage: usage,
      );
      return null;
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

    if (isStream) {
      // 流式响应：在流完成时才计算响应时间
      return _processor.processStreamResponse(
        response,
        cleanHeaders,
        startTime,
        (Map<String, int> tokenUsage, int responseTime) =>
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
        (int responseTime, Map<String, int>? usage) => _recordRequestWithBody(
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
    Map<String, int>? tokenUsage,
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
    );

    _onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }

  void recordException({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required List<int> requestBodyBytes,
    required int startTime,
    required Object error,
    List<int>? mappedRequestBodyBytes,
  }) {
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;
    final bodyBytesToUse = mappedRequestBodyBytes ?? requestBodyBytes;

    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: utf8.decode(bodyBytesToUse, allowMalformed: true),
      headers: request.headers,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: 0,
      headers: {},
      responseTime: responseTime,
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
    void Function(int responseTime, Map<String, int>? usage) recordStats,
  ) async {
    final responseBodyBytes = await response.stream.toBytes();
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    // 提取 token 使用量（非流式响应）
    Map<String, int>? usage;
    try {
      final bodyStr = utf8.decode(responseBodyBytes, allowMalformed: true);
      final json = jsonDecode(bodyStr);
      if (json is Map<String, dynamic> && json.containsKey('usage')) {
        final usageData = json['usage'];
        if (usageData is Map<String, dynamic>) {
          usage = {
            'input': usageData['input_tokens'] as int? ?? 0,
            'output': usageData['output_tokens'] as int? ?? 0,
          };
        }
      }
    } catch (e) {
      // 忽略 JSON 解析错误（非 JSON 响应或格式不匹配）
    }

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
    void Function(Map<String, int> tokenUsage, int responseTime) recordStats,
    void Function(Object error) recordException,
  ) {
    int inputTokens = 0;
    int outputTokens = 0;
    String pendingData = '';

    final transformedStream = response.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (List<int> chunk, EventSink<List<int>> sink) {
          try {
            sink.add(chunk);

            final chunkStr = utf8.decode(chunk, allowMalformed: true);
            final fullData = pendingData + chunkStr;
            final lines = fullData.split('\n');

            if (!fullData.endsWith('\n')) {
              pendingData = lines.removeLast();
            } else {
              pendingData = '';
            }

            for (final line in lines) {
              if (line.startsWith('data: ')) {
                final jsonStr = line.substring(6).trim();
                if (jsonStr.isNotEmpty && jsonStr != '[DONE]') {
                  try {
                    final json = jsonDecode(jsonStr);
                    if (json is Map<String, dynamic>) {
                      // Extract message_start usage (input tokens)
                      if (json['type'] == 'message_start' &&
                          json.containsKey('message')) {
                        final message = json['message'];
                        if (message is Map<String, dynamic> &&
                            message.containsKey('usage')) {
                          final usage = message['usage'];
                          if (usage is Map<String, dynamic>) {
                            inputTokens = usage['input_tokens'] as int? ?? 0;
                          }
                        }
                      }
                      // Extract message_delta usage (output tokens)
                      if (json['type'] == 'message_delta' &&
                          json.containsKey('usage')) {
                        final usage = json['usage'];
                        if (usage is Map<String, dynamic>) {
                          outputTokens += (usage['output_tokens'] as int? ?? 0);
                        }
                      }
                    }
                  } catch (_) {
                    // Ignore JSON parse errors
                  }
                }
              }
            }
          } catch (e) {
            // Catch-all for decoding/parsing errors
          }
        },
        handleDone: (EventSink<List<int>> sink) {
          final responseTime =
              DateTime.now().millisecondsSinceEpoch - startTime;
          recordStats({
            'input': inputTokens,
            'output': outputTokens,
          }, responseTime);
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

class HeaderCleaner {
  static const Set<String> _headersToRemove = {
    'transfer-encoding',
    'content-encoding',
    'content-length',
  };

  const HeaderCleaner();

  Map<String, String> clean(Map<String, String> headers) {
    return Map.from(headers)
      ..removeWhere((key, _) => _headersToRemove.contains(key));
  }
}
