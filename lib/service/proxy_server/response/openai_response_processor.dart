import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_chat_response_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_chat_stream_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_responses_response_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_responses_stream_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_sse_converter.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

import 'request_attempt_context.dart';
import 'request_attempt_recorder.dart';
import 'response_decompressor.dart';
import 'token_extractor.dart';
import 'upstream_stream_aborted_exception.dart';

/// 将 OpenAI 普通、错误及流式响应转换为 Anthropic 响应。
class OpenAiResponseProcessor {
  final RequestAttemptRecorder _recorder;
  final void Function(EndpointEntity)? _onStreamError;
  final _tokenExtractor = const TokenExtractor();
  final _openAiResponseConverter = const OpenAiChatResponseConverter();
  final _openAiResponsesResponseConverter =
      const OpenAiResponsesResponseConverter();

  OpenAiResponseProcessor({
    required RequestAttemptRecorder recorder,
    void Function(EndpointEntity)? onStreamError,
  }) : _recorder = recorder,
       _onStreamError = onStreamError;

  /// OpenAI 端点的错误响应：转换错误体并记录日志后返回。
  ///
  /// 返回给客户端的是 Anthropic 错误格式；审计中 responseBody/errorBody
  /// 均记录客户端实际收到的转换后文本。
  shelf.Response processErrorResponse(
    http.StreamedResponse response,
    RequestAttemptContext attempt,
    String upstreamErrorBody,
  ) {
    final responseTime =
        DateTime.now().millisecondsSinceEpoch - attempt.startTime!;
    // 两种 OpenAI API 的错误体结构同构（{error:{message,type,code}}），
    // 复用同一转换实现
    final convertedJson = _openAiResponseConverter.convertErrorBody(
      upstreamErrorBody,
    );
    final clientFacingBody = jsonEncode(convertedJson);

    _recorder.recordResponse(
      attempt,
      response,
      responseTime: responseTime,
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

  /// OpenAI 端点：非流式响应转换（chat.completion → Anthropic message）。
  Future<shelf.Response> processNormalResponse(
    http.StreamedResponse response,
    RequestAttemptContext attempt,
  ) async {
    final contentEncoding = response.headers['content-encoding'];
    final responseBodyBytes = await response.stream.toBytes();
    final responseTime =
        DateTime.now().millisecondsSinceEpoch - attempt.startTime!;

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
            attempt.endpoint.apiFormat == EndpointApiFormat.openaiResponses
            ? _openAiResponsesResponseConverter.convertResponse(
                decodedJson,
                originalModel: attempt.originalModel,
              )
            : _openAiResponseConverter.convertResponse(
                decodedJson,
                originalModel: attempt.originalModel,
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

    _recorder.recordResponse(
      attempt,
      response,
      responseTime: responseTime,
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

  /// OpenAI 端点：流式响应转换（OpenAI SSE chunk 流 → Anthropic 事件流）。
  ///
  /// message_start/ping 在上游首字节到达前先行产出，保证客户端尽快收到响应。
  shelf.Response processStreamResponse(
    http.StreamedResponse response,
    RequestAttemptContext attempt,
  ) {
    final originalModel = attempt.originalModel;
    final OpenAiSseConverter converter =
        attempt.endpoint.apiFormat == EndpointApiFormat.openaiResponses
        ? OpenAiResponsesSseStreamConverter(originalModel: originalModel)
        : OpenAiChatSseStreamConverter(originalModel: originalModel);
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

        final responseTime =
            DateTime.now().millisecondsSinceEpoch - attempt.startTime!;
        final rawStreamText = utf8.decode(
          rawChunks.expand((c) => c).toList(),
          allowMalformed: true,
        );
        _recorder.recordResponse(
          attempt,
          response,
          responseTime: responseTime,
          forwardedResponseHeaders: _openAiStreamHeaders(),
          tokenUsage: converter.finalUsage,
          responseBody: outputChunks.join(),
          rawResponseBody: rawStreamText,
        );
      } catch (error) {
        LoggerUtil.instance.w('Upstream OpenAI stream error: $error');
        // 流中途失败：对端点补记失败，避免损坏的流被记为成功
        _onStreamError?.call(attempt.endpoint);

        // 错误事件输出也留存：截断场景仍写入审计（半截原始流 + error 事件），
        // 保证本地可还原中断点
        final errorEvents = converter.handleError(error);
        if (errorEvents.isNotEmpty) {
          outputChunks.add(utf8.decode(errorEvents));
        }
        _recorder.recordException(
          attempt,
          error,
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

  /// OpenAI 端点非流式响应的转发头。
  ///
  /// 响应体已整体重写（解压 + 格式转换），content-encoding/content-length
  /// 均不再适用。
  Map<String, String> _openAiJsonHeaders() => const {
    'content-type': 'application/json',
  };

  /// OpenAI 端点流式响应的转发头
  Map<String, String> _openAiStreamHeaders() => const {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache',
  };
}
