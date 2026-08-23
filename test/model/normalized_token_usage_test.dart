import 'package:code_proxy/model/normalized_token_usage.dart';
import 'package:code_proxy/model/request_log_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NormalizedTokenUsage', () {
    test('将 OpenAI 总输入拆成互斥的未缓存、缓存创建和缓存读取', () {
      final usage = NormalizedTokenUsage.fromOpenAi(
        totalInputTokens: 100,
        outputTokens: 10,
        cacheCreationInputTokens: 20,
        cacheReadInputTokens: 60,
      );

      expect(usage, isNotNull);
      expect(usage!.inputTokens, 20);
      expect(usage.cacheCreationInputTokens, 20);
      expect(usage.cacheReadInputTokens, 60);
      expect(usage.outputTokens, 10);
      expect(usage.totalInputTokens, 100);
      expect(usage.totalTokens, 110);
    });

    test('缓存分类超过总输入时会截断且不会产生负 token', () {
      final usage = NormalizedTokenUsage.fromOpenAi(
        totalInputTokens: 10,
        outputTokens: -2,
        cacheCreationInputTokens: 7,
        cacheReadInputTokens: 8,
      )!;

      expect(usage.inputTokens, 0);
      expect(usage.cacheReadInputTokens, 8);
      expect(usage.cacheCreationInputTokens, 2);
      expect(usage.outputTokens, 0);
      expect(usage.totalInputTokens, 10);
    });

    test('完全缺失 usage 时返回 null', () {
      expect(
        NormalizedTokenUsage.fromOpenAi(
          totalInputTokens: null,
          outputTokens: null,
        ),
        isNull,
      );
    });
  });

  test('RequestLog 总量只在展示层汇总一次缓存分类', () {
    const log = RequestLogEntity(
      id: 'log-1',
      timestamp: 1,
      endpointName: 'endpoint',
      path: '/v1/messages',
      statusCode: 200,
      inputTokens: 20,
      outputTokens: 10,
      cacheCreationInputTokens: 20,
      cacheReadInputTokens: 60,
    );

    expect(log.totalInputTokens, 100);
    expect(log.totalTokens, 110);
  });
}
