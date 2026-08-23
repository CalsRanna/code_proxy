import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_compat_response_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_compat_stream_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_responses_response_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_responses_stream_converter.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

/// 上游流在未发送协议完成信号（Anthropic `message_stop`、OpenAI
/// finish_reason/[DONE] 或 Responses completed/incomplete/failed）前即到达
/// EOF，视为静默截断。
///
/// 这种情况常见于网关在模型长推理中途断开连接：客户端若收到转换器
/// 补发的"正常收尾"会误以为模型零输出完成，而非流被截断。
class UpstreamStreamAbortedException implements Exception {
  const UpstreamStreamAbortedException();

  @override
  String toString() =>
      'Upstream stream ended without completion signal '
      '(connection closed mid-stream)';
}

/// 响应处理器 - 协调者
class ProxyServerResponseHandler {
  final ResponseProcessor _processor;
  final TokenExtractor _tokenExtractor;

  /// Chat Completions 格式的响应体/错误体转换器
  final OpenAiCompatResponseConverter _openAiResponseConverter =
      const OpenAiCompatResponseConverter();

  /// Responses API 格式的响应体转换器
  final OpenAiResponsesResponseConverter _openAiResponsesResponseConverter =
      const OpenAiResponsesResponseConverter();

  /// 端点是否需要代理完成协议转换（OpenAI 两大 API 格式）
  static bool _needsConversion(EndpointEntity endpoint) =>
      endpoint.apiFormat != EndpointApiFormat.anthropic;

  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  _onRequestCompleted;

  /// 流式响应中途中断时回调（用于对端点补记失败）。
  final void Function(EndpointEntity)? _onStreamError;

