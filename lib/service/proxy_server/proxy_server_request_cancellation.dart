import 'dart:async';

class ProxyServerRequestCancelled implements Exception {
  final String reason;

  const ProxyServerRequestCancelled(this.reason);

  @override
  String toString() => reason;
}

/// Request cancellation shared by forwarding, retry waits and response streams.
class ProxyServerRequestCancellation {
  Object? _reason;
  final Set<void Function()> _listeners = {};

  bool get isCancelled => _reason != null;
  Object? get reason => _reason;

  void throwIfCancelled() {
    final reason = _reason;
    if (reason != null) throw reason;
  }

  void cancel(Object reason) {
    if (isCancelled) return;
    _reason = reason;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  /// Returns a function which unregisters the listener.
  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  Future<T> run<T>(Future<T> operation) async {
    final result = Completer<T>();
    final remove = onCancel(() {
      if (!result.isCompleted) result.completeError(_reason!);
    });
    // Always observe operation, including errors arriving after cancellation.
    operation.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    try {
      final value = await result.future;
      throwIfCancelled();
      return value;
    } finally {
      remove();
    }
  }

  Future<void> wait(Duration duration) async {
    throwIfCancelled();
    final completed = Completer<void>();
    final timer = Timer(duration, completed.complete);
    try {
      await run(completed.future);
    } finally {
      timer.cancel();
    }
  }

  Stream<T> bindStream<T>(
    Stream<T> source, {
    bool cancelWithError = true,
    void Function()? onDone,
  }) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    void Function() remove = () {};
    var finished = false;

    void finish() {
      if (finished) return;
      finished = true;
      remove();
      onDone?.call();
    }

    void cancelled() {
      if (finished) return;
      if (cancelWithError) controller.addError(_reason!);
      unawaited(subscription?.cancel());
      unawaited(controller.close());
      finish();
    }

    controller = StreamController<T>(
      onListen: () {
        if (isCancelled) {
          cancelled();
          return;
        }
        remove = onCancel(cancelled);
        subscription = source.listen(
          (data) {
            if (!finished) controller.add(data);
          },
          onError: (Object error, StackTrace stack) {
            if (!finished) controller.addError(error, stack);
          },
          onDone: () {
            unawaited(controller.close());
            finish();
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        finish();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
