import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CircuitBreakerRegistry', () {
    test('应按需创建断路器实例', () {
      final registry = ProxyServerCircuitBreakerRegistry();

      final breaker1 = registry.getBreaker('ep-1');
      final breaker2 = registry.getBreaker('ep-1');
      expect(identical(breaker1, breaker2), isTrue);
    });

    test('不同端点应有独立的断路器', () {
      final registry = ProxyServerCircuitBreakerRegistry(failureThreshold: 1);

      final breaker1 = registry.getBreaker('ep-1');
      final breaker2 = registry.getBreaker('ep-2');

      breaker1.forceOpen();
      expect(breaker1.isAvailable, isFalse);
      expect(breaker2.isAvailable, isTrue);
    });

    test('reset 应重置指定端点的断路器', () {
      final registry = ProxyServerCircuitBreakerRegistry();

      final breaker = registry.getBreaker('ep-1');
      breaker.forceOpen();
      expect(breaker.state, ProxyServerCircuitBreakerState.open);

      registry.reset('ep-1');
      expect(breaker.state, ProxyServerCircuitBreakerState.closed);
      expect(breaker.isAvailable, isTrue);
    });

    test('reset 不存在的端点不应报错', () {
      final registry = ProxyServerCircuitBreakerRegistry();
      registry.reset('non-existent');
    });

    test('resetAll 应重置所有断路器', () {
      final registry = ProxyServerCircuitBreakerRegistry();

      final breaker1 = registry.getBreaker('ep-1');
      final breaker2 = registry.getBreaker('ep-2');
      breaker1.forceOpen();
      breaker2.forceOpen();

      registry.resetAll();
      expect(breaker1.isAvailable, isTrue);
      expect(breaker2.isAvailable, isTrue);
    });

    test('removeBreaker 应释放实例', () {
      final registry = ProxyServerCircuitBreakerRegistry();

      final breaker1 = registry.getBreaker('ep-1');
      breaker1.forceOpen();

      registry.removeBreaker('ep-1');

      final breaker2 = registry.getBreaker('ep-1');
      expect(identical(breaker1, breaker2), isFalse);
      expect(breaker2.state, ProxyServerCircuitBreakerState.closed);
    });

    test('应将配置参数传递给新建的断路器', () {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 2,
        recoveryTimeoutMs: 30000,
      );

      final breaker = registry.getBreaker('ep-1');
      expect(breaker.failureThreshold, 2);
      expect(breaker.recoveryTimeoutMs, 30000);
    });

    test('恢复超时后不应继续返回 open 端点', () async {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 1,
        recoveryTimeoutMs: 10,
      );

      final breaker = registry.getBreaker('ep-1');
      breaker.recordFailure();
      expect(registry.getOpenEndpointIds(['ep-1']), {'ep-1'});

      await Future.delayed(const Duration(milliseconds: 30));

      expect(registry.getOpenEndpointIds(['ep-1']), isEmpty);
      expect(breaker.state, ProxyServerCircuitBreakerState.halfOpen);
    });
  });
}
