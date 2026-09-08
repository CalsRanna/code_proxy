import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/page/dashboard/dashboard_page.dart';
import 'package:code_proxy/page/endpoint/endpoint_page.dart';
import 'package:code_proxy/page/home_startup_dialogs.dart';
import 'package:code_proxy/page/request_log/request_log_page.dart';
import 'package:code_proxy/page/setting_page.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/util/window_util.dart';
import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
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

  StreamSubscription<WindowEvent>? _windowSubscription;

  final icons = [
    LucideIcons.layoutGrid,
    LucideIcons.shell,
    LucideIcons.arrowUpDown,
    LucideIcons.bolt,
  ];
  final labels = ['概览', '端点', '请求', '设置'];

  @override
  Widget build(BuildContext context) {
    var children = [_buildLeftBar(context), Expanded(child: _buildContent())];
    return Scaffold(body: Row(children: children));
  }

  @override
  void initState() {
    super.initState();
    logsViewModel.setActive(viewModel.selectedIndex.value == 2);
    _initialize();
    dashboardViewModel.initSignals();
    endpointsViewModel.initSignals();
    logsViewModel.initSignals();
    settingsViewModel.initSignals();
  }

  Future<void> _initialize() async {
    try {
      await viewModel.initSignals();
    } on ModelConfigException catch (error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showConfigErrorDialog(
          context,
          error.message,
          viewModel.modelConfigPath,
        );
      });
      return;
    } catch (error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showStartupErrorDialog(context, error);
      });
    }
    if (!mounted) return;
    _windowSubscription = WindowUtil.instance.stream.listen((event) {
      if (event == WindowEvent.shown && viewModel.selectedIndex.value == 0) {
        dashboardViewModel.initSignals();
      }
    });
  }

  void _selectTab(int index) {
    final previous = viewModel.selectedIndex.value;
    viewModel.updateSelectedIndex(index);
    logsViewModel.setActive(index == 2);
    if (previous == index) return;
    switch (index) {
      case 0:
        dashboardViewModel.initSignals();
      case 1:
        endpointsViewModel.initSignals();
      case 2:
        logsViewModel.initSignals();
      case 3:
        settingsViewModel.initSignals();
    }
  }

  @override
  void dispose() {
    _windowSubscription?.cancel();
    logsViewModel.setActive(false);
    super.dispose();
  }

  Widget _buildContent() {
    return Watch((context) {
      // IndexedStack 保活四个页面：切换 tab 只改变可见索引，不再销毁
      // 重建 widget 树。此前 switch 直接替换页面，切回概览页时两个
      // Syncfusion 图表 + 全年热力图要从零 build/layout/paint，明显卡顿。
      return IndexedStack(
        index: viewModel.selectedIndex.value,
        children: const [
          DashboardPage(),
          EndpointPage(),
          RequestLogPage(),
          SettingPage(),
        ],
      );
    });
  }

  Widget _buildIconButton(int index) {
    final isSelected = viewModel.selectedIndex.value == index;
    var shadIconButton = ShadIconButton.ghost(
      backgroundColor: isSelected ? ShadcnColors.zinc100 : null,
      icon: Icon(icons[index]),
      onPressed: () {
        _selectTab(index);
      },
    );
    var anchor = ShadAnchor(
      overlayAlignment: Alignment.centerRight,
      childAlignment: Alignment.centerLeft,
    );
    var textStyle = TextStyle(color: ShadcnColors.lightBackground);
    return ShadTooltip(
      anchor: anchor,
      builder: (context) => Text(labels[index], style: textStyle),
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
