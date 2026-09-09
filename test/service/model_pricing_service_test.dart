import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/model/normalized_token_usage.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 生成 "YYYY-MM-DD" 日期字符串。
String _dateStr(DateTime d) => d.toIso8601String().substring(0, 10);

void main() {
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

    test('应按互斥 token 分类正确计算缓存费用', () {
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

      final openAiUsage = NormalizedTokenUsage.fromOpenAi(
        totalInputTokens: 1000000,
        outputTokens: 500000,
        cacheCreationInputTokens: 200000,
        cacheReadInputTokens: 300000,
      )!;
      final openAiCost = service.calculateCost(
        model: 'MiniMax-M2.5',
        inputTokens: openAiUsage.inputTokens,
        outputTokens: openAiUsage.outputTokens,
        cacheCreationTokens: openAiUsage.cacheCreationInputTokens,
        cacheReadTokens: openAiUsage.cacheReadInputTokens,
      );
      final anthropicCost = service.calculateCost(
        model: 'MiniMax-M2.5',
        inputTokens: 500000,
        outputTokens: 500000,
        cacheCreationTokens: 200000,
        cacheReadTokens: 300000,
      );

      expect(openAiCost, closeTo(0.834, 0.000001));
      expect(anthropicCost, openAiCost);
    });

    test('应解析 GLM 和 Kimi provider 的定价数据', () {
      final service = ModelPricingService.instance;
      final recent = _dateStr(
        DateTime.now().subtract(const Duration(days: 100)),
      );
      service.parseApiResponseForTesting({
        'zhipuai': {
          'models': {
            'glm-5': {
              'cost': {'input': 1, 'output': 3.2, 'cache_read': 0.2},
              'release_date': recent,
            },
          },
        },
        'moonshotai': {
          'models': {
            'kimi-k2.5': {
              'cost': {'input': 0.6, 'output': 3, 'cache_read': 0.1},
              'release_date': recent,
            },
          },
        },
      });

      final glmPricing = service.getPricing('glm-5');
      expect(glmPricing, isNotNull);
      expect(glmPricing!.inputPrice, 1);
      expect(glmPricing.outputPrice, 3.2);
      expect(glmPricing.cacheReadPrice, 0.2);

      final kimiPricing = service.getPricing('moonshotai/kimi-k2.5');
      expect(kimiPricing, isNotNull);
      expect(kimiPricing!.modelId, 'kimi-k2.5');
      expect(kimiPricing.inputPrice, 0.6);
      expect(kimiPricing.outputPrice, 3);
      expect(kimiPricing.cacheReadPrice, 0.1);
    });

    test('应只保留近一年发布的模型并过滤更早的历史模型', () {
      final service = ModelPricingService.instance;
      final now = DateTime.now();
      service.parseApiResponseForTesting({
        'anthropic': {
          'models': {
            'claude-current': {
              'cost': {'input': 1, 'output': 2},
              'release_date': _dateStr(now.subtract(const Duration(days: 100))),
            },
            'claude-historic': {
              'cost': {'input': 1, 'output': 2},
              'release_date': _dateStr(now.subtract(const Duration(days: 500))),
            },
          },
        },
      });

      expect(service.getPricing('claude-current'), isNotNull);
      expect(service.getPricing('claude-historic'), isNull);
    });

    test('应解析 openai provider 并过滤其历史模型', () {
      final service = ModelPricingService.instance;
      final recent = _dateStr(
        DateTime.now().subtract(const Duration(days: 100)),
      );
      service.parseApiResponseForTesting({
        'openai': {
          'models': {
            'gpt-current': {
              'cost': {'input': 0.5, 'output': 1.5, 'cache_read': 0.1},
              'release_date': recent,
            },
            'gpt-4': {
              'cost': {'input': 0.3, 'output': 0.6},
              'release_date': '2023-03-14',
            },
          },
        },
      });

      final pricing = service.getPricing('gpt-current');
      expect(pricing, isNotNull);
      expect(pricing!.inputPrice, 0.5);
      expect(pricing.outputPrice, 1.5);
      expect(pricing.cacheReadPrice, 0.1);
      expect(service.getPricing('gpt-4'), isNull);
    });

    test('缺失发布日期的模型应被过滤', () {
      final service = ModelPricingService.instance;
      service.parseApiResponseForTesting({
        'openai': {
          'models': {
            'no-date-model': {
              'cost': {'input': 1, 'output': 2},
            },
          },
        },
      });

      expect(service.getPricing('no-date-model'), isNull);
    });
  });
}
