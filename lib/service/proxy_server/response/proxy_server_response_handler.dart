import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

import 'anthropic_response_processor.dart';
import 'openai_response_processor.dart';
import 'request_attempt_context.dart';
import 'request_attempt_recorder.dart';
import 'response_decompressor.dart';
import 'token_extractor.dart';

/// 按状态码、协议和流式类型分派响应；重试由代理主循环决定。
class ProxyServerResponseHandler {
  final _anthropicProcessor = const AnthropicResponseProcessor();
  final _tokenExtractor = const TokenExtractor();
  final OpenAiResponseProcessor _openAiProcessor;
  final RequestAttemptRecorder _recorder;
  final void Function(EndpointEntity)? _onStreamError;

  ProxyServerResponseHandler({
    required RequestAttemptRecorder recorder,
    void Function(EndpointEntity)? onStreamError,
  }) : _recorder = recorder,
       _onStreamError = onStreamError,
       _openAiProcessor = OpenAiResponseProcessor(
         recorder: recorder,
         onStreamError: onStreamError,
       );

  Future<shelf.Response> handleResponse(
    http.StreamedResponse response,
    RequestAttemptContext attempt,
  ) async {
    final needsConversion =
        attempt.endpoint.apiFormat != EndpointApiFormat.anthropic;
    final contentEncoding = response.headers['content-encoding'];

    if (response.statusCode >= 400) {
      final bytes = await response.stream.toBytes();
      final responseTime =
          DateTime.now().millisecondsSinceEpoch - attempt.startTime!;
      final body = ResponseDecompressor.decodeForLogging(
        bytes,
        contentEncoding,
      );
      if (needsConversion) {
        return _openAiProcessor.processErrorResponse(response, attempt, body);
      }
      final headers = _forwardedHeaders(response);
      _recorder.recordResponse(
        attempt,
        response,
        responseTime: responseTime,
        forwardedResponseHeaders: headers,
        tokenUsage: _tokenExtractor.extractUsage(body),
        errorBody: body,
        responseBody: body,
      );
      return shelf.Response(response.statusCode, headers: headers, body: bytes);
    }

    final isStream = _anthropicProcessor.isStream(response.headers);
    if (needsConversion) {
      return isStream
          ? _openAiProcessor.processStreamResponse(response, attempt)
          : await _openAiProcessor.processNormalResponse(response, attempt);
    }

    final headers = _forwardedHeaders(response);
    void recordStats(
      int responseTime,
      Map<String, int?>? usage,
      String? responseBody, {
      int? ttftMs,
    }) {
      _recorder.recordResponse(
        attempt,
        response,
        responseTime: responseTime,
        ttftMs: ttftMs,
        forwardedResponseHeaders: headers,
        tokenUsage: usage,
        responseBody: responseBody,
      );
    }

    if (isStream) {
      return _anthropicProcessor.processStreamResponse(
        response,
        headers,
        attempt.startTime!,
        contentEncoding,
        (usage, responseTime, body, ttftMs) =>
            recordStats(responseTime, usage, body, ttftMs: ttftMs),
        (error, body) => _recorder.recordException(
          attempt,
          error,
          responseBody: body.isEmpty ? null : body,
        ),
        onStreamError: () => _onStreamError?.call(attempt.endpoint),
        originalModel: attempt.originalModel,
        bodyWriter: attempt.bodyWriter,
      );
    }
    return _anthropicProcessor.processNormalResponse(
      response,
      headers,
      attempt.startTime!,
      _tokenExtractor,
      contentEncoding,
      recordStats,
      originalModel: attempt.originalModel,
    );
  }

  Map<String, String> _forwardedHeaders(http.StreamedResponse response) =>
      Map<String, String>.from(response.headers)
        ..remove('transfer-encoding')
        ..remove('content-length');
}