  ProxyServerResponseHandler({
    void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
    onRequestCompleted,
    void Function(EndpointEntity)? onStreamError,
  }) : _processor = const ResponseProcessor(),
       _tokenExtractor = const TokenExtractor(),
       _onRequestCompleted = onRequestCompleted,
       _onStreamError = onStreamError;

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
        originalRequestBodyBytes: requestBodyBytes,
        forwardedHeaders: forwardedHeaders,
      );
    } else if (statusCode >= 400 && statusCode < 500) {
      // 客户端错误 → 读取错误响应体，记录日志，返回响应
      final responseBodyBytes = await response.stream.toBytes();
      final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

      // 解压并解码响应体以保存错误信息
      final contentEncoding = response.headers['content-encoding'];
      final bodyStr = ResponseDecompressor.decodeForLogging(
        responseBodyBytes,
        contentEncoding,
      );

      // OpenAI 格式端点：错误体转换为 Anthropic 格式，保证客户端可解析展示
      if (_needsConversion(endpoint)) {
        return _openAiErrorResponse(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          originalRequestBodyBytes: requestBodyBytes,
          response: response,
          startTime: startTime,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
          forwardedHeaders: forwardedHeaders,
          upstreamErrorBody: bodyStr,
        );
      }

      // 转发响应头（移除 transfer-encoding 因为 http 包已自动解码 chunked，
      // 保留 content-encoding 让客户端自行解压）
      final forwardedResponseHeaders =
          Map<String, String>.from(response.headers)
            ..remove('transfer-encoding')
            ..remove('content-length');

      // 记录请求日志（包含错误信息）
      _recordRequestWithBody(
        endpoint: endpoint,
        request: request,
        requestBodyBytes: requestBodyBytes,
        originalRequestBodyBytes: requestBodyBytes,
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
      final bodyStr = ResponseDecompressor.decodeForLogging(
        responseBodyBytes,
        contentEncoding,
      );
      final usage = _tokenExtractor.extractUsage(bodyStr);

      // OpenAI 格式端点：错误体转换为 Anthropic 格式，保证客户端可解析展示
      if (_needsConversion(endpoint)) {
        return _openAiErrorResponse(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          originalRequestBodyBytes: requestBodyBytes,
          response: response,
          startTime: startTime,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
          forwardedHeaders: forwardedHeaders,
          upstreamErrorBody: bodyStr,
        );
      }

      // 转发响应头
      final forwardedResponseHeaders =
          Map<String, String>.from(response.headers)
            ..remove('transfer-encoding')
            ..remove('content-length');

      _recordRequestWithBody(
        endpoint: endpoint,
        request: request,
        requestBodyBytes: requestBodyBytes,
        originalRequestBodyBytes: requestBodyBytes,
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
        originalRequestBodyBytes: requestBodyBytes,
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
    int statusCode = HttpStatus.badGateway,
    List<int>? mappedRequestBodyBytes,
    Map<String, String>? forwardedHeaders,
    String? rawResponseBody,
    String? responseBody,
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
      originalModel: _extractOriginalModel(requestBodyBytes),
      originalBody: utf8.decode(requestBodyBytes, allowMalformed: true),
      headers: request.headers,
      forwardedHeaders: forwardedHeaders,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: statusCode,
      headers: {},
      responseTime: responseTime,
      errorBody: error.toString(),
      rawResponseBody: rawResponseBody,
      responseBody: responseBody,
    );

    _onRequestCompleted?.call(endpoint, proxyRequest, proxyResponse);
  }

  shelf.Response buildExceptionResponse(Object error) {
    return shelf.Response(
      HttpStatus.internalServerError,
      headers: {HttpHeaders.contentTypeHeader: 'text/plain; charset=utf-8'},
      body: error.toString(),
    );
  }

  Future<shelf.Response> _processAndReturnResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> requestBodyBytes,
    int startTime, {
    List<int>? mappedRequestBodyBytes,
    required List<int> originalRequestBodyBytes,
    Map<String, String>? forwardedHeaders,
  }) async {
    final isStream = _processor.isStream(response.headers);
    final contentEncoding = response.headers['content-encoding'];
    // 转发响应头（移除 transfer-encoding 因为 http 包已自动解码 chunked，
    // 保留 content-encoding 让客户端自行解压）
    final forwardedResponseHeaders = Map<String, String>.from(response.headers)
      ..remove('transfer-encoding')
      ..remove('content-length');

    // OpenAI 格式端点：响应体需要整体转换后重发给客户端，走独立的处理路径
    if (_needsConversion(endpoint)) {
      return isStream
          ? _buildOpenAiStreamResponse(
              response,
              endpoint,
              request,
              requestBodyBytes: requestBodyBytes,
              originalRequestBodyBytes: originalRequestBodyBytes,
              startTime: startTime,
              mappedRequestBodyBytes: mappedRequestBodyBytes,
              forwardedHeaders: forwardedHeaders,
            )
          : await _processOpenAiNormalResponse(
              response,
              endpoint,
              request,
              requestBodyBytes: requestBodyBytes,
              originalRequestBodyBytes: originalRequestBodyBytes,
              startTime: startTime,
              contentEncoding: contentEncoding,
              mappedRequestBodyBytes: mappedRequestBodyBytes,
              forwardedHeaders: forwardedHeaders,
            );
    }

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
          originalRequestBodyBytes: originalRequestBodyBytes,
          response: response,
          responseTime: responseTime,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
          forwardedHeaders: forwardedHeaders,
          forwardedResponseHeaders: forwardedResponseHeaders,
          tokenUsage: tokenUsage,
          responseBody: responseBody,
        ),
        (Object error, String responseBody) => recordException(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          startTime: startTime,
          error: error,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
          forwardedHeaders: forwardedHeaders,
          responseBody: responseBody.isEmpty ? null : responseBody,
        ),
        onStreamError: () => _onStreamError?.call(endpoint),
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
              originalRequestBodyBytes: originalRequestBodyBytes,
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

  /// OpenAI 兼容端点的错误响应：转换错误体并记录日志后返回。
  ///
  /// 返回给客户端的是 Anthropic 错误格式；审计中 responseBody/errorBody
  /// 均记录客户端实际收到的转换后文本。
  shelf.Response _openAiErrorResponse({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required List<int> requestBodyBytes,
    required List<int> originalRequestBodyBytes,
    required http.StreamedResponse response,
    required int startTime,
    List<int>? mappedRequestBodyBytes,
    Map<String, String>? forwardedHeaders,
    required String upstreamErrorBody,
  }) {
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;
    // 两种 OpenAI API 的错误体结构同构（{error:{message,type,code}}），
    // 复用同一转换实现
    final convertedJson = _openAiResponseConverter.convertErrorBody(
      upstreamErrorBody,
    );
    final clientFacingBody = jsonEncode(convertedJson);

    _recordRequestWithBody(
      endpoint: endpoint,
      request: request,
      requestBodyBytes: requestBodyBytes,
      originalRequestBodyBytes: originalRequestBodyBytes,
      response: response,
      responseTime: responseTime,
      mappedRequestBodyBytes: mappedRequestBodyBytes,
      forwardedHeaders: forwardedHeaders,
      forwardedResponseHeaders: _openAiJsonHeaders(),
      errorBody: clientFacingBody,
      responseBody: clientFacingBody,
      rawResponseBody: upstreamErrorBody,
    );

    return shelf.Response(
      response.statusCode,
      headers: _openAiJsonHeaders(),
      body: clientFacingBody,
    );
  }

  /// OpenAI 兼容端点：非流式响应转换（chat.completion → Anthropic message）。
  Future<shelf.Response> _processOpenAiNormalResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request, {
    required List<int> requestBodyBytes,
    required List<int> originalRequestBodyBytes,
    required int startTime,
    String? contentEncoding,
    List<int>? mappedRequestBodyBytes,
    Map<String, String>? forwardedHeaders,
  }) async {
    final responseBodyBytes = await response.stream.toBytes();
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    // 上游已要求 identity，但防御个别网关仍返回压缩体
    final decompressed = ResponseDecompressor.decompress(
      responseBodyBytes,
      contentEncoding,
    );
    final decoded = utf8.decode(decompressed, allowMalformed: true);

    String clientFacingBody;
    Map<String, int?>? usage;

    try {
      final decodedJson = jsonDecode(decoded);
      if (decodedJson is Map<String, dynamic>) {
        final converted =
            endpoint.apiFormat == EndpointApiFormat.openaiResponses
            ? _openAiResponsesResponseConverter.convertResponse(
                decodedJson,
                originalModel: _extractOriginalModel(originalRequestBodyBytes),
              )
            : _openAiResponseConverter.convertResponse(
                decodedJson,
                originalModel: _extractOriginalModel(originalRequestBodyBytes),
              );
        clientFacingBody = jsonEncode(converted);
        // 转换结果为标准 Anthropic 格式，直接复用现有提取器统计 usage
        usage = _tokenExtractor.extractUsage(clientFacingBody);
      } else {
        clientFacingBody = decoded;
      }
    } catch (e) {
      LoggerUtil.instance.w(
        'OpenAI non-stream response is not valid JSON, passing through: $e',
      );
      clientFacingBody = decoded;
    }

    _recordRequestWithBody(
      endpoint: endpoint,
      request: request,
      requestBodyBytes: requestBodyBytes,
      originalRequestBodyBytes: originalRequestBodyBytes,
      response: response,
      responseTime: responseTime,
      mappedRequestBodyBytes: mappedRequestBodyBytes,
      forwardedHeaders: forwardedHeaders,
      forwardedResponseHeaders: _openAiJsonHeaders(),
      tokenUsage: usage,
      responseBody: clientFacingBody,
      rawResponseBody: decoded,
    );

    return shelf.Response(
      response.statusCode,
      headers: _openAiJsonHeaders(),
      body: clientFacingBody,
    );
  }

  /// OpenAI 兼容端点：流式响应转换（OpenAI SSE chunk 流 → Anthropic 事件流）。
  ///
  /// message_start/ping 在上游首字节到达前先行产出，保证客户端尽快收到响应。
  shelf.Response _buildOpenAiStreamResponse(
    http.StreamedResponse response,
    EndpointEntity endpoint,
    shelf.Request request, {
    required List<int> requestBodyBytes,
    required List<int> originalRequestBodyBytes,
    required int startTime,
    List<int>? mappedRequestBodyBytes,
    Map<String, String>? forwardedHeaders,
  }) {
    final originalModel = _extractOriginalModel(originalRequestBodyBytes);
    final OpenAiSseConverter converter =
        endpoint.apiFormat == EndpointApiFormat.openaiResponses
        ? OpenAiResponsesSseStreamConverter(originalModel: originalModel)
        : OpenAiSseStreamConverter(originalModel: originalModel);
    // 转换后的完整事件文本（供审计记录）
    final outputChunks = <String>[];
    // 上游原始字节（协议转换前，供审计对照）。accept-encoding 已强制
    // identity，无需解压；流结束后整体解码，天然规避跨 chunk 的 UTF-8 截断。
    final rawChunks = <List<int>>[];

    Stream<List<int>> convert(Stream<List<int>> source) async* {
      final head = converter.initialEvents();
      if (head.isNotEmpty) {
        outputChunks.add(utf8.decode(head));
        yield head;
      }
      try {
        await for (final chunk in source) {
          rawChunks.add(chunk);
          final out = converter.handleData(chunk);
          if (out.isNotEmpty) {
            outputChunks.add(utf8.decode(out));
            yield out;
          }
        }

        // 上游静默截断：流已 EOF 但从未收到完成信号（finish_reason/[DONE]
        // 或 response.completed 等）。此刻不能补发正常收尾事件伪装成
        // "零输出成功响应"——按流中断处理，走下方异常路径。
        if (!converter.isComplete) {
          throw const UpstreamStreamAbortedException();
        }

        final tail = converter.handleDone();
        if (tail.isNotEmpty) {
          outputChunks.add(utf8.decode(tail));
          yield tail;
        }

        final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;
        final rawStreamText = utf8.decode(
          rawChunks.expand((c) => c).toList(),
          allowMalformed: true,
        );
        _recordRequestWithBody(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          originalRequestBodyBytes: originalRequestBodyBytes,
          response: response,
          responseTime: responseTime,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
          forwardedHeaders: forwardedHeaders,
          forwardedResponseHeaders: _openAiStreamHeaders(),
          tokenUsage: converter.finalUsage,
          responseBody: outputChunks.join(),
          rawResponseBody: rawStreamText,
        );
      } catch (error) {
        LoggerUtil.instance.w('Upstream OpenAI stream error: $error');
        // 流中途失败：对端点补记失败，避免损坏的流被记为成功
        _onStreamError?.call(endpoint);

        // 错误事件输出也留存：截断场景仍写入审计（半截原始流 + error 事件），
        // 保证本地可还原中断点
        final errorEvents = converter.handleError(error);
        if (errorEvents.isNotEmpty) {
          outputChunks.add(utf8.decode(errorEvents));
        }
        recordException(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: requestBodyBytes,
          startTime: startTime,
          error: error,
          mappedRequestBodyBytes: mappedRequestBodyBytes,
          forwardedHeaders: forwardedHeaders,
          // 已收到的半截原始流一并留存，便于排查中断点
          rawResponseBody: utf8.decode(
            rawChunks.expand((c) => c).toList(),
            allowMalformed: true,
          ),
          // 客户端实际收到的完整输出（头部事件 + 已转换内容块 + error 事件）
          // 也落审计，便于还原中断点
          responseBody: outputChunks.isEmpty ? null : outputChunks.join(),
        );

        // 以标准 Anthropic error 事件优雅终止
        yield errorEvents;
      }
    }

    return shelf.Response(
      response.statusCode,
      headers: _openAiStreamHeaders(),
      body: convert(response.stream),
    );
  }

  /// OpenAI 兼容端点非流式响应的转发头。
  ///
  /// 响应体已整体重写（解压 + 格式转换），content-encoding/content-length
  /// 均不再适用。
  Map<String, String> _openAiJsonHeaders() => const {
    'content-type': 'application/json',
  };

  /// OpenAI 兼容端点流式响应的转发头
  Map<String, String> _openAiStreamHeaders() => const {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache',
  };

  /// 从原始请求体字节中提取客户端发送的原始模型名称
  String? _extractOriginalModel(List<int> requestBodyBytes) {
    try {
      final bodyString = utf8.decode(requestBodyBytes, allowMalformed: true);
      if (bodyString.isEmpty) return null;
      final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;
      return bodyJson['model'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _recordRequestWithBody({
    required EndpointEntity endpoint,
    required shelf.Request request,
    required List<int> requestBodyBytes,
    required List<int> originalRequestBodyBytes,
    required http.StreamedResponse response,
    required int responseTime,
    List<int>? mappedRequestBodyBytes,
    Map<String, String>? forwardedHeaders,
    Map<String, String>? forwardedResponseHeaders,
    Map<String, int?>? tokenUsage,
    String? errorBody,
    String? responseBody,
    String? rawResponseBody,
  }) {
    final bodyBytesToUse = mappedRequestBodyBytes ?? requestBodyBytes;
    final proxyRequest = ProxyServerRequest(
      path: request.url.path,
      method: request.method,
      body: utf8.decode(bodyBytesToUse, allowMalformed: true),
      originalModel: _extractOriginalModel(originalRequestBodyBytes),
      originalBody: utf8.decode(originalRequestBodyBytes, allowMalformed: true),
      headers: request.headers,
      forwardedHeaders: forwardedHeaders,
    );

    final proxyResponse = ProxyServerResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      forwardedHeaders: forwardedResponseHeaders,
      responseTime: responseTime,
      usage: tokenUsage,
      errorBody: errorBody,
      responseBody: responseBody,
      rawResponseBody: rawResponseBody,
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

  /// 将响应体字节转换为适合日志记录的文本。
  /// 如果无法得到可读文本，则返回包含编码和数据摘要的占位描述。
  static String decodeForLogging(List<int> bytes, String? contentEncoding) {
    if (bytes.isEmpty) return '';

    final decompressedBytes = decompress(bytes, contentEncoding);
    final bodyStr = utf8.decode(decompressedBytes, allowMalformed: true);
    if (_isReadableText(bodyStr)) {
      return bodyStr;
    }

    final base64Preview = base64Encode(bytes);
    final preview = base64Preview.length > 120
        ? '${base64Preview.substring(0, 120)}...'
        : base64Preview;
    final encodingLabel = contentEncoding == null || contentEncoding.isEmpty
        ? 'identity'
        : contentEncoding;

    return '[non-text response body, ${bytes.length} bytes, '
        'content-encoding: $encodingLabel, base64: $preview]';
  }

  static bool _isReadableText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (!trimmed.contains('\uFFFD')) return true;

    final replacementCount = '\uFFFD'.allMatches(trimmed).length;
    return replacementCount * 2 < trimmed.length;
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
    void Function(Object error, String responseBody) recordException, {
    void Function()? onStreamError,
  }) {
    int? inputTokens;
    int? outputTokens;
    int? cacheCreationTokens;
    int? cacheReadTokens;
    final responseChunks = <String>[];
    final normalizedEncoding = contentEncoding?.trim().toLowerCase();
    final isCompressed =
        normalizedEncoding != null &&
        normalizedEncoding.isNotEmpty &&
        normalizedEncoding != 'identity';
    final rawChunks = isCompressed ? <List<int>>[] : null;

    // 非压缩流：使用带内部状态的 chunked decoder。
    // 逐 chunk 独立 decode 会把跨 chunk 边界的多字节 UTF-8 字符截断成
    // U+FFFD 替换符（中文响应体审计日志偶发乱码），chunked 模式在
    // decoder 内部维护 carry 字节，只有真正损坏的序列才产生替换符。
    final utf8Buffer = StringBuffer();
    final utf8Sink = isCompressed
        ? null
        : const Utf8Decoder(allowMalformed: true).startChunkedConversion(
            // StringBuffer 不是 Sink<String>，需经 StringConversionSink 桥接
            StringConversionSink.fromStringSink(utf8Buffer),
          );
    var failed = false;
    final canEmitSseError =
        !isCompressed &&
        (response.headers['content-type'] ?? '').contains('text/event-stream');

    List<int> buildSseError(Object error) {
      if (!canEmitSseError) return const [];
      return utf8.encode(
        'event: error\n'
        'data: ${jsonEncode({
          'type': 'error',
          'error': {'type': 'api_error', 'message': error.toString()},
        })}\n\n',
      );
    }

    final transformedStream = response.stream.transform(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          // 原始数据原封不动转发给客户端
          sink.add(chunk);

          if (isCompressed) {
            // 压缩数据先收集，流结束后统一解压
            rawChunks!.add(chunk);
          } else {
            utf8Sink!.add(chunk);
            final text = utf8Buffer.toString();
            utf8Buffer.clear();
            if (text.isEmpty) return;
            responseChunks.add(text);
            inputTokens = extractor.extractInputTokens(text) ?? inputTokens;
            outputTokens = extractor.extractOutputTokens(text) ?? outputTokens;
            cacheCreationTokens =
                extractor.extractCacheCreationTokens(text) ??
                cacheCreationTokens;
            cacheReadTokens =
                extractor.extractCacheReadTokens(text) ?? cacheReadTokens;
          }
        },
        handleDone: (sink) {
          if (failed) {
            sink.close();
            return;
          }

          final responseTime =
              DateTime.now().millisecondsSinceEpoch - startTime;

          if (isCompressed && rawChunks != null) {
            final allBytes = rawChunks.expand((c) => c).toList();
            final decompressed = ResponseDecompressor.decompress(
              allBytes,
              contentEncoding,
            );
            final text = utf8.decode(decompressed, allowMalformed: true);
            responseChunks.add(text);
          } else {
            // 刷新 decoder 尾部缓冲（跨 chunk 的不完整序列在此收尾）
            utf8Sink!.close();
            final tail = utf8Buffer.toString();
            if (tail.isNotEmpty) responseChunks.add(tail);
          }

          final responseBody = responseChunks.join();

          if (!_hasAnthropicCompletionSignal(responseBody)) {
            final error = const UpstreamStreamAbortedException();
            failed = true;
            LoggerUtil.instance.w('Upstream Anthropic stream error: $error');
            final errorEvent = buildSseError(error);
            final clientBody = errorEvent.isEmpty
                ? responseBody
                : '$responseBody${utf8.decode(errorEvent)}';
            recordException(error, clientBody);
            onStreamError?.call();
            if (errorEvent.isNotEmpty) sink.add(errorEvent);
            sink.close();
            return;
          }

          final usage = extractor.extractUsage(responseBody);
          if (usage != null) {
            inputTokens = usage['input'] ?? inputTokens;
            outputTokens = usage['output'] ?? outputTokens;
            cacheCreationTokens =
                usage['cache_creation'] ?? cacheCreationTokens;
            cacheReadTokens = usage['cache_read'] ?? cacheReadTokens;
          }

          recordStats(
            {
              'input': inputTokens,
              'output': outputTokens,
              'cache_creation': cacheCreationTokens,
              'cache_read': cacheReadTokens,
            },
            responseTime,
            responseBody,
          );
          sink.close();
        },
        handleError: (error, stackTrace, sink) {
          LoggerUtil.instance.w('Upstream stream error: $error');
          if (!failed) {
            failed = true;
            final responseBody = responseChunks.join();
            final errorEvent = buildSseError(error);
            final clientBody = errorEvent.isEmpty
                ? responseBody
                : '$responseBody${utf8.decode(errorEvent)}';
            recordException(error, clientBody);
            // 流中途失败：通知断路器对该端点补记失败，
            // 避免“成功开始但中途损坏”的流被记为成功。
            onStreamError?.call();
            if (errorEvent.isNotEmpty) sink.add(errorEvent);
          }
          sink.close();
        },
      ),
    );

    return shelf.Response(
      response.statusCode,
      headers: responseHeaders,
      body: transformedStream,
    );
  }

  static bool _hasAnthropicCompletionSignal(String responseBody) {
    for (final rawLine in const LineSplitter().convert(responseBody)) {
      final line = rawLine.trim();
      if (line.startsWith('event:') &&
          line.substring('event:'.length).trim() == 'message_stop') {
        return true;
      }

      final payload = line.startsWith('data:')
          ? line.substring('data:'.length).trim()
          : line;
      if (!payload.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map && decoded['type'] == 'message_stop') return true;
      } catch (_) {
        // 不完整行会在 EOF 完整性判断中自然判为失败。
      }
    }
    return false;
  }
}

