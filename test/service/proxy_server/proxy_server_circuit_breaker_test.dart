import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  group('ProxyServiceCircuitBreaker', () {
    group('初始状态', () {
      test('新建断路器应为 closed 且可用', () {
        final breaker = createBreaker();

        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
        expect(breaker.isAvailable, isTrue);
      });
    });

    group('滑动窗口与阈值', () {
      test('失败次数达到阈值应触发 open', () {
        final breaker = createBreaker(failureThreshold: 3);

        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);

        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
        expect(breaker.isAvailable, isFalse);
      });

      test('阈值内的失败不应触发 open', () {
        final breaker = createBreaker(failureThreshold: 5);

        for (var i = 0; i < 4; i++) {
          breaker.recordFailure();
        }
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
        expect(breaker.isAvailable, isTrue);
      });

      test('滑动窗口外的失败记录应被清除', () async {
        final breaker = createBreaker(failureThreshold: 3, slidingWindowMs: 50);

        breaker.recordFailure();
        breaker.recordFailure();
        await Future.delayed(const Duration(milliseconds: 80));
        breaker.recordFailure();

        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
      });

      test('成功时应清理过期的失败记录', () async {
        final breaker = createBreaker(failureThreshold: 3, slidingWindowMs: 50);

        breaker.recordFailure();
        breaker.recordFailure();
        await Future.delayed(const Duration(milliseconds: 80));

        breaker.recordSuccess();

        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);

        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
      });
    });

    group('状态转换 open -> halfOpen -> closed', () {
      test('超时后应从 open 转为 halfOpen', () async {
        final breaker = createBreaker(
          failureThreshold: 1,
          recoveryTimeoutMs: 50,
        );

        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
        expect(breaker.isAvailable, isFalse);

        await Future.delayed(const Duration(milliseconds: 80));

        expect(breaker.isAvailable, isTrue);
        expect(
          breaker.evaluateState(),
          ProxyServerCircuitBreakerState.halfOpen,
        );
      });

      test('halfOpen 探测成功应恢复为 closed', () async {
        final breaker = createBreaker(
          failureThreshold: 1,
          recoveryTimeoutMs: 10,
        );

        breaker.recordFailure();
        await Future.delayed(const Duration(milliseconds: 30));

        expect(breaker.isAvailable, isTrue);
        breaker.recordSuccess();
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
      });

      test('halfOpen 探测失败应回到 open', () async {
        final breaker = createBreaker(
          failureThreshold: 1,
          recoveryTimeoutMs: 10,
        );

        breaker.recordFailure();
        await Future.delayed(const Duration(milliseconds: 30));

        expect(
          breaker.evaluateState(),
          ProxyServerCircuitBreakerState.halfOpen,
        );
        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
        expect(breaker.isAvailable, isFalse);
      });
    });

    group('forceOpen', () {
      test('应立即打开断路器', () {
        final breaker = createBreaker();

        breaker.forceOpen();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
        expect(breaker.isAvailable, isFalse);
      });

      test('支持自定义恢复超时', () async {
        final breaker = createBreaker(recoveryTimeoutMs: 60000);

        breaker.forceOpen(customRecoveryTimeoutMs: 30);
        expect(breaker.isAvailable, isFalse);

        await Future.delayed(const Duration(milliseconds: 60));

        expect(breaker.isAvailable, isTrue);
        expect(
          breaker.evaluateState(),
          ProxyServerCircuitBreakerState.halfOpen,
        );
      });

      test('halfOpen 探测失败后应恢复为默认超时', () async {
        final breaker = createBreaker(recoveryTimeoutMs: 60000);

        breaker.forceOpen(customRecoveryTimeoutMs: 10);
        await Future.delayed(const Duration(milliseconds: 30));

        expect(
          breaker.evaluateState(),
          ProxyServerCircuitBreakerState.halfOpen,
        );
        breaker.recordFailure();

        expect(breaker.state, ProxyServerCircuitBreakerState.open);
        await Future.delayed(const Duration(milliseconds: 30));
        expect(breaker.isAvailable, isFalse);
      });
    });

    group('手动重置', () {
      test('应立即恢复到 closed', () {
        final breaker = createBreaker(failureThreshold: 1);

        breaker.forceOpen();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
        expect(breaker.isAvailable, isFalse);

        breaker.reset();
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
        expect(breaker.isAvailable, isTrue);
      });

      test('重置后失败计数应清零', () {
        final breaker = createBreaker(failureThreshold: 3);

        breaker.recordFailure();
        breaker.recordFailure();
        breaker.reset();

        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
      });
    });

    group('open 状态下忽略失败', () {
      test('open 状态下 recordFailure 不应改变状态', () {
        final breaker = createBreaker(failureThreshold: 1);

        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);

        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
      });
    });
  });
}
