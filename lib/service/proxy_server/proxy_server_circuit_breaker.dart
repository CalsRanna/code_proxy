/// 断路器状态
enum ProxyServerCircuitBreakerState { closed, open, halfOpen }

/// 断路器 - 标准连续失败计数实现
///
/// 连续失败 [failureThreshold] 次后打开断路器，成功时直接清零计数。
/// 这是 Netflix Hystrix、Resilience4j 等主流断路器的经典实现方式，
/// 不依赖滑动窗口，因此不受请求耗时长短的影响。
///
/// 线程安全说明：此类依赖 Dart 的单线程事件循环模型。
/// 所有公开方法均为同步方法，在单次事件循环迭代中完成执行，
/// 因此不存在并发竞态条件。如需移植到多线程环境，需额外加锁。
class ProxyServerCircuitBreaker {
  final String endpointId;
  final int failureThreshold;
  final int recoveryTimeoutMs;

  ProxyServerCircuitBreakerState _state =
      ProxyServerCircuitBreakerState.closed;
  int _consecutiveFailures = 0;
  int? _openedAt;

  /// 当前生效的恢复超时（可被 forceOpen 临时覆盖）
  late int _effectiveRecoveryTimeoutMs;

  ProxyServerCircuitBreaker({
    required this.endpointId,
    this.failureThreshold = 5,
    this.recoveryTimeoutMs = 60000,
  }) : _effectiveRecoveryTimeoutMs = recoveryTimeoutMs;

  /// 当前状态（纯读取，不触发状态转换）
  ProxyServerCircuitBreakerState get state => _state;

  /// 评估并更新状态（处理 open -> halfOpen 的超时转换）
  /// 需要检查状态转换时应显式调用此方法，而非通过 state getter
  ProxyServerCircuitBreakerState evaluateState() {
    if (_state == ProxyServerCircuitBreakerState.open && _openedAt != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _openedAt! >= _effectiveRecoveryTimeoutMs) {
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
      _effectiveRecoveryTimeoutMs = recoveryTimeoutMs;
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
      _effectiveRecoveryTimeoutMs = recoveryTimeoutMs;
      return;
    }

    if (_state != ProxyServerCircuitBreakerState.closed) return;

    _consecutiveFailures++;
    if (_consecutiveFailures >= failureThreshold) {
      _state = ProxyServerCircuitBreakerState.open;
      _openedAt = now;
      _effectiveRecoveryTimeoutMs = recoveryTimeoutMs;
    }
  }

  /// 强制打开断路器（用于需要立即断路的场景）
  ///
  /// [customRecoveryTimeoutMs] 自定义恢复超时，
  /// 为 null 时使用默认的 [recoveryTimeoutMs]。
  void forceOpen({int? customRecoveryTimeoutMs}) {
    _state = ProxyServerCircuitBreakerState.open;
    _openedAt = DateTime.now().millisecondsSinceEpoch;
    _effectiveRecoveryTimeoutMs = customRecoveryTimeoutMs ?? recoveryTimeoutMs;
  }

  /// 手动重置到 closed
  void reset() {
    _state = ProxyServerCircuitBreakerState.closed;
    _consecutiveFailures = 0;
    _openedAt = null;
    _effectiveRecoveryTimeoutMs = recoveryTimeoutMs;
  }
}