/// Token 提取器 - 从 API 响应中提取 token 使用量
///
/// [extractUsage] 是权威方法，使用 JSON 解析精确提取 usage 对象中的各字段，
/// 支持非流式（单个 JSON 对象）和流式 SSE（多个 data: 行）两种格式。
///
/// 逐块正则方法（[extractInputTokens] 等）仅用于流式实时提取，
/// 会在 [handleDone] 阶段被 [extractUsage] 的 JSON 解析结果覆盖。
class TokenExtractor {
  static final _inputPattern = RegExp(r'"input_tokens"\s*:\s*(\d+)');
  static final _outputPattern = RegExp(r'"output_tokens"\s*:\s*(\d+)');
  static final _cacheCreationPattern = RegExp(
    r'"cache_creation_input_tokens"\s*:\s*(\d+)',
  );
  static final _cacheReadPattern = RegExp(
    r'"cache_read_input_tokens"\s*:\s*(\d+)',
  );

  const TokenExtractor();

  int? extractInputTokens(String text) {
    final match = _inputPattern.firstMatch(text);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  int? extractOutputTokens(String text) {
    final matches = _outputPattern.allMatches(text);
    if (matches.isEmpty) return null;
    return int.tryParse(matches.last.group(1)!);
  }

  int? extractCacheCreationTokens(String text) {
    final match = _cacheCreationPattern.firstMatch(text);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  int? extractCacheReadTokens(String text) {
    final match = _cacheReadPattern.firstMatch(text);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  /// 从完整响应文本中提取 usage（权威方法，使用 JSON 解析）。
  ///
  /// 先尝试解析为单个 JSON 对象（非流式响应），
  /// 失败后尝试解析 SSE 文本中的 data: 行（流式响应）。
  Map<String, int?>? extractUsage(String text) {
    final singleJsonUsage = _tryExtractFromJson(text);
    if (singleJsonUsage != null) return singleJsonUsage;

    return _extractUsageFromSSE(text);
  }

  Map<String, int?>? _tryExtractFromJson(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      final usage = json['usage'] as Map<String, dynamic>?;
      if (usage != null) {
        return _extractFromUsageMap(usage);
      }
    } catch (_) {}
    return null;
  }

  /// 从 SSE 文本的 data: 行中解析 JSON 并累积 usage。
  ///
  /// 对 message_start 事件，usage 位于 message.usage 路径下；
  /// 对 message_delta 事件，usage 位于顶层。
  Map<String, int?>? _extractUsageFromSSE(String text) {
    int? inputTokens;
    int? outputTokens;
    int? cacheCreationTokens;
    int? cacheReadTokens;

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data: ')) continue;
      final jsonStr = trimmed.substring(6);

      try {
        final json = jsonDecode(jsonStr);
        if (json is! Map<String, dynamic>) continue;

        Map<String, dynamic>? usage;
        if (json['type'] == 'message_start') {
          final message = json['message'] as Map<String, dynamic>?;
          usage = message?['usage'] as Map<String, dynamic>?;
        } else {
          usage = json['usage'] as Map<String, dynamic>?;
        }

        if (usage != null) {
          inputTokens = (usage['input_tokens'] as int?) ?? inputTokens;
          final output = usage['output_tokens'] as int?;
          if (output != null) outputTokens = output;
          cacheCreationTokens =
              (usage['cache_creation_input_tokens'] as int?) ??
              cacheCreationTokens;
          cacheReadTokens =
              (usage['cache_read_input_tokens'] as int?) ?? cacheReadTokens;
        }
      } catch (_) {}
    }

    if (inputTokens == null && outputTokens == null) return null;
    return {
      'input': inputTokens,
      'output': outputTokens,
      'cache_creation': cacheCreationTokens,
      'cache_read': cacheReadTokens,
    };
  }

  Map<String, int?> _extractFromUsageMap(Map<String, dynamic> usage) {
    return {
      'input': usage['input_tokens'] as int?,
      'output': usage['output_tokens'] as int?,
      'cache_creation': usage['cache_creation_input_tokens'] as int?,
      'cache_read': usage['cache_read_input_tokens'] as int?,
    };
  }
}
