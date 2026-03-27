import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker_registry.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProxyServerRouter', () {
    test('失败响应应统一走断路器重试与故障转移', () async {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 2,
        recoveryTimeoutMs: 1000,
      );
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 2),
        circuitBreakerRegistry: registry,
      );
      router.setEndpoints([
        const EndpointEntity(id: 'ep-1', name: 'Endpoint 1'),
        const EndpointEntity(id: 'ep-2', name: 'Endpoint 2'),
      ]);
      final session = router.startRequest();

      expect(await session.hasNext(null), isTrue);
      expect(session.currentEndpoint?.id, 'ep-1');

      expect(await session.hasNext(false), isTrue);
      expect(session.currentEndpoint?.id, 'ep-1');

      expect(await session.hasNext(false), isTrue);
      expect(session.currentEndpoint?.id, 'ep-2');
      expect(
        registry.getBreaker('ep-1').state,
        ProxyServerCircuitBreakerState.open,
      );
    });

    test('open 端点在恢复超时后应以 halfOpen 重新参与选择', () async {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 1,
        recoveryTimeoutMs: 10,
      );
      final restoredEndpointIds = <String>[];
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 1),
        circuitBreakerRegistry: registry,
        onEndpointRestored: (endpoint) => restoredEndpointIds.add(endpoint.id),
      );
      router.setEndpoints([
        const EndpointEntity(id: 'ep-1', name: 'Endpoint 1'),
      ]);
      final firstSession = router.startRequest();

      expect(await firstSession.hasNext(null), isTrue);
      expect(await firstSession.hasNext(false), isFalse);
      expect(
        registry.getBreaker('ep-1').state,
        ProxyServerCircuitBreakerState.open,
      );

      await Future.delayed(const Duration(milliseconds: 30));
      final recoverySession = router.startRequest();

      expect(await recoverySession.hasNext(null), isTrue);
      expect(
        registry.getBreaker('ep-1').evaluateState(),
        ProxyServerCircuitBreakerState.halfOpen,
      );

      expect(await recoverySession.hasNext(true), isFalse);
      expect(restoredEndpointIds, ['ep-1']);
      expect(
        registry.getBreaker('ep-1').state,
        ProxyServerCircuitBreakerState.closed,
      );
    });

    test('并发请求失败时不应把断路器错误应用到其他端点', () async {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 1,
        recoveryTimeoutMs: 1000,
      );
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 1),
        circuitBreakerRegistry: registry,
      );
      router.setEndpoints([
        const EndpointEntity(id: 'ep-1', name: 'Endpoint 1'),
        const EndpointEntity(id: 'ep-2', name: 'Endpoint 2'),
      ]);

      final sessionA = router.startRequest();
      final sessionB = router.startRequest();

      expect(await sessionA.hasNext(null), isTrue);
      expect(sessionA.currentEndpoint?.id, 'ep-1');
      expect(await sessionB.hasNext(null), isTrue);
      expect(sessionB.currentEndpoint?.id, 'ep-1');

      expect(await sessionA.hasNext(false), isTrue);
      expect(sessionA.currentEndpoint?.id, 'ep-2');
      expect(
        registry.getBreaker('ep-1').state,
        ProxyServerCircuitBreakerState.open,
      );
      expect(
        registry.getBreaker('ep-2').state,
        ProxyServerCircuitBreakerState.closed,
      );

      expect(await sessionB.hasNext(false), isTrue);
      expect(sessionB.currentEndpoint?.id, 'ep-2');
      expect(
        registry.getBreaker('ep-1').state,
        ProxyServerCircuitBreakerState.open,
      );
      expect(
        registry.getBreaker('ep-2').state,
        ProxyServerCircuitBreakerState.closed,
      );
    });
  });
}
