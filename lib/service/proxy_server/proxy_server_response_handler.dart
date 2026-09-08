import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_compat_response_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_compat_stream_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_responses_response_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_responses_stream_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_sse_converter.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/response_processor.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

import 'response_decompressor.dart';
import 'token_extractor.dart';
import 'upstream_stream_aborted_exception.dart';

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

  /// 处理单次上游 HTTP 响应并通过回调记录结果。
  ///
  /// 是否重试由调用方根据状态码和重试开关决定。
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

    // 4xx 与 5xx 走同一条错误路径：读取错误体、记录日志、把原始字节回传。
    // 是否重试 / 熔断 / 故障转移由 ProxyServerService 按状态码和开关决定。
    if (statusCode >= 400) {
      final responseBodyBytes = await response.stream.toBytes();
      final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

      // 解压并解码响应体以保存错误信息
      final contentEncoding = response.headers['content-encoding'];
      final bodyStr = ResponseDecompressor.decodeForLogging(
        responseBodyBytes,
        contentEncoding,
      );
      // 失败请求同样可能已消耗 token（5xx 常发生在推理之后），如实提取
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
    }

    // 2xx / 3xx 正常透传（含流式）。3xx 是重定向或缓存语义，端点没有故障，
    // 不进重试与断路器 —— 与 ProxyServerService 的判定保持一致。
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
    // 响应模型伪装（默认行为）：Anthropic 透传路径把响应中的 model 回填为
    // 客户端请求的原始模型名，仅改响应呈现、不改变已映射的上游请求。
    // OpenAI 转换路径由转换器回填，两条路径行为一致。
    final originalModel = _extractOriginalModel(originalRequestBodyBytes);
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
        originalModel: originalModel,
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
        originalModel: originalModel,
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
