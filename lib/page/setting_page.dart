import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/settings_view_model.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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
          PageHeader(
            title: '应用设置',
            subtitle: '管理代理服务器配置和应用选项',
            icon: LucideIcons.bolt,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
              children: [
                ListTile(
                  title: const Text('监听端口'),
                  subtitle: Text(config.port.toString()),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => _editListenPort(context, config),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  void _editListenPort(BuildContext context, ProxyServerConfig config) {
    final controller = TextEditingController(text: config.port.toString());
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('监听端口'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ShadButton(
            onPressed: () async {
              final port = int.tryParse(controller.text);
              if (port == null || !viewModel.isValidPort(port)) return;

              // 检查端口是否变化
              final currentPort = viewModel.config.value.port;
              if (port == currentPort) {
                if (context.mounted) Navigator.pop(context);
                return;
              }

              // 保存配置并重启服务器
              await viewModel.updateListenPort(port);

              String? errorMessage;
              try {
                final homeViewModel = GetIt.instance.get<HomeViewModel>();
                await homeViewModel.restartProxyServer(port);
              } catch (e) {
                errorMessage = e.toString();
              }

              // 关闭输入对话框并显示结果
              if (context.mounted) {
                Navigator.pop(context);
                _showRestartNotification(
                  context,
                  port,
                  success: errorMessage == null,
                  error: errorMessage,
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
        child: ShadInput(
          controller: controller,
          keyboardType: TextInputType.number,
        ),
      ),
    );
  }

  void _showRestartNotification(
    BuildContext context,
    int newPort, {
    required bool success,
    String? error,
  }) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(success ? '代理服务器已重启' : '重启失败'),
        description: success
            ? Text(
                '监听端口已更新为 $newPort，代理服务器已自动重启。\n\n'
                '请退出 Claude Code 并重新启动以使配置生效。',
              )
            : Text(
                '代理服务器重启失败。\n\n'
                '错误信息：${error ?? "未知错误"}\n\n'
                '请尝试重启应用程序。',
              ),
        actions: [
          ShadButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
