import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
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
    var listView = ListView(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
      children: [portListTile],
    );
    var pageHeader = PageHeader(
      title: '应用设置',
      subtitle: '管理代理服务器配置和应用选项',
      icon: LucideIcons.bolt,
    );
    var children = [pageHeader, Expanded(child: listView)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
