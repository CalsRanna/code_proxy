import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:http/http.dart' as http;

import 'request_attempt_context.dart';

/// 将一次尝试组装为请求、响应快照，再交给应用层持久化。
class RequestAttemptRecorder {
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  onRequestCompleted;

  const RequestAttemptRecorder({this.onRequestCompleted});

  void recordResponse(
    RequestAttemptContext attempt,
    http.StreamedResponse response, {
    required int responseTime,
    int? ttftMs,
    Map<String, String>? forwardedResponseHeaders,
    Map<String, int?>? tokenUsage,
    String? errorBody,
    String? responseBody,
    String? rawResponseBody,
  }) {
    _record(
      attempt,
      ProxyServerResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        forwardedHeaders: forwardedResponseHeaders,
        responseTime: responseTime,
        ttftMs: ttftMs,
        usage: tokenUsage,
        errorBody: errorBody,
        responseBody: responseBody,
        rawResponseBody: rawResponseBody,
      ),
    );
  }

  void recordException(
    RequestAttemptContext attempt,
    Object error, {
    int statusCode = HttpStatus.badGateway,
    String? rawResponseBody,
    String? responseBody,
  }) {
    final startTime = attempt.startTime;
    _record(
      attempt,
      ProxyServerResponse(
        statusCode: statusCode,
        headers: {},
        responseTime: startTime == null
            ? 0
            : DateTime.now().millisecondsSinceEpoch - startTime,
        errorBody: error.toString(),
        rawResponseBody: rawResponseBody,
        responseBody: responseBody,
      ),
    );
  }

  void _record(RequestAttemptContext attempt, ProxyServerResponse response) {
    final request = ProxyServerRequest(
      path: attempt.request.url.path,
      method: attempt.request.method,
      body: utf8.decode(
        attempt.forwardedRequestBodyBytes,
        allowMalformed: true,
      ),
      originalModel: attempt.originalModel,
      mappedModel: attempt.mappedModel,
      originalBody: utf8.decode(
        attempt.originalRequestBodyBytes,
        allowMalformed: true,
      ),
      headers: attempt.request.headers,
      forwardedHeaders: attempt.forwardedHeaders,
    );
    onRequestCompleted?.call(attempt.endpoint, request, response);
  }
}
