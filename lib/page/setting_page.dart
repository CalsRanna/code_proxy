import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/settings_view_model.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
import 'package:flutter/material.dart';
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
              if (port != null) {
                await viewModel.updateListenPort(port);
              }
              if (context.mounted) Navigator.pop(context);
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
}
