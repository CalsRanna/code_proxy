import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:code_proxy/widget/page_header.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final viewModel = GetIt.instance.get<SettingViewModel>();

  @override
  Widget build(BuildContext context) {
    var portListTile = Watch((context) {
      return ListTile(
        title: const Text('监听端口'),
        subtitle: Text(viewModel.port.value.toString()),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => viewModel.editListenPort(context),
      );
    });
    var circuitBreakerThresholdTile = Watch((context) {
      return ListTile(
        title: const Text('端点熔断阈值'),
        subtitle: Text(
          '连续失败 ${viewModel.circuitBreakerFailureThreshold.value} 次后禁用端点并故障转移',
        ),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => viewModel.editDisableDuration(context),
      );
    });
    var circuitBreakerRecoveryTile = Watch((context) {
      return ListTile(
        title: const Text('端点恢复超时'),
        subtitle: Text(
          '端点被禁用 ${viewModel.circuitBreakerRecoveryTimeout.value} 秒后尝试探测恢复',
        ),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => viewModel.editCircuitBreakerRecoveryTimeout(context),
      );
    });
    var apiTimeoutTile = Watch((context) {
      return ListTile(
        title: const Text('API 超时时间'),
        subtitle: Text('${viewModel.apiTimeout.value} 毫秒'),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => viewModel.editApiTimeout(context),
      );
    });
    var launchAtStartupTile = Watch((context) {
      return ListTile(
        title: const Text('开机自启动'),
        subtitle: const Text('系统启动时自动运行应用'),
        trailing: ShadSwitch(
          value: viewModel.autoLaunch.value,
          onChanged: (value) => viewModel.toggleLaunchAtStartup(value),
        ),
        onTap: () =>
            viewModel.toggleLaunchAtStartup(!viewModel.autoLaunch.value),
      );
    });
    var auditRetainDaysTile = Watch((context) {
      return ListTile(
        title: const Text('审计日志保留天数'),
        subtitle: Text('保留最近 ${viewModel.auditRetainDays.value} 天的审计日志'),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => viewModel.editAuditRetainDays(context),
      );
    });
    var sizeTile = Watch((context) {
      return ListTile(
        title: const Text('数据库文件大小'),
        subtitle: Text(_getFileSize(viewModel.size.value)),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => _showClearDatabaseDialog(context),
      );
    });
    var resetTile = ListTile(
      title: const Text('恢复默认设置'),
      subtitle: const Text('清空所有数据和设置,应用将自动重启'),
      trailing: const Icon(LucideIcons.chevronRight),
      onTap: () => _showResetToDefaultDialog(context),
    );
    var attributionHeaderTile = Watch((context) {
      return ListTile(
        title: const Text('归属提示头'),
        subtitle: const Text('在请求里自动加上归属提示头'),
        trailing: ShadSwitch(
          value: viewModel.attributionHeader.value,
          onChanged: (value) => viewModel.toggleAttributionHeader(value),
        ),
        onTap: () => viewModel.toggleAttributionHeader(
          !viewModel.attributionHeader.value,
        ),
      );
    });
    var disableExperimentalBetasTile = Watch((context) {
      return ListTile(
        title: const Text('禁用实验性 Beta 头'),
        subtitle: const Text('通过第三方 LLM 网关时禁用 anthropic-beta 头'),
        trailing: ShadSwitch(
          value: viewModel.disableExperimentalBetas.value,
          onChanged: (value) => viewModel.toggleDisableExperimentalBetas(value),
        ),
        onTap: () => viewModel.toggleDisableExperimentalBetas(
          !viewModel.disableExperimentalBetas.value,
        ),
      );
    });
    var disableNonessentialTrafficTile = Watch((context) {
      return ListTile(
        title: const Text('禁用非必要网络请求'),
        subtitle: const Text('减少 Claude Code 的后台网络活动'),
        trailing: ShadSwitch(
          value: viewModel.disableNonessentialTraffic.value,
          onChanged: (value) =>
              viewModel.toggleDisableNonessentialTraffic(value),
        ),
        onTap: () => viewModel.toggleDisableNonessentialTraffic(
          !viewModel.disableNonessentialTraffic.value,
        ),
      );
    });
    var defaultModelMappingTile = Watch((context) {
      return ListTile(
        title: const Text('默认模型'),
        subtitle: Text('端点没有配置模型时使用的默认模型'),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => viewModel.editDefaultModelMapping(context),
      );
    });
    var pricingTile = Watch((context) {
      final refreshing = viewModel.pricingRefreshing.value;
      return ListTile(
        title: const Text('模型定价'),
        subtitle: Text(
          '${viewModel.pricingModelCount.value} 个模型 | 更新于 ${viewModel.pricingLastUpdated.value}',
        ),
        trailing: refreshing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(LucideIcons.refreshCw),
        onTap: refreshing ? null : () => viewModel.refreshPricing(),
      );
    });
    var versionTile = Watch((context) {
      return Padding(
        padding: const EdgeInsets.only(top: ShadcnSpacing.spacing24),
        child: Center(
          child: Text(
            'Code Proxy ${viewModel.version.value}',
            style: TextStyle(fontSize: 12, color: ShadcnColors.zinc400),
          ),
        ),
      );
    });
    var pageHeader = PageHeader(title: '设置', subtitle: '管理代理服务器配置和应用选项');
    var tabs = ShadTabs<String>(
      value: 'proxy',
      maintainState: false,
      tabs: [
        ShadTab(
          value: 'proxy',
          expandContent: true,
          content: ListView(
            padding: const EdgeInsets.only(top: ShadcnSpacing.spacing8),
            children: [
              portListTile,
              circuitBreakerThresholdTile,
              circuitBreakerRecoveryTile,
              launchAtStartupTile,
              auditRetainDaysTile,
              sizeTile,
              resetTile,
              versionTile,
            ],
          ),
          child: const Text('代理服务器'),
        ),
        ShadTab(
          value: 'claude_code',
          expandContent: true,
          content: ListView(
            padding: const EdgeInsets.only(top: ShadcnSpacing.spacing8),
            children: [
              defaultModelMappingTile,
              pricingTile,
              apiTimeoutTile,
              attributionHeaderTile,
              disableExperimentalBetasTile,
              disableNonessentialTrafficTile,
              versionTile,
            ],
          ),
          child: const Text('Claude Code'),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeader,
        SizedBox(height: ShadcnSpacing.spacing24),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ShadcnSpacing.spacing24,
            ),
            child: tabs,
          ),
        ),
      ],
    );
  }

  String _getFileSize(int size) {
    var kb = size / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(2)}KB';
    var mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(2)}MB';
    var gb = mb / 1024;
    return '${gb}GB';
  }

  void _showClearDatabaseDialog(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (context) {
        return ShadDialog(
          title: const Text('清空数据库'),
          description: const Text('确定要清空数据库中的所有数据吗？此操作不可撤销。'),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ShadButton(
              onPressed: () {
                Navigator.of(context).pop();
                viewModel.clearDatabase(context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _showResetToDefaultDialog(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (context) {
        return ShadDialog(
          title: const Text('恢复默认设置'),
          description: const Text('确定要清空所有数据和设置吗？此操作无法撤销。'),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ShadButton(
              onPressed: () {
                Navigator.of(context).pop();
                viewModel.resetToDefault();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}
