import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    } else if (statusCode == 429) {
      // 429 速率限制/余额不足，需要特殊处理
      return HandleResult.rateLimited;
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
    Map<String, String>? forwardedHeaders,
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
        forwardedHeaders: forwardedHeaders,
      );
    } else if (statusCode >= 400 && statusCode < 500) {
      // 客户端错误 → 读取错误响应体，记录日志，返回响应（不重试）
      final responseBodyBytes = await response.stream.toBytes();
      final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

      // 解压并解码响应体以保存错误信息
      final contentEncoding = response.headers['content-encoding'];
      final decompressedBytes = ResponseDecompressor.decompress(
        responseBodyBytes,
        contentEncoding,
      );
      final bodyStr = utf8.decode(decompressedBytes, allowMalformed: true);

      // 转发响应头（移除 transfer-encoding 因为 http 包已自动解码 chunked，
      // 保留 content-encoding 让客户端自行解压）
      final forwardedResponseHeaders = Map<String, String>.from(
        response.headers,
      )
        ..remove('transfer-encoding')
        ..remove('content-length');

      // 记录请求日志（包含错误信息）
      _recordRequestWithBody(
        endpoint: endpoint,
        request: request,
        requestBodyBytes: requestBodyBytes,
        response: response,
        responseTime: responseTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
        forwardedHeaders: forwardedHeaders,
        forwardedResponseHeaders: forwardedResponseHeaders,
        errorBody: bodyStr,
        responseBody: bodyStr,
      );

      // 返回原始压缩数据给客户端
      return shelf.Response(
        response.statusCode,
        headers: forwardedResponseHeaders,
        body: responseBodyBytes,
      );
    } else if (statusCode >= 500) {
      // 服务器错误 → 记录日志，返回响应（调用方决定是否重试）
      final responseBodyBytes = await response.stream.toBytes();
      final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

      // 解压并解码以提取 token
      final contentEncoding = response.headers['content-encoding'];
      final decompressedBytes = ResponseDecompressor.decompress(
        responseBodyBytes,
        contentEncoding,
      );
      final bodyStr = utf8.decode(decompressedBytes, allowMalformed: true);
      final usage = _tokenExtractor.extractUsage(bodyStr);

      // 转发响应头
      final forwardedResponseHeaders = Map<String, String>.from(
        response.headers,
      )
        ..remove('transfer-encoding')
        ..remove('content-length');

      _recordRequestWithBody(
        endpoint: endpoint,
        request: request,
        requestBodyBytes: requestBodyBytes,
        response: response,
        responseTime: responseTime,
        mappedRequestBodyBytes: mappedRequestBodyBytes,
        forwardedHeaders: forwardedHeaders,
        forwardedResponseHeaders: forwardedResponseHeaders,
        tokenUsage: usage,
        errorBody: bodyStr,
        responseBody: bodyStr,
      );

      // 返回原始压缩数据给客户端
      return shelf.Response(
        response.statusCode,
        headers: forwardedResponseHeaders,
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
        forwardedHeaders: forwardedHeaders,
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
    Map<String, String>? forwardedHeaders,
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
      forwardedHeaders: forwardedHeaders,
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
    Map<String, String>? forwardedHeaders,
  }) async {
    final isStream = _processor.isStream(response.headers);
    final contentEncoding = response.headers['content-encoding'];
    // 转发响应头（移除 transfer-encoding 因为 http 包已自动解码 chunked，
    // 保留 content-encoding 让客户端自行解压）
    final forwardedResponseHeaders = Map<String, String>.from(response.headers)
      ..remove('transfer-encoding')
      ..remove('content-length');

    if (isStream) {
      // 流式响应：在流完成时才计算响应时间
      return _processor.processStreamResponse(
        response,
        forwardedResponseHeaders,
        startTime,
        _tokenExtractor,
        contentEncoding,
        (
          Map<String, int?>? tokenUsage,
          int responseTime,
          String responseBody,
        ) => _recordRequestWithBody(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          response: response,
          responseTime: responseTime,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
          forwardedHeaders: forwardedHeaders,
          forwardedResponseHeaders: forwardedResponseHeaders,
          tokenUsage: tokenUsage,
          responseBody: responseBody,
        ),
        (Object error) => recordException(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          startTime: startTime,
          error: error,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
          forwardedHeaders: forwardedHeaders,
        ),
      );
    } else {
      // 非流式响应：在读取完响应体后计算响应时间并提取 token
      return await _processor.processNormalResponse(
        response,
        forwardedResponseHeaders,
        startTime,
        _tokenExtractor,
        contentEncoding,
        (int responseTime, Map<String, int?>? usage, String responseBody) =>
            _recordRequestWithBody(
              endpoint: endpoint,
              request: request,
              requestBodyBytes: requestBodyBytes,
              response: response,
              responseTime: responseTime,
              mappedRequestBodyBytes: mappedRequestBodyBytes,
              forwardedHeaders: forwardedHeaders,
              forwardedResponseHeaders: forwardedResponseHeaders,
              tokenUsage: usage,
              responseBody: responseBody,
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
    Map<String, String>? forwardedHeaders,
    Map<String, String>? forwardedResponseHeaders,
    Map<String, int?>? tokenUsage,
    String? errorBody,
    String? responseBody,
  }) {
    final bodyBytesToUse = mappedRequestBodyBytes ?? requestBodyBytes;
    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: utf8.decode(bodyBytesToUse, allowMalformed: true),
      headers: request.headers,
      forwardedHeaders: forwardedHeaders,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      forwardedHeaders: forwardedResponseHeaders,
      responseTime: responseTime,
      timeToFirstByte: null,
      usage: tokenUsage,
      errorBody: errorBody,
      responseBody: responseBody,
    );

    _onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }
}

