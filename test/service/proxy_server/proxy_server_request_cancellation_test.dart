import 'dart:async';

import 'package:code_proxy/service/proxy_server/proxy_server_request_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cancelled = ProxyServerRequestCancelled('test cancellation');

  test('cancels a long retry wait and notifies only once', () async {
    final cancellation = ProxyServerRequestCancellation();
    var notifications = 0;
    cancellation.onCancel(() => notifications++);
    final waiting = cancellation.wait(const Duration(days: 1));
    final assertion = expectLater(waiting, throwsA(same(cancelled)));
    cancellation.cancel(cancelled);
    cancellation.cancel(cancelled);
    await assertion;
    expect(notifications, 1);
  });

  test('observes late errors without resuming a cancelled operation', () async {
    final cancellation = ProxyServerRequestCancellation();
    final operation = Completer<int>();
    final waiting = cancellation.run(operation.future);
    final assertion = expectLater(waiting, throwsA(same(cancelled)));
    cancellation.cancel(cancelled);
    await assertion;
    operation.completeError(StateError('late I/O error'));
    await Future<void>.delayed(Duration.zero);
  });

  test('completion racing cancellation never completes twice', () async {
    final cancellation = ProxyServerRequestCancellation();
    final source = Completer<int>();
    final result = cancellation.run(source.future);
    source.future.then((_) => cancellation.cancel(cancelled));
    final assertion = expectLater(result, throwsA(same(cancelled)));
    source.complete(1);
    await assertion;
  });

  test('stream cancellation closes downstream and cancels source', () async {
    final cancellation = ProxyServerRequestCancellation();
    var sourceCancelled = false;
    var cleaned = 0;
    final source = StreamController<int>(
      onCancel: () => sourceCancelled = true,
    );
    final chunks = <int>[];
    final done = Completer<void>();
    cancellation
        .bindStream(
          source.stream,
          cancelWithError: false,
          onDone: () => cleaned++,
        )
        .listen(chunks.add, onDone: done.complete);
    source.add(1);
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel(cancelled);
    await done.future;
    expect(chunks, [1]);
    expect(sourceCancelled, isTrue);
    expect(cleaned, 1);
    await source.close();
  });
}
