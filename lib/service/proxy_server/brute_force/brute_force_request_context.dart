import 'dart:async';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request_cancellation.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request_handler.dart';

class BruteForceRequestContext {
  final EndpointEntity endpoint;
  final ProxyServerRequestHandler handler;
  final cancellation = ProxyServerRequestCancellation();
  final stopwatch = Stopwatch()..start();
  final Duration timeout;
  late final Timer _deadline;
  late final void Function() _removeParent;
  bool _disposed = false;

  BruteForceRequestContext({
    required this.endpoint,
    required ProxyServerConfig config,
    required ProxyServerRequestCancellation parent,
  }) : handler = ProxyServerRequestHandler(config),
       timeout = Duration(milliseconds: config.apiTimeoutMs) {
    cancellation.onCancel(handler.close);
    _removeParent = parent.onCancel(() => cancellation.cancel(parent.reason!));
    _deadline = Timer(timeout, _expire);
  }

  int get remainingMs =>
      (timeout.inMilliseconds - stopwatch.elapsedMilliseconds).clamp(
        0,
        timeout.inMilliseconds,
      );

  void _expire() {
    cancellation.cancel(
      TimeoutException('Brute force retry deadline exceeded', timeout),
    );
  }

  void checkBudget() {
    if (remainingMs == 0) _expire();
    cancellation.throwIfCancelled();
  }

  void finishRetryWindow() {
    checkBudget();
    _deadline.cancel();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _deadline.cancel();
    _removeParent();
    handler.close();
    stopwatch.stop();
  }
}
