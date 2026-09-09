import 'package:code_proxy/service/proxy_server/routing/proxy_server_circuit_breaker.dart';

/// 按端点 ID 管理共享断路器的注册表。
///
/// 同一 ID 复用已注册的实例，使并发请求及不同模型共享失败计数。
class ProxyServerCircuitBreakerRegistry {
  final int failureThreshold;
  final int recoveryTimeoutMs;
  final Map<String, ProxyServerCircuitBreaker> _breakers = {};

  ProxyServerCircuitBreakerRegistry({
    this.failureThreshold = 5,
    this.recoveryTimeoutMs = 60000,
  });

  /// 获取 [endpointId] 的共享断路器，首次访问时创建。
  ProxyServerCircuitBreaker getBreaker(String endpointId) {
    return _breakers.putIfAbsent(
      endpointId,
      () => ProxyServerCircuitBreaker(
        endpointId: endpointId,
        failureThreshold: failureThreshold,
        recoveryTimeoutMs: recoveryTimeoutMs,
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
