import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'setting_dialogs.dart';
import 'setting_version.dart';

class ClaudeSettingsTab extends StatelessWidget {
  final SettingViewModel viewModel;

  const ClaudeSettingsTab({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final dialogs = SettingDialogs(viewModel);
    var defaultModelMappingTile = Watch((context) {
      return ListTile(
        title: const Text('默认模型'),
        subtitle: Text('端点没有配置模型时使用的默认模型'),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => dialogs.editDefaultModelMapping(context),
      );
    });
    var apiTimeoutTile = Watch((context) {
      return ListTile(
        title: const Text('API 超时时间'),
        subtitle: Text('${viewModel.apiTimeout.value} 毫秒'),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => dialogs.editApiTimeout(context),
      );
    });
    var clientAttributionTile = Watch((context) {
      return ListTile(
        title: const Text('客户端归属标识'),
        subtitle: const Text(
          '在系统提示中附带客户端版本信息，关闭可提升第三方 LLM 网关的 prompt caching 命中率',
        ),
        trailing: ShadSwitch(
          value: viewModel.clientAttribution.value,
          onChanged: (value) => viewModel.toggleClientAttribution(value),
        ),
        onTap: () => viewModel.toggleClientAttribution(
          !viewModel.clientAttribution.value,
        ),
      );
    });
    var experimentalApiFeaturesTile = Watch((context) {
      return ListTile(
        title: const Text('实验性 API 特性'),
        subtitle: const Text(
          '在 API 请求中附带 anthropic-beta 请求头及实验性工具字段，第三方网关可能不兼容',
        ),
        trailing: ShadSwitch(
          value: viewModel.experimentalApiFeatures.value,
          onChanged: (value) => viewModel.toggleExperimentalApiFeatures(value),
        ),
        onTap: () => viewModel.toggleExperimentalApiFeatures(
          !viewModel.experimentalApiFeatures.value,
        ),
      );
    });
    var backgroundDataCollectionTile = Watch((context) {
      return ListTile(
        title: const Text('后台数据收集'),
        subtitle: const Text('允许反馈收集、错误上报及遥测数据。'),
        trailing: ShadSwitch(
          value: viewModel.backgroundDataCollection.value,
          onChanged: (value) => viewModel.toggleBackgroundDataCollection(value),
        ),
        onTap: () => viewModel.toggleBackgroundDataCollection(
          !viewModel.backgroundDataCollection.value,
        ),
      );
    });
    var enableAgentTeamsTile = Watch((context) {
      return ListTile(
        title: const Text('多代理协作'),
        subtitle: const Text('允许 Claude Code 以团队模式创建多个代理协作（实验性功能）'),
        trailing: ShadSwitch(
          value: viewModel.enableAgentTeams.value,
          onChanged: (value) => viewModel.toggleEnableAgentTeams(value),
        ),
        onTap: () =>
            viewModel.toggleEnableAgentTeams(!viewModel.enableAgentTeams.value),
      );
    });
    var aiCommitAttributionTile = Watch((context) {
      return ListTile(
        title: const Text('AI 提交署名'),
        subtitle: const Text('git 提交和 PR 描述中自动添加 Claude Code 的 AI 归属信息'),
        trailing: ShadSwitch(
          value: viewModel.aiCommitAttribution.value,
          onChanged: (value) => viewModel.toggleAiCommitAttribution(value),
        ),
        onTap: () => viewModel.toggleAiCommitAttribution(
          !viewModel.aiCommitAttribution.value,
        ),
      );
    });
    return ListView(
      padding: const EdgeInsets.only(top: ShadcnSpacing.spacing8),
      children: [
        defaultModelMappingTile,
        apiTimeoutTile,
        clientAttributionTile,
        experimentalApiFeaturesTile,
        backgroundDataCollectionTile,
        enableAgentTeamsTile,
        aiCommitAttributionTile,
        SettingVersion(viewModel: viewModel),
      ],
    );
  }
}
