import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('应解析 GLM 和 Kimi provider 的定价数据', () {
      final service = ModelPricingService.instance;
      service.parseApiResponseForTesting({
        'zhipuai': {
          'models': {
            'glm-5': {
              'cost': {'input': 1, 'output': 3.2, 'cache_read': 0.2},
            },
          },
        },
        'moonshotai': {
          'models': {
            'kimi-k2.5': {
              'cost': {'input': 0.6, 'output': 3, 'cache_read': 0.1},
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
  });
}
