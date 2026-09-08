import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/brute_force/brute_force_request_context.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request_cancellation.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request_handler.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response_handler.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_retry_delay.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:uuid/uuid.dart';

/// Fixed-endpoint retries with a single budget, independent of normal routing.
class ProxyServerBruteForceExecutor {
  final ProxyServerConfig config;
  final _active = <BruteForceRequestContext>{};
  List<EndpointEntity> _endpoints = [];

  ProxyServerBruteForceExecutor(this.config);

  bool get hasEnabledEndpoints => _endpoints.isNotEmpty;

  void setEndpoints(List<EndpointEntity> endpoints) {
    _endpoints = endpoints.where((endpoint) => endpoint.enabled).toList();
    final ids = _endpoints.map((endpoint) => endpoint.id).toSet();
    for (final context in _active.toList()) {
      if (!ids.contains(context.endpoint.id)) {
        context.cancellation.cancel(
          const ProxyServerRequestCancelled('Endpoint disabled or removed'),
        );
      }
    }
  }

  Future<shelf.Response> execute(
    shelf.Request request,
    List<int> rawBody,
    ProxyServerRequestCancellation cancellation, {
    void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
    onRequestCompleted,
  }) async {
    cancellation.throwIfCancelled();
    if (_endpoints.isEmpty) {
      return _error(HttpStatus.serviceUnavailable, 'No enabled endpoints');
    }
    final endpoint = _endpoints.first;
    final context = BruteForceRequestContext(
      endpoint: endpoint,
      config: config,
      parent: cancellation,
    );
    _active.add(context);
    final requestId = const Uuid().v4();
    var attempt = 0;
    var attemptCompleted = false;
    var responseOwnsContext = false;
    int? startTime;
    http.Request? prepared;

    void dispose() {
      context.dispose();
      _active.remove(context);
      LoggerUtil.instance.d(
        'brute_force request=$requestId endpoint=${endpoint.id} '
        'attempts=$attempt elapsed_ms=${context.stopwatch.elapsedMilliseconds} '
        'result=${context.cancellation.reason?.runtimeType ?? (responseOwnsContext ? 'response_completed' : 'failed')}'
        '${context.cancellation.reason is ProxyServerRequestCancelled ? ' reason=${context.cancellation.reason}' : ''}',
      );
    }

    final responseHandler = ProxyServerResponseHandler(
      onRequestCompleted: (endpoint, request, response) {
        if (context.cancellation.isCancelled) return;
        attemptCompleted = true;
        onRequestCompleted?.call(endpoint, request, response);
      },
    );

    try {
      context.checkBudget();
      prepared = context.handler.prepareRequest(
        request,
        endpoint,
        rawBody,
        bodyCache: ProxyServerBodyCache(),
      );
      while (true) {
        context.checkBudget();
        attempt++;
        attemptCompleted = false;
        startTime = DateTime.now().millisecondsSinceEpoch;
        String? retryAfter;
        try {
          // A fresh request object, with identical prepared bytes and headers.
          final outgoing = http.Request(prepared.method, prepared.url)
            ..headers.addAll(prepared.headers)
            ..bodyBytes = prepared.bodyBytes
            ..followRedirects = prepared.followRedirects
            ..maxRedirects = prepared.maxRedirects
            ..persistentConnection = prepared.persistentConnection;
          final upstream = await context.cancellation.run(
            context.handler.forwardRequest(outgoing),
          );
          context.checkBudget();
          final response = await context.cancellation.run(
            responseHandler.handleResponse(
              upstream,
              endpoint,
              request,
              rawBody,
              startTime,
              mappedRequestBodyBytes: prepared.bodyBytes,
              forwardedHeaders: prepared.headers,
            ),
          );
          context.checkBudget();
          if (upstream.statusCode >= 200 && upstream.statusCode < 400) {
            context.finishRetryWindow();
            final result = response!;
            responseOwnsContext = true;
            return result.change(
              body: context.cancellation.bindStream(
                result.read(),
                cancelWithError: false,
                onDone: dispose,
              ),
            );
          }
          retryAfter = upstream.headers['retry-after'];
          LoggerUtil.instance.w(
            'brute_force request=$requestId endpoint=${endpoint.id} '
            'attempt=$attempt status=${upstream.statusCode} '
            'remaining_ms=${context.remainingMs}',
          );
        } catch (error) {
          context.checkBudget();
          if (!_isTransportError(error)) rethrow;
          if (!attemptCompleted) {
            responseHandler.recordException(
              endpoint: endpoint,
              request: request,
              requestBodyBytes: rawBody,
              startTime: startTime,
              error: error,
              mappedRequestBodyBytes: prepared.bodyBytes,
              forwardedHeaders: prepared.headers,
            );
          }
          LoggerUtil.instance.w(
            'brute_force request=$requestId endpoint=${endpoint.id} '
            'attempt=$attempt transport_error=${error.runtimeType} '
            'remaining_ms=${context.remainingMs}',
          );
        }
        await context.cancellation.wait(
          retryDelay(attempt, retryAfter: retryAfter),
        );
      }
    } on ProxyServerRequestCancelled {
      rethrow;
    } catch (error) {
      final timedOut = error is TimeoutException;
      final status = timedOut
          ? HttpStatus.gatewayTimeout
          : HttpStatus.badGateway;
      final message = timedOut
          ? 'Brute force retry deadline exceeded after $attempt attempts'
          : 'Unable to process upstream request';
      if (!attemptCompleted) {
        // The deadline has cancelled the context; explicitly log its final
        // attempt once, without accepting late callbacks from the old I/O.
        ProxyServerResponseHandler(
          onRequestCompleted: onRequestCompleted,
        ).recordException(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: rawBody,
          startTime: startTime,
          error: message,
          statusCode: status,
          mappedRequestBodyBytes: prepared?.bodyBytes,
          forwardedHeaders: prepared?.headers,
        );
      }
      return _error(status, message);
    } finally {
      if (!responseOwnsContext) dispose();
    }
  }

  static bool _isTransportError(Object error) =>
      error is http.ClientException ||
      error is SocketException ||
      error is HttpException ||
      error is TlsException ||
      error is TimeoutException;

  static Duration retryDelay(
    int failedAttempt, {
    String? retryAfter,
    DateTime? now,
    Random? random,
  }) {
    final minimum = Duration(
      milliseconds: calculateProxyRetryDelayMs(
        failedAttempt + 1,
        random: random,
      ),
    );
    if (retryAfter == null) return minimum;
    final seconds = int.tryParse(retryAfter.trim());
    Duration delay;
    if (seconds != null) {
      // Waiting longer than the largest supported request budget is equivalent
      // to waiting for its deadline, and avoids Duration integer overflow.
      delay = Duration(seconds: seconds.clamp(0, 3600));
    } else {
      try {
        delay = HttpDate.parse(retryAfter).difference(now ?? DateTime.now());
      } on HttpException {
        return minimum;
      }
    }
    return delay < minimum ? minimum : delay;
  }

  static shelf.Response _error(int status, String message) => shelf.Response(
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
    body: jsonEncode({
      'type': 'error',
      'error': {'type': 'api_error', 'message': message},
    }),
  );
}
