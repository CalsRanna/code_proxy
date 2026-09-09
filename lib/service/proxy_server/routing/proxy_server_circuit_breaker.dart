/// 断路器状态
enum ProxyServerCircuitBreakerState { closed, open, halfOpen }

/// 同一端点跨请求、跨模型共享的连续失败断路器。
///
/// 关闭时连续失败 [failureThreshold] 次后打开，记录成功则清零计数。
/// 多个并发请求共同贡献失败，不为每个请求分配独立的重试配额。
/// 打开后等待 [recoveryTimeoutMs] 毫秒才允许半开探测；探测成功则恢复，
/// 失败则立即重新打开。
///
/// 状态更新在同一 isolate 内同步完成；调用方的异步等待不会锁定状态，
/// 等待期间其他请求仍可改变断路器状态。
class ProxyServerCircuitBreaker {
  final String endpointId;
  final int failureThreshold;
  final int recoveryTimeoutMs;

  ProxyServerCircuitBreakerState _state = ProxyServerCircuitBreakerState.closed;
  int _consecutiveFailures = 0;
  int? _openedAt;

  ProxyServerCircuitBreaker({
    required this.endpointId,
    this.failureThreshold = 5,
    this.recoveryTimeoutMs = 60000,
  });

  /// 当前状态（纯读取，不触发状态转换）
  ProxyServerCircuitBreakerState get state => _state;

  /// 评估并更新状态（处理 open -> halfOpen 的超时转换）
  /// 需要检查状态转换时应显式调用此方法，而非通过 state getter
  ProxyServerCircuitBreakerState evaluateState() {
    if (_state == ProxyServerCircuitBreakerState.open && _openedAt != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _openedAt! >= recoveryTimeoutMs) {
        _state = ProxyServerCircuitBreakerState.halfOpen;
      }
    }
    return _state;
  }

  /// 端点是否可用（用于端点过滤和请求放行）
  ///
  /// closed / halfOpen 状态返回 true，open 状态返回 false。
  /// halfOpen 状态下允许多个请求通过以探测端点是否恢复，
  /// 由 [recordSuccess] / [recordFailure] 驱动状态转换。
  bool get isAvailable {
    final currentState = evaluateState();
    return currentState != ProxyServerCircuitBreakerState.open;
  }

  /// 记录成功
  void recordSuccess() {
    if (_state == ProxyServerCircuitBreakerState.halfOpen) {
      _state = ProxyServerCircuitBreakerState.closed;
      _consecutiveFailures = 0;
      _openedAt = null;
    } else if (_state == ProxyServerCircuitBreakerState.closed) {
      _consecutiveFailures = 0;
    }
  }

  /// 记录失败
  void recordFailure() {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_state == ProxyServerCircuitBreakerState.halfOpen) {
      _state = ProxyServerCircuitBreakerState.open;
      _openedAt = now;
      return;
    }

    if (_state != ProxyServerCircuitBreakerState.closed) return;

    _consecutiveFailures++;
    if (_consecutiveFailures >= failureThreshold) {
      _state = ProxyServerCircuitBreakerState.open;
      _openedAt = now;
    }
  }

  /// 手动重置到 closed
  void reset() {
    _state = ProxyServerCircuitBreakerState.closed;
    _consecutiveFailures = 0;
    _openedAt = null;
  }
}
