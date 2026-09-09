import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/page/setting/model_pricing_detail_dialog.dart';
import 'package:code_proxy/page/setting/setting_page.dart';
import 'package:code_proxy/page/setting/setting_value_dialog.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/memory_preferences.dart';
import '../../support/setting_view_model_factory.dart';

class _Proxy extends Fake implements ProxyServerController {}

class _Pricing extends Fake implements ModelPricingService {
  @override
  List<ModelPricingEntity> get pricingModels => const [
    ModelPricingEntity(
      modelId: 'claude-test',
      inputPrice: 3,
      outputPrice: 15,
      cacheWritePrice: 3.75,
      cacheReadPrice: 0.3,
    ),
  ];
}

void main() {
  testWidgets('标签切换共用设置状态，编辑保存和定价详情保持可用', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = MemoryPreferences();
    final viewModel = createSettingViewModel(
      proxy: _Proxy(),
      preferences: preferences,
      pricing: _Pricing(),
    );
    GetIt.instance.registerSingleton<SettingViewModel>(viewModel);
    addTearDown(GetIt.instance.reset);

    await tester.pumpWidget(const ShadApp(home: Scaffold(body: SettingPage())));
    await tester.pumpAndSettle();
    expect(find.text('端点熔断阈值'), findsOneWidget);

    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('API 超时时间'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingValueDialog), findsOneWidget);
    await tester.enterText(find.byType(EditableText), '120000');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(preferences.timeout, 120000);
    expect(find.text('120,000 毫秒'), findsOneWidget);
    expect(find.text('API 超时时间已更新，重启代理服务器后生效。'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('模型定价'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('claude-test'));
    await tester.pumpAndSettle();
    expect(find.byType(ModelPricingDetailDialog), findsOneWidget);
    expect(find.text('输入价格'), findsOneWidget);
    expect(find.text(r'$3 / MTok'), findsOneWidget);
    expect(find.text(r'$15 / MTok'), findsOneWidget);
    expect(find.text(r'$3.75 / MTok'), findsOneWidget);
    expect(find.text(r'$0.3 / MTok'), findsOneWidget);
    Navigator.of(tester.element(find.byType(ModelPricingDetailDialog))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('代理服务器'));
    await tester.pumpAndSettle();
    expect(find.text('端点熔断阈值'), findsOneWidget);
    await tester.tap(find.text('Claude'));
    await tester.pumpAndSettle();
    expect(find.text('120,000 毫秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
