import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:code_proxy/widget/page_header.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'claude_settings_tab.dart';
import 'model_pricing_settings_tab.dart';
import 'proxy_settings_tab.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final viewModel = GetIt.instance.get<SettingViewModel>();
  String selectedTab = 'proxy';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: '设置', subtitle: '管理代理配置、Claude Code 设置和应用选项'),
        const SizedBox(height: ShadcnSpacing.spacing24),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ShadcnSpacing.spacing24,
            ),
            child: ShadTabs<String>(
              value: selectedTab,
              onChanged: (value) => setState(() => selectedTab = value),
              maintainState: false,
              tabs: [
                ShadTab(
                  value: 'proxy',
                  expandContent: true,
                  content: ProxySettingsTab(viewModel: viewModel),
                  child: const Text('代理服务器'),
                ),
                ShadTab(
                  value: 'claude',
                  expandContent: true,
                  content: ClaudeSettingsTab(viewModel: viewModel),
                  child: const Text('Claude'),
                ),
                ShadTab(
                  value: 'pricing',
                  expandContent: true,
                  content: ModelPricingSettingsTab(viewModel: viewModel),
                  child: const Text('模型定价'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
