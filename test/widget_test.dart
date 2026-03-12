import 'package:code_proxy/service/proxy_server/circuit_breaker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual reset should immediately restore an open circuit breaker', () {
    final breaker = CircuitBreaker(
      endpointId: 'endpoint-1',
      failureThreshold: 1,
      recoveryTimeoutMs: 60000,
      slidingWindowMs: 60000,
    );

    breaker.forceOpen();

    expect(breaker.state, CircuitBreakerState.open);
    expect(breaker.allowRequest, isFalse);

    breaker.reset();

    expect(breaker.state, CircuitBreakerState.closed);
    expect(breaker.allowRequest, isTrue);
  });

  test('registry reset should clear the breaker for a specific endpoint', () {
    final registry = CircuitBreakerRegistry(
      failureThreshold: 1,
      recoveryTimeoutMs: 60000,
      slidingWindowMs: 60000,
    );

    final breaker = registry.getBreaker('endpoint-1');
    breaker.forceOpen();

    expect(breaker.state, CircuitBreakerState.open);

    registry.reset('endpoint-1');

    expect(breaker.state, CircuitBreakerState.closed);
    expect(breaker.allowRequest, isTrue);
  });
}