/// 响应体解压工具
class ResponseDecompressor {
  /// 根据 content-encoding 解压响应体字节
  /// 返回解压后的字节，如果不需要解压或不支持的格式则返回原始字节
  static List<int> decompress(List<int> bytes, String? contentEncoding) {
    if (contentEncoding == null || contentEncoding.isEmpty) return bytes;

    try {
      switch (contentEncoding.toLowerCase()) {
        case 'gzip':
          return gzip.decode(bytes);
        case 'deflate':
          return zlib.decode(bytes);
        case 'br':
          LoggerUtil.instance.w(
            'Brotli decompression not supported, raw bytes used for logging',
          );
          return bytes;
        case 'zstd':
          LoggerUtil.instance.w(
            'Zstd decompression not supported, raw bytes used for logging',
          );
          return bytes;
        default:
          return bytes;
      }
    } catch (e) {
      LoggerUtil.instance.w(
        'Failed to decompress response body ($contentEncoding): $e',
      );
      return bytes;
    }
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
    Map<String, String> responseHeaders,
    int startTime,
    TokenExtractor extractor,
    String? contentEncoding,
    void Function(
      int responseTime,
      Map<String, int?>? usage,
      String responseBody,
    )
    recordStats,
  ) async {
    final responseBodyBytes = await response.stream.toBytes();
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    // 解压后提取 token 使用量（非流式响应）
    final decompressedBytes = ResponseDecompressor.decompress(
      responseBodyBytes,
      contentEncoding,
    );
    final bodyStr = utf8.decode(decompressedBytes, allowMalformed: true);
    final usage = extractor.extractUsage(bodyStr);

    recordStats(responseTime, usage, bodyStr);

    // 返回原始压缩数据给客户端
    return shelf.Response(
      response.statusCode,
      headers: responseHeaders,
      body: responseBodyBytes,
    );
  }

  shelf.Response processStreamResponse(
    http.StreamedResponse response,
    Map<String, String> responseHeaders,
    int startTime,
    TokenExtractor extractor,
    String? contentEncoding,
    void Function(
      Map<String, int?>? tokenUsage,
      int responseTime,
      String responseBody,
    )
    recordStats,
    void Function(Object error) recordException,
  ) {
    int? inputTokens;
    int? outputTokens;
    final responseChunks = <String>[];
    final isCompressed = contentEncoding != null && contentEncoding.isNotEmpty;
    final rawChunks = isCompressed ? <List<int>>[] : null;

    final transformedStream = response.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          // 原始数据原封不动转发给客户端
          sink.add(chunk);

          if (isCompressed) {
            // 压缩数据先收集，流结束后统一解压
            rawChunks!.add(chunk);
          } else {
            final text = utf8.decode(chunk, allowMalformed: true);
            responseChunks.add(text);
            inputTokens = extractor.extractInputTokens(text) ?? inputTokens;
            outputTokens = extractor.extractOutputTokens(text) ?? outputTokens;
          }
        },
        handleDone: (sink) {
          final responseTime =
              DateTime.now().millisecondsSinceEpoch - startTime;

          if (isCompressed && rawChunks != null) {
            // 将所有块合并后统一解压
            final allBytes = rawChunks.expand((c) => c).toList();
            final decompressed = ResponseDecompressor.decompress(
              allBytes,
              contentEncoding,
            );
            final text = utf8.decode(decompressed, allowMalformed: true);
            responseChunks.add(text);
            inputTokens = extractor.extractInputTokens(text) ?? inputTokens;
            outputTokens = extractor.extractOutputTokens(text) ?? outputTokens;
          }

          final responseBody = responseChunks.join();
          recordStats(
            {'input': inputTokens, 'output': outputTokens},
            responseTime,
            responseBody,
          );
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
      headers: responseHeaders,
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
