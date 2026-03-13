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
  bool _hasBeenOpened = false;

  CircuitBreaker({
    required this.endpointId,
    this.failureThreshold = 5,
    this.recoveryTimeoutMs = 60000,
    this.slidingWindowMs = 120000,
  });

  /// 当前状态（纯读取，不触发状态转换）
  CircuitBreakerState get state => _state;

  /// 断路器是否曾经被打开过（用于区分新建断路器和恢复后的断路器）
  bool get hasBeenOpened => _hasBeenOpened;

  /// 评估并更新状态（处理 open → halfOpen 的超时转换）
  /// 需要检查状态转换时应显式调用此方法，而非通过 state getter
  CircuitBreakerState evaluateState() {
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
    final currentState = evaluateState();
    switch (currentState) {
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
    } else if (_state == CircuitBreakerState.closed) {
      // closed 状态下成功时清理过期的失败记录，避免端点长期处于脆弱状态
      final now = DateTime.now().millisecondsSinceEpoch;
      _failureTimestamps.removeWhere((t) => now - t > slidingWindowMs);
    }
  }

  /// 记录失败
  void recordFailure() {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_state == CircuitBreakerState.halfOpen) {
      // halfOpen 探测失败 → 回到 open
      _state = CircuitBreakerState.open;
      _openedAt = now;
      _halfOpenProbing = false;
      _hasBeenOpened = true;
      return;
    }

    // 只在 closed 状态下记录失败，open 状态下忽略
    if (_state != CircuitBreakerState.closed) return;

    // closed 状态：滑动窗口计数
    _failureTimestamps.add(now);
    // 清除窗口外的失败记录
    _failureTimestamps.removeWhere((t) => now - t > slidingWindowMs);

    if (_failureTimestamps.length >= failureThreshold) {
      _state = CircuitBreakerState.open;
      _openedAt = now;
      _halfOpenProbing = false;
      _hasBeenOpened = true;
    }
  }

  /// 强制打开断路器（用于 429 等需要立即断路的场景）
  void forceOpen() {
    _state = CircuitBreakerState.open;
    _openedAt = DateTime.now().millisecondsSinceEpoch;
    _halfOpenProbing = false;
    _hasBeenOpened = true;
  }

  /// 手动重置到 closed
  void reset() {
    _state = CircuitBreakerState.closed;
    _failureTimestamps.clear();
    _openedAt = null;
    _halfOpenProbing = false;
    _hasBeenOpened = false;
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

  /// 移除端点的断路器实例（用于端点被删除时清理内存）
  void removeBreaker(String endpointId) {
    _breakers.remove(endpointId);
  }

  void resetAll() {
    for (final breaker in _breakers.values) {
      breaker.reset();
    }
  }
}
