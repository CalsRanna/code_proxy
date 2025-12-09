import 'package:code_proxy/model/proxy_config.dart';
import 'package:code_proxy/view_model/settings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

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
          Container(
            padding: const EdgeInsets.all(24),
            child: const Text(
              '应用设置',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  '代理服务器',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('监听地址'),
                        subtitle: Text(config.listenAddress),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editListenAddress(context, config),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('监听端口'),
                        subtitle: Text(config.listenPort.toString()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editListenPort(context, config),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '健康检查',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 24),
                const Text(
                  '数据管理',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.upload_file),
                        title: const Text('导出配置'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _exportConfig(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.restore),
                        title: const Text('恢复默认'),
                        trailing: const Icon(Icons.chevron_right),
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

  void _editListenAddress(BuildContext context, ProxyConfig config) {
    final controller = TextEditingController(text: config.listenAddress);
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

  void _editListenPort(BuildContext context, ProxyConfig config) {
    final controller = TextEditingController(
      text: config.listenPort.toString(),
    );
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
