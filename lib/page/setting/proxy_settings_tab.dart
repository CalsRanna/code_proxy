import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/util/format_number_util.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'setting_dialogs.dart';
import 'setting_version.dart';

class ProxySettingsTab extends StatelessWidget {
  final SettingViewModel viewModel;

  const ProxySettingsTab({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final dialogs = SettingDialogs(viewModel);
    var circuitBreakerThresholdTile = Watch((context) {
      return ListTile(
        title: const Text('端点熔断阈值'),
        subtitle: Text(
          '连续失败 ${viewModel.circuitBreakerFailureThreshold.value} 次后禁用端点并故障转移',
        ),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => dialogs.editCircuitBreakerFailureThreshold(context),
      );
    });
    var circuitBreakerRecoveryTile = Watch((context) {
      return ListTile(
        title: const Text('端点恢复超时'),
        subtitle: Text(
          '端点被禁用 ${formatWithThousandsSeparator(viewModel.circuitBreakerRecoveryTimeout.value)} 秒后尝试探测恢复',
        ),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => dialogs.editCircuitBreakerRecoveryTimeout(context),
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
    var notificationEnabledTile = Watch((context) {
      return ListTile(
        title: const Text('启用通知'),
        subtitle: const Text('端点故障转移或恢复时发送系统通知'),
        trailing: ShadSwitch(
          value: viewModel.notificationEnabled.value,
          onChanged: (value) => viewModel.toggleNotificationEnabled(value),
        ),
        onTap: () => viewModel.toggleNotificationEnabled(
          !viewModel.notificationEnabled.value,
        ),
      );
    });
    var auditRetainDaysTile = Watch((context) {
      return ListTile(
        title: const Text('审计日志保留天数'),
        subtitle: Text('保留最近 ${viewModel.auditRetainDays.value} 天的审计日志'),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => dialogs.editAuditRetainDays(context),
      );
    });
    var sizeTile = Watch((context) {
      return ListTile(
        title: const Text('数据库文件大小'),
        subtitle: Text(_getFileSize(viewModel.size.value)),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => dialogs.confirmClearDatabase(context),
      );
    });
    var resetTile = ListTile(
      title: const Text('恢复默认设置'),
      subtitle: const Text('清空所有数据和设置,应用将自动重启'),
      trailing: const Icon(LucideIcons.chevronRight),
      onTap: () => dialogs.confirmResetToDefault(context),
    );
    return ListView(
      padding: const EdgeInsets.only(top: ShadcnSpacing.spacing8),
      children: [
        circuitBreakerThresholdTile,
        circuitBreakerRecoveryTile,
        launchAtStartupTile,
        notificationEnabledTile,
        auditRetainDaysTile,
        sizeTile,
        resetTile,
        SettingVersion(viewModel: viewModel),
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
}
