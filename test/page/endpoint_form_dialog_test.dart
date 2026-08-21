import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/page/endpoint/endpoint_form_dialog.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('端点表单渲染认证方式区块（标题 + 三个单选选项 + 说明）', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: EndpointFormDialog(
            endpoint: null,
            viewModel: EndpointViewModel(),
          ),
        ),
      ),
    );

    // 字段标签（扁平布局，无分区标题）
    for (final label in [
      '名称',
      '备注',
      'API Key',
      'Base URL',
      'Haiku 模型',
      'Sonnet 模型',
      'Opus 模型',
      '认证方式',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    for (final sectionTitle in ['基本信息', '连接配置', '模型映射']) {
      expect(find.text(sectionTitle), findsNothing);
    }
    // 认证方式选项横向排列
    // 注意：shadcn 内部构造 ShadRadioGroup 时泛型推断为 dynamic，
    // 需通过 form field 的 descendant 查找
    final radioGroup = tester.widget<ShadRadioGroup>(
      find.descendant(
        of: find.byType(ShadRadioGroupFormField<EndpointAuthMode>),
        matching: find.byType(ShadRadioGroup),
      ),
    );
    expect(radioGroup.axis, Axis.horizontal);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('x-api-key'), findsOneWidget);
    expect(find.text('Bearer'), findsOneWidget);

    // 所有标签（字段标签 + 认证方式 + radio 选项）统一遵循 shadcn 规范
    // label 样式：由 ShadInputDecorator / ShadRadio 通过 DefaultTextStyle
    // 渲染，均为 muted 字号 + w500 + foreground 色
    final labelContext = tester.element(find.text('API Key'));
    final shadTheme = ShadTheme.of(labelContext);
    final expectedStyle = shadTheme.textTheme.muted.copyWith(
      fontWeight: FontWeight.w500,
      color: shadTheme.colorScheme.foreground,
    );

    final allLabelTexts = [
      '名称',
      '备注',
      'API Key',
      'Base URL',
      'Haiku 模型',
      'Sonnet 模型',
      'Opus 模型',
      '认证方式',
      'Default',
      'x-api-key',
      'Bearer',
    ];
    for (final text in allLabelTexts) {
      final inherited = DefaultTextStyle.of(tester.element(find.text(text)));
      expect(inherited.style.fontWeight, expectedStyle.fontWeight);
      expect(inherited.style.color, expectedStyle.color);
      expect(inherited.style.fontSize, expectedStyle.fontSize);
    }
  });

  testWidgets('编辑已有端点时认证方式初始化为端点配置值', (tester) async {
    // 编辑模式下默认选中「强制 x-api-key」
    final viewModel = EndpointViewModel();

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: EndpointFormDialog(
            endpoint: createEndpoint(
              authMode: EndpointAuthMode.xApiKey,
            ),
            viewModel: viewModel,
          ),
        ),
      ),
    );

    // 初始值回显断言（shadcn 内部泛型推断为 dynamic，直接查 form field）
    final radioGroupFormField =
        tester.widget<ShadRadioGroupFormField<EndpointAuthMode>>(
      find.byType(ShadRadioGroupFormField<EndpointAuthMode>),
    );
    expect(radioGroupFormField.initialValue, EndpointAuthMode.xApiKey);
  });

  testWidgets('端点表单渲染 API 格式区块，默认选中 Anthropic', (tester) async {
    final viewModel = EndpointViewModel();

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: EndpointFormDialog(endpoint: null, viewModel: viewModel),
        ),
      ),
    );

    expect(find.text('API 格式'), findsOneWidget);
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('Chat Completions'), findsOneWidget);
    expect(find.text('Responses'), findsOneWidget);

    final formatField = tester.widget<ShadRadioGroupFormField<EndpointApiFormat>>(
      find.byType(ShadRadioGroupFormField<EndpointApiFormat>),
    );
    expect(formatField.initialValue, EndpointApiFormat.anthropic);
  });

  testWidgets('编辑已有端点时 API 格式初始化为端点配置值', (tester) async {
    final viewModel = EndpointViewModel();

    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: EndpointFormDialog(
            endpoint: createEndpoint(
              apiFormat: EndpointApiFormat.openai,
            ),
            viewModel: viewModel,
          ),
        ),
      ),
    );

    final formatField = tester.widget<ShadRadioGroupFormField<EndpointApiFormat>>(
      find.byType(ShadRadioGroupFormField<EndpointApiFormat>),
    );
    expect(formatField.initialValue, EndpointApiFormat.openai);
  });
}
