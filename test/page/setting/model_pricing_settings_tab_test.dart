import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/page/setting/model_pricing_settings_tab.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/setting_view_model_factory.dart';

class _Proxy extends Fake implements ProxyServerController {}

class _Pricing extends Fake implements ModelPricingService {
  @override
  List<ModelPricingEntity> get pricingModels => const [
    ModelPricingEntity(
      modelId: 'gpt-5.2',
      provider: 'openai',
      inputPrice: 1.25,
      outputPrice: 10,
    ),
    ModelPricingEntity(
      modelId: 'claude-sonnet-4-6',
      provider: 'anthropic',
      inputPrice: 3,
      outputPrice: 15,
    ),
    ModelPricingEntity(
      modelId: 'glm-5-turbo',
      provider: 'zai',
      inputPrice: 0.5,
      outputPrice: 1,
    ),
  ];
}

void main() {
  testWidgets('定价列表按 provider 分组，区域变体并入同组并按固定顺序展示', (tester) async {
    final viewModel = createSettingViewModel(
      proxy: _Proxy(),
      pricing: _Pricing(),
    );

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(body: ModelPricingSettingsTab(viewModel: viewModel)),
      ),
    );
    await tester.pumpAndSettle();

    // zai 的模型归入 GLM 组，不再出现兜底的「其他」分组。
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('GLM'), findsOneWidget);
    expect(find.text('其他'), findsNothing);

    final claudeY = tester.getTopLeft(find.text('Claude')).dy;
    final openAiY = tester.getTopLeft(find.text('OpenAI')).dy;
    final glmY = tester.getTopLeft(find.text('GLM')).dy;
    expect(claudeY, lessThan(openAiY));
    expect(openAiY, lessThan(glmY));
  });
}
