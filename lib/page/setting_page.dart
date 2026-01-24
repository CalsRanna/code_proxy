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
    var maxRetriesTile = Watch((context) {
      return ListTile(
        title: const Text('最大重试次数'),
        subtitle: Text('每个端点最多重试 ${viewModel.maxRetries.value} 次'),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => viewModel.editMaxRetries(context),
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
    var disableDurationTile = Watch((context) {
      final minutes = viewModel.disableDuration.value ~/ 60000;
      return ListTile(
        title: const Text('端点禁用时长'),
        subtitle: Text('端点失败后禁用 $minutes 分钟'),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => viewModel.editDisableDuration(context),
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
    var launchAtStartupTile = Watch((context) {
      return ListTile(
        title: const Text('开机自启动'),
        subtitle: const Text('系统启动时自动运行应用'),
        trailing: ShadSwitch(
          value: viewModel.autoLaunch.value,
          onChanged: (value) => viewModel.toggleLaunchAtStartup(value),
        ),
        onTap: () => viewModel.toggleLaunchAtStartup(
          !viewModel.autoLaunch.value,
        ),
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
    var auditRetainDaysTile = Watch((context) {
      return ListTile(
        title: const Text('审计日志保留天数'),
        subtitle: Text('保留最近 ${viewModel.auditRetainDays.value} 天的审计日志'),
        trailing: const Icon(LucideIcons.chevronRight),
        onTap: () => viewModel.editAuditRetainDays(context),
      );
    });
    var resetTile = ListTile(
      title: const Text('恢复默认设置'),
      subtitle: const Text('清空所有数据和设置,应用将自动重启'),
      trailing: const Icon(LucideIcons.chevronRight),
      onTap: () => _showResetToDefaultDialog(context),
    );
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
    var listView = ListView(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
      children: [
        portListTile,
        maxRetriesTile,
        apiTimeoutTile,
        disableDurationTile,
        disableNonessentialTrafficTile,
        launchAtStartupTile,
        sizeTile,
        auditRetainDaysTile,
        resetTile,
        versionTile,
      ],
    );
    var pageHeader = PageHeader(title: '设置', subtitle: '管理代理服务器配置和应用选项');
    var children = [pageHeader, Expanded(child: listView)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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
