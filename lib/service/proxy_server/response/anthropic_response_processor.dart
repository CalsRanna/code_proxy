import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/service/proxy_server/converter/anthropic_sse_writer.dart';
import 'package:code_proxy/service/proxy_server/response/anthropic_sse_scanner.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

import 'anthropic_sse_model_rewriter.dart';
import 'response_decompressor.dart';
import 'token_extractor.dart';
import 'upstream_stream_aborted_exception.dart';

class AnthropicResponseProcessor {
  const AnthropicResponseProcessor();

  /// 压缩流解码器：响应模型伪装开启时把上游压缩流先解码为 identity。
  ///
  /// 仅支持 gzip/deflate（请求侧 accept-encoding 白名单内），其他编码返回
  /// null 表示维持原样透传（跳过伪装）。
  static StreamTransformer<List<int>, List<int>>? _streamContentDecoder(
    String? normalizedEncoding,
  ) {
    switch (normalizedEncoding) {
      case 'gzip':
        return gzip.decoder;
      case 'deflate':
        return zlib.decoder;
      default:
        return null;
    }
  }

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
    recordStats, {
    String? originalModel,
  }) async {
    final responseBodyBytes = await response.stream.toBytes();
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    // 解压后提取 token 使用量（非流式响应）
    final decompressedBytes = ResponseDecompressor.decompress(
      responseBodyBytes,
      contentEncoding,
    );
    final bodyStr = utf8.decode(decompressedBytes, allowMalformed: true);

    // 响应模型伪装：把顶层 model 回填为客户端请求的原始模型名
    String clientBody = bodyStr;
    List<int> bodyToSend = responseBodyBytes;
    if (originalModel != null) {
      final rewritten = _rewriteModelInJson(bodyStr, originalModel);
      if (rewritten != null) {
        clientBody = rewritten;
        final normalizedEncoding = contentEncoding?.trim().toLowerCase();
        if (normalizedEncoding == 'gzip') {
          bodyToSend = gzip.encode(utf8.encode(rewritten));
        } else if (normalizedEncoding == 'deflate') {
          bodyToSend = zlib.encode(utf8.encode(rewritten));
        } else if (normalizedEncoding != null &&
            normalizedEncoding != 'identity') {
          // 无法重新压缩（br/zstd 等）：转为 identity 发送
          responseHeaders.remove('content-encoding');
          bodyToSend = utf8.encode(rewritten);
        } else {
          bodyToSend = utf8.encode(rewritten);
        }
      }
    }

    final usage = extractor.extractUsage(clientBody);

    recordStats(responseTime, usage, clientBody);

    return shelf.Response(
      response.statusCode,
      headers: responseHeaders,
      body: bodyToSend,
    );
  }

  /// 非流式响应体中的 model 字段改写。
  ///
  /// 仅当响应体为 JSON 对象且顶层含字符串 `model` 时替换；解析失败或结构
  /// 不符返回 null（调用方原样透传）。
  static String? _rewriteModelInJson(String body, String targetModel) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['model'] is! String) return null;
      decoded['model'] = targetModel;
      return jsonEncode(decoded);
    } catch (e) {
      LoggerUtil.instance.w('Failed to rewrite model in response body: $e');
      return null;
    }
  }

  shelf.Response processStreamResponse(
    http.StreamedResponse response,
    Map<String, String> responseHeaders,
    int startTime,
    String? contentEncoding,
    void Function(
      Map<String, int?>? tokenUsage,
      int responseTime,
      String responseBody,
    )
    recordStats,
    void Function(Object error, String responseBody) recordException, {
    void Function()? onStreamError,
    String? originalModel,
  }) {
    final responseChunks = <String>[];
    final normalizedEncoding = contentEncoding?.trim().toLowerCase();
    var isCompressed =
        normalizedEncoding != null &&
        normalizedEncoding.isNotEmpty &&
        normalizedEncoding != 'identity';

    // 响应模型伪装开启且上游为压缩流时：流式解压后统一走文本改写管线，
    // 输出 identity（不再转发压缩字节），避免为改写而整段缓存重压。
    // 请求侧已把 accept-encoding 限定为 gzip/deflate，其他编码（br/zstd）
    // 无法解压，跳过伪装原样透传。
    Stream<List<int>> upstreamStream = response.stream;
    if (originalModel != null && isCompressed) {
      final decoder = _streamContentDecoder(normalizedEncoding);
      if (decoder != null) {
        isCompressed = false;
        upstreamStream = response.stream.transform(decoder);
        responseHeaders.remove('content-encoding');
      } else {
        LoggerUtil.instance.w(
          'Unsupported content-encoding ($normalizedEncoding) for model '
          'spoofing, passing through unchanged',
        );
      }
    }
    final modelRewriter = originalModel != null
        ? AnthropicSseModelRewriter(originalModel)
        : null;
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
    // 压缩流与非压缩流共用同一个扫描器：非压缩流边流边喂，压缩流在流结束
    // 解压后一次性喂入。完成信号与 usage 因此天然同口径，不会分叉。
    final scanner = AnthropicSseScanner();
    var failed = false;
    final canEmitSseError =
        !isCompressed &&
        (response.headers['content-type'] ?? '').contains('text/event-stream');

    List<int> buildSseError(Object error) {
      if (!canEmitSseError) return const [];
      return utf8.encode(buildSseErrorEventText(error.toString()));
    }

    final transformedStream = upstreamStream.transform(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          if (isCompressed) {
            // 原始数据原封不动转发给客户端
            sink.add(chunk);
            // 压缩数据先收集，流结束后统一解压
            rawChunks!.add(chunk);
          } else {
            utf8Sink!.add(chunk);
            final text = utf8Buffer.toString();
            utf8Buffer.clear();
            if (text.isEmpty) return;
            if (modelRewriter == null) {
              // 无伪装：原样转发原始字节（与历史行为一致）
              responseChunks.add(text);
              scanner.add(text);
              sink.add(chunk);
            } else {
              final forwarded = modelRewriter.add(text);
              if (forwarded.isNotEmpty) {
                responseChunks.add(forwarded);
                scanner.add(forwarded);
                sink.add(utf8.encode(forwarded));
              }
            }
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
            scanner.add(text);
          } else {
            // 刷新 decoder 尾部缓冲（跨 chunk 的不完整序列在此收尾）
            utf8Sink!.close();
            final tail = utf8Buffer.toString();
            if (tail.isNotEmpty) {
              if (modelRewriter == null) {
                responseChunks.add(tail);
                scanner.add(tail);
              } else {
                final forwarded = modelRewriter.add(tail);
                if (forwarded.isNotEmpty) {
                  responseChunks.add(forwarded);
                  scanner.add(forwarded);
                  sink.add(utf8.encode(forwarded));
                }
              }
            }
          }
          // 处理最后一行没有换行结尾的残留（含伪装改写器的行缓冲）
          final flushed = modelRewriter?.flush() ?? '';
          if (flushed.isNotEmpty) {
            responseChunks.add(flushed);
            scanner.add(flushed);
            sink.add(utf8.encode(flushed));
          }
          scanner.flush();

          final responseBody = responseChunks.join();

          if (!scanner.sawCompletionSignal) {
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

          recordStats(scanner.usage, responseTime, responseBody);
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
}
