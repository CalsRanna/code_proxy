import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker_registry.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

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

    test('黑名单失败不应重试或计入断路器', () async {
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
      final session = router.startRequest();

      expect(await session.hasNext(null), isTrue);
      expect(session.currentEndpoint?.id, 'ep-1');

      expect(
        await session.hasNext(false, applyCircuitBreakerOnFailure: false),
        isFalse,
      );
      expect(session.currentEndpoint?.id, 'ep-1');
      expect(
        registry.getBreaker('ep-1').state,
        ProxyServerCircuitBreakerState.closed,
      );
      expect(
        registry.getBreaker('ep-2').state,
        ProxyServerCircuitBreakerState.closed,
      );
    });

    test('header 未达错误每端点享有 2 次透明重试预算', () {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 5,
        recoveryTimeoutMs: 1000,
      );
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 5),
        circuitBreakerRegistry: registry,
      );
      router.setEndpoints([
        const EndpointEntity(id: 'ep-1', name: 'Endpoint 1'),
        const EndpointEntity(id: 'ep-2', name: 'Endpoint 2'),
      ]);
      final session = router.startRequest();
      const ep1 = EndpointEntity(id: 'ep-1', name: 'Endpoint 1');
      final headerError = http.ClientException(
        'Connection closed before full header was received',
      );

      // 第 1、2 次:预算未尽
      expect(session.shouldTransientRetry(ep1, headerError), isTrue);
      session.recordTransientRetry(ep1);
      expect(session.shouldTransientRetry(ep1, headerError), isTrue);
      session.recordTransientRetry(ep1);
      // 第 3 次:预算耗尽
      expect(session.shouldTransientRetry(ep1, headerError), isFalse);
    });

    test('非 header 未达错误不享受透明重试', () {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 5,
        recoveryTimeoutMs: 1000,
      );
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 5),
        circuitBreakerRegistry: registry,
      );
      router.setEndpoints([
        const EndpointEntity(id: 'ep-1', name: 'Endpoint 1'),
      ]);
      final session = router.startRequest();
      const ep1 = EndpointEntity(id: 'ep-1', name: 'Endpoint 1');

      expect(
        session.shouldTransientRetry(
          ep1,
          http.ClientException('reset by peer'),
        ),
        isFalse,
      );
    });

    test('透明重试预算每端点独立', () {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 5,
        recoveryTimeoutMs: 1000,
      );
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 5),
        circuitBreakerRegistry: registry,
      );
      router.setEndpoints([
        const EndpointEntity(id: 'ep-1', name: 'Endpoint 1'),
        const EndpointEntity(id: 'ep-2', name: 'Endpoint 2'),
      ]);
      final session = router.startRequest();
      const ep1 = EndpointEntity(id: 'ep-1', name: 'Endpoint 1');
      const ep2 = EndpointEntity(id: 'ep-2', name: 'Endpoint 2');
      final headerError = http.ClientException(
        'Connection closed before full header was received',
      );

      // 耗尽 ep-1 预算
      session.recordTransientRetry(ep1);
      session.recordTransientRetry(ep1);
      expect(session.shouldTransientRetry(ep1, headerError), isFalse);
      // ep-2 预算仍满
      expect(session.shouldTransientRetry(ep2, headerError), isTrue);
    });

    test('断路器打回同端点后透明重试预算不重置(防放大)', () {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 5,
        recoveryTimeoutMs: 1000,
      );
      final router = ProxyServerRouter(
        config: const ProxyServerConfig(circuitBreakerFailureThreshold: 5),
        circuitBreakerRegistry: registry,
      );
      router.setEndpoints([
        const EndpointEntity(id: 'ep-1', name: 'Endpoint 1'),
      ]);
      final session = router.startRequest();
      const ep1 = EndpointEntity(id: 'ep-1', name: 'Endpoint 1');
      final headerError = http.ClientException(
        'Connection closed before full header was received',
      );

      session.recordTransientRetry(ep1);
      session.recordTransientRetry(ep1);
      expect(session.shouldTransientRetry(ep1, headerError), isFalse);
      // 模拟一次断路器失败重试(预算不应因此重置)
      // ignore: unawaited_futures
      session.hasNext(false);
      expect(session.shouldTransientRetry(ep1, headerError), isFalse);
    });
  });
}
