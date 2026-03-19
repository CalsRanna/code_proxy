import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_log_handler.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response_handler.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProxyServiceCircuitBreaker', () {
    group('初始状态', () {
      test('新建断路器应为 closed 且可用', () {
        final breaker = _createBreaker();

        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
        expect(breaker.isAvailable, isTrue);
      });
    });

    group('滑动窗口与阈值', () {
      test('失败次数达到阈值应触发 open', () {
        final breaker = _createBreaker(failureThreshold: 3);

        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);

        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
        expect(breaker.isAvailable, isFalse);
      });

      test('阈值内的失败不应触发 open', () {
        final breaker = _createBreaker(failureThreshold: 5);

        for (var i = 0; i < 4; i++) {
          breaker.recordFailure();
        }
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
        expect(breaker.isAvailable, isTrue);
      });

      test('滑动窗口外的失败记录应被清除', () async {
        final breaker = _createBreaker(
          failureThreshold: 3,
          slidingWindowMs: 50,
        );

        breaker.recordFailure();
        breaker.recordFailure();
        // 等待失败记录过期
        await Future.delayed(const Duration(milliseconds: 80));
        breaker.recordFailure();

        // 窗口内只有 1 次失败，不应触发 open
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
      });

      test('成功时应清理过期的失败记录', () async {
        final breaker = _createBreaker(
          failureThreshold: 3,
          slidingWindowMs: 50,
        );

        breaker.recordFailure();
        breaker.recordFailure();
        await Future.delayed(const Duration(milliseconds: 80));

        // 成功触发清理
        breaker.recordSuccess();

        // 再添加 2 次失败（窗口内总共 2 次，不应触发 open）
        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);

        // 第 3 次窗口内失败触发 open
        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
      });
    });

    group('状态转换 open -> halfOpen -> closed', () {
      test('超时后应从 open 转为 halfOpen', () async {
        final breaker = _createBreaker(
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
        final breaker = _createBreaker(
          failureThreshold: 1,
          recoveryTimeoutMs: 10,
        );

        breaker.recordFailure();
        await Future.delayed(const Duration(milliseconds: 30));

        // 进入 halfOpen
        expect(breaker.isAvailable, isTrue);
        breaker.recordSuccess();
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
      });

      test('halfOpen 探测失败应回到 open', () async {
        final breaker = _createBreaker(
          failureThreshold: 1,
          recoveryTimeoutMs: 10,
        );

        breaker.recordFailure();
        await Future.delayed(const Duration(milliseconds: 30));

        // 进入 halfOpen
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
        final breaker = _createBreaker();

        breaker.forceOpen();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
        expect(breaker.isAvailable, isFalse);
      });

      test('支持自定义恢复超时', () async {
        final breaker = _createBreaker(recoveryTimeoutMs: 60000);

        // 使用很短的自定义超时
        breaker.forceOpen(customRecoveryTimeoutMs: 30);
        expect(breaker.isAvailable, isFalse);

        await Future.delayed(const Duration(milliseconds: 60));

        // 应该已经转为 halfOpen（用的是自定义超时而非默认 60s）
        expect(breaker.isAvailable, isTrue);
        expect(
          breaker.evaluateState(),
          ProxyServerCircuitBreakerState.halfOpen,
        );
      });

      test('halfOpen 探测失败后应恢复为默认超时', () async {
        final breaker = _createBreaker(recoveryTimeoutMs: 60000);

        breaker.forceOpen(customRecoveryTimeoutMs: 10);
        await Future.delayed(const Duration(milliseconds: 30));

        // 进入 halfOpen 后失败
        expect(
          breaker.evaluateState(),
          ProxyServerCircuitBreakerState.halfOpen,
        );
        breaker.recordFailure();

        // 回到 open，此时用默认超时（60s），短时间内不应恢复
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
        await Future.delayed(const Duration(milliseconds: 30));
        expect(breaker.isAvailable, isFalse);
      });
    });

    group('手动重置', () {
      test('应立即恢复到 closed', () {
        final breaker = _createBreaker(failureThreshold: 1);

        breaker.forceOpen();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
        expect(breaker.isAvailable, isFalse);

        breaker.reset();
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
        expect(breaker.isAvailable, isTrue);
      });

      test('重置后失败计数应清零', () {
        final breaker = _createBreaker(failureThreshold: 3);

        breaker.recordFailure();
        breaker.recordFailure();
        breaker.reset();

        // 重置后再记录 2 次失败不应触发 open
        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.closed);
      });
    });

    group('open 状态下忽略失败', () {
      test('open 状态下 recordFailure 不应改变状态', () {
        final breaker = _createBreaker(failureThreshold: 1);

        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);

        // 继续调用 recordFailure 不应报错或改变状态
        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.state, ProxyServerCircuitBreakerState.open);
      });
    });
  });

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

      // 重新获取应得到全新的实例
      final breaker2 = registry.getBreaker('ep-1');
      expect(identical(breaker1, breaker2), isFalse);
      expect(breaker2.state, ProxyServerCircuitBreakerState.closed);
    });

    test('应将配置参数传递给新建的断路器', () {
      final registry = ProxyServerCircuitBreakerRegistry(
        failureThreshold: 2,
        recoveryTimeoutMs: 30000,
        slidingWindowMs: 60000,
      );

      final breaker = registry.getBreaker('ep-1');
      expect(breaker.failureThreshold, 2);
      expect(breaker.recoveryTimeoutMs, 30000);
      expect(breaker.slidingWindowMs, 60000);
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

  group('ModelPricingService', () {
    test('应匹配带 provider 前缀的 MiniMax 模型名', () {
      final service = ModelPricingService.instance;
      service.replacePricingForTesting([
        const ModelPricingEntity(
          modelId: 'MiniMax-M2.5',
          inputPrice: 0.3,
          outputPrice: 1.2,
          cacheWritePrice: 0.375,
          cacheReadPrice: 0.03,
        ),
      ]);

      final pricing = service.getPricing('minimax/minimax-m2.5');
      expect(pricing, isNotNull);
      expect(pricing!.modelId, 'MiniMax-M2.5');
    });

    test('应按 MiniMax 定价正确计算缓存费用', () {
      final service = ModelPricingService.instance;
      service.replacePricingForTesting([
        const ModelPricingEntity(
          modelId: 'MiniMax-M2.5',
          inputPrice: 0.3,
          outputPrice: 1.2,
          cacheWritePrice: 0.375,
          cacheReadPrice: 0.03,
        ),
      ]);

      final cost = service.calculateCost(
        model: 'MiniMax-M2.5',
        inputTokens: 1000000,
        outputTokens: 500000,
        cacheCreationTokens: 200000,
        cacheReadTokens: 300000,
      );

      expect(cost, closeTo(0.834, 0.000001));
    });
  });

  group('RequestLogErrorMessage', () {
    test('errorBody 为空时应回退到 responseBody', () {
      final handler = ProxyServerLogHandler.create();
      final log = handler.buildRequestLog(
        endpoint: _createEndpoint(),
        request: const ProxyServerRequest(
          method: 'POST',
          path: '/v1/messages',
          headers: {},
          body: '{"model":"MiniMax-M2.5"}',
        ),
        response: const ProxyServerResponse(
          statusCode: 500,
          headers: {},
          responseTime: 100,
          errorBody: '   ',
          responseBody: '{"error":"upstream failure"}',
        ),
      );

      expect(log.errorMessage, '{"error":"upstream failure"}');
    });

    test('不可读响应体应生成可见摘要', () {
      final text = ResponseDecompressor.decodeForLogging(utf8.encode(''), null);
      expect(text, isEmpty);

      final binarySummary = ResponseDecompressor.decodeForLogging(const [
        0,
        159,
        146,
        150,
        255,
      ], 'br');
      expect(binarySummary, contains('non-text response body'));
      expect(binarySummary, contains('content-encoding: br'));
      expect(binarySummary, contains('base64:'));
    });
  });
}

ProxyServerCircuitBreaker _createBreaker({
  int failureThreshold = 5,
  int recoveryTimeoutMs = 60000,
  int slidingWindowMs = 120000,
}) {
  return ProxyServerCircuitBreaker(
    endpointId: 'test-endpoint',
    failureThreshold: failureThreshold,
    recoveryTimeoutMs: recoveryTimeoutMs,
    slidingWindowMs: slidingWindowMs,
  );
}

EndpointEntity _createEndpoint() {
  return const EndpointEntity(id: 'ep-1', name: 'Endpoint 1');
}
