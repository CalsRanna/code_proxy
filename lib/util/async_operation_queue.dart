import 'dart:async';

/// 串行执行异步操作；同一操作内部可重入，失败不会阻塞后续操作。
class AsyncOperationQueue {
  final _zoneKey = Object();
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final scope = Zone.current[_zoneKey] as _OperationScope?;
    if (scope?.active ?? false) return Future<T>.sync(action);

    final result = _tail.then((_) async {
      final current = _OperationScope();
      try {
        return await runZoned(action, zoneValues: {_zoneKey: current});
      } finally {
        // 事务派生、但在事务结束后才执行的异步回调不能继续绕过队列。
        current.active = false;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

class _OperationScope {
  bool active = true;
}
