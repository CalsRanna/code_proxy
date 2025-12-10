import 'package:code_proxy/model/proxy_server_config_entity.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/settings_view_model.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SettingPage extends StatelessWidget {
  final SettingsViewModel viewModel;

  const SettingPage({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final config = viewModel.config.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '应用设置',
            subtitle: '管理代理服务器配置和应用选项',
            icon: LucideIcons.settings,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
              children: [
                const SectionHeader(title: '代理服务器', icon: LucideIcons.router),
                const SizedBox(height: ShadcnSpacing.spacing12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('监听地址'),
                        subtitle: Text(config.address),
                        trailing: const Icon(LucideIcons.chevronRight),
                        onTap: () => _editListenAddress(context, config),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('监听端口'),
                        subtitle: Text(config.port.toString()),
                        trailing: const Icon(LucideIcons.chevronRight),
                        onTap: () => _editListenPort(context, config),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ShadcnSpacing.spacing24),
                const SectionHeader(
                  title: '健康检查',
                  icon: LucideIcons.heartPulse,
                ),
                const SizedBox(height: ShadcnSpacing.spacing12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('检查间隔'),
                        subtitle: Text('${config.healthCheckInterval} 秒'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('连续失败阈值'),
                        subtitle: Text(
                          '${config.consecutiveFailureThreshold} 次',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ShadcnSpacing.spacing24),
                const SectionHeader(title: '数据管理', icon: LucideIcons.database),
                const SizedBox(height: ShadcnSpacing.spacing12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(LucideIcons.upload),
                        title: const Text('导出配置'),
                        trailing: const Icon(LucideIcons.chevronRight),
                        onTap: () => _exportConfig(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(LucideIcons.rotateCcw),
                        title: const Text('恢复默认'),
                        trailing: const Icon(LucideIcons.chevronRight),
                        onTap: () => _resetDefaults(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  void _editListenAddress(
    BuildContext context,
    ProxyServerConfigEntity config,
  ) {
    final controller = TextEditingController(text: config.address);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('监听地址'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '地址',
            hintText: '127.0.0.1 或 0.0.0.0',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await viewModel.updateListenAddress(controller.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _editListenPort(BuildContext context, ProxyServerConfigEntity config) {
    final controller = TextEditingController(text: config.port.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('监听端口'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '端口',
            hintText: '1-65535',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final port = int.tryParse(controller.text);
              if (port != null) {
                await viewModel.updateListenPort(port);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _exportConfig(BuildContext context) async {
    try {
      final path = await viewModel.exportConfig();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已导出至: $path')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  void _resetDefaults(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认恢复'),
        content: const Text('确定要恢复默认设置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await viewModel.resetToDefaults();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }
}
