import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:code_proxy/page/dashboard/dashboard_page.dart';
import 'package:code_proxy/page/endpoint/endpoint_page.dart';
import 'package:code_proxy/page/mcp_server/mcp_server_page.dart';
import 'package:code_proxy/page/request_log/request_log_page.dart';
import 'package:code_proxy/page/setting_page.dart';
import 'package:code_proxy/page/skill/skill_page.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/mcp_server_view_model.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:code_proxy/view_model/skill_view_model.dart';
import 'package:code_proxy/widget/macos_window_buttons.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

@RoutePage()
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final viewModel = GetIt.instance.get<HomeViewModel>();
  final dashboardViewModel = GetIt.instance.get<DashboardViewModel>();
  final endpointsViewModel = GetIt.instance.get<EndpointViewModel>();
  final logsViewModel = GetIt.instance.get<RequestLogViewModel>();
  final settingsViewModel = GetIt.instance.get<SettingViewModel>();
  final serverViewModel = GetIt.instance.get<McpServerViewModel>();
  final skillViewModel = GetIt.instance.get<SkillViewModel>();

  final icons = [
    LucideIcons.layoutGrid,
    LucideIcons.shell,
    LucideIcons.server,
    LucideIcons.sparkles,
    LucideIcons.arrowUpDown,
    LucideIcons.bolt,
  ];
  final labels = ['控制面板', '端点', 'MCP服务器', '技能', '日志', '设置'];

  @override
  Widget build(BuildContext context) {
    var children = [_buildLeftBar(context), Expanded(child: _buildContent())];
    return Scaffold(body: Row(children: children));
  }

  @override
  void initState() {
    super.initState();
    viewModel.initSignals();
    dashboardViewModel.initSignals();
    endpointsViewModel.initSignals();
    logsViewModel.initSignals();
    serverViewModel.initSignals();
    skillViewModel.initSignals();
    settingsViewModel.initSignals();
  }

  Widget _buildContent() {
    return Watch((context) {
      return switch (viewModel.selectedIndex.value) {
        0 => DashboardPage(),
        1 => EndpointPage(),
        2 => McpServerPage(),
        3 => SkillPage(),
        4 => RequestLogPage(),
        5 => SettingPage(),
        _ => DashboardPage(),
      };
    });
  }

  Widget _buildIconButton(int index) {
    final isSelected = viewModel.selectedIndex.value == index;
    var shadIconButton = ShadIconButton.ghost(
      backgroundColor: isSelected ? ShadcnColors.zinc100 : null,
      icon: Icon(icons[index]),
      onPressed: () {
        viewModel.updateSelectedIndex(index);
      },
    );
    var anchor = ShadAnchor(
      overlayAlignment: Alignment.centerRight,
      childAlignment: Alignment.centerLeft,
    );
    return ShadTooltip(
      anchor: anchor,
      builder: (context) => Text(labels[index]),
      child: shadIconButton,
    );
  }

  Widget _buildLeftBar(BuildContext context) {
    var borderSide = BorderSide(
      color: ShadcnColors.zinc100,
      width: ShadcnSpacing.borderWidth,
    );
    var boxDecoration = BoxDecoration(border: Border(right: borderSide));
    return Watch((context) {
      var column = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: ShadcnSpacing.spacing8,
        children: List.generate(icons.length, _buildIconButton),
      );
      var children = [
        Container(width: 72, decoration: boxDecoration, child: column),
        if (Platform.isMacOS) const MacOSWindowButtons(),
      ];
      return Stack(children: children);
    });
  }
}
