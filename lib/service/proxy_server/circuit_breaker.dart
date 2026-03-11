/// 断路器状态
enum CircuitBreakerState { closed, open, halfOpen }

/// 断路器 - 智能管理端点可用性
class CircuitBreaker {
  final String endpointId;
  final int failureThreshold;
  final int recoveryTimeoutMs;
  final int slidingWindowMs;

  CircuitBreakerState _state = CircuitBreakerState.closed;
  final List<int> _failureTimestamps = [];
  int? _openedAt;
  bool _halfOpenProbing = false;

  CircuitBreaker({
    required this.endpointId,
    this.failureThreshold = 5,
    this.recoveryTimeoutMs = 60000,
    this.slidingWindowMs = 120000,
  });

  CircuitBreakerState get state {
    if (_state == CircuitBreakerState.open && _openedAt != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _openedAt! >= recoveryTimeoutMs) {
        _state = CircuitBreakerState.halfOpen;
        _halfOpenProbing = false;
      }
    }
    return _state;
  }

  /// 是否允许请求通过
  bool get allowRequest {
    switch (state) {
      case CircuitBreakerState.closed:
        return true;
      case CircuitBreakerState.open:
        return false;
      case CircuitBreakerState.halfOpen:
        // halfOpen 状态下只允许一个探测请求
        if (!_halfOpenProbing) {
          _halfOpenProbing = true;
          return true;
        }
        return false;
    }
  }

  /// 记录成功
  void recordSuccess() {
    if (_state == CircuitBreakerState.halfOpen) {
      _state = CircuitBreakerState.closed;
      _failureTimestamps.clear();
      _openedAt = null;
      _halfOpenProbing = false;
    }
  }

  /// 记录失败
  void recordFailure() {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (state == CircuitBreakerState.halfOpen) {
      // halfOpen 探测失败 → 回到 open
      _state = CircuitBreakerState.open;
      _openedAt = now;
      _halfOpenProbing = false;
      return;
    }

    // closed 状态：滑动窗口计数
    _failureTimestamps.add(now);
    // 清除窗口外的失败记录
    _failureTimestamps.removeWhere((t) => now - t > slidingWindowMs);

    if (_failureTimestamps.length >= failureThreshold) {
      _state = CircuitBreakerState.open;
      _openedAt = now;
      _halfOpenProbing = false;
    }
  }

  /// 强制打开断路器（用于 429 等需要立即断路的场景）
  void forceOpen() {
    _state = CircuitBreakerState.open;
    _openedAt = DateTime.now().millisecondsSinceEpoch;
    _halfOpenProbing = false;
  }

  /// 手动重置到 closed
  void reset() {
    _state = CircuitBreakerState.closed;
    _failureTimestamps.clear();
    _openedAt = null;
    _halfOpenProbing = false;
  }
}

/// 断路器注册表 - 管理所有端点的断路器
class CircuitBreakerRegistry {
  final int failureThreshold;
  final int recoveryTimeoutMs;
  final int slidingWindowMs;
  final Map<String, CircuitBreaker> _breakers = {};

  CircuitBreakerRegistry({
    this.failureThreshold = 5,
    this.recoveryTimeoutMs = 60000,
    this.slidingWindowMs = 120000,
  });

  CircuitBreaker getBreaker(String endpointId) {
    return _breakers.putIfAbsent(
      endpointId,
      () => CircuitBreaker(
        endpointId: endpointId,
        failureThreshold: failureThreshold,
        recoveryTimeoutMs: recoveryTimeoutMs,
        slidingWindowMs: slidingWindowMs,
      ),
    );
  }

  void reset(String endpointId) {
    _breakers[endpointId]?.reset();
  }

  void resetAll() {
    for (final breaker in _breakers.values) {
      breaker.reset();
    }
  }
}
