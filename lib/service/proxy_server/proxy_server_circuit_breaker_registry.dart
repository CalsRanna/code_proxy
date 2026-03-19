import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker.dart';

/// 断路器注册表 - 管理所有端点的断路器
class ProxyServerCircuitBreakerRegistry {
  final int failureThreshold;
  final int recoveryTimeoutMs;
  final int slidingWindowMs;
  final Map<String, ProxyServerCircuitBreaker> _breakers = {};

  ProxyServerCircuitBreakerRegistry({
    this.failureThreshold = 5,
    this.recoveryTimeoutMs = 60000,
    this.slidingWindowMs = 120000,
  });

  ProxyServerCircuitBreaker getBreaker(String endpointId) {
    return _breakers.putIfAbsent(
      endpointId,
      () => ProxyServerCircuitBreaker(
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

  /// 获取当前仍处于 open 状态的端点 ID
  Set<String> getOpenEndpointIds(Iterable<String> endpointIds) {
    final openEndpointIds = <String>{};

    for (final endpointId in endpointIds) {
      final breaker = _breakers[endpointId];
      if (breaker == null) continue;

      if (breaker.evaluateState() == ProxyServerCircuitBreakerState.open) {
        openEndpointIds.add(endpointId);
      }
    }

    return openEndpointIds;
  }
}
