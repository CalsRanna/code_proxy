import 'package:auto_route/auto_route.dart';
import 'package:code_proxy/page/dashboard/dashboard_page.dart';
import 'package:code_proxy/page/endpoint/endpoint_page.dart';
import 'package:code_proxy/page/log_page.dart';
import 'package:code_proxy/page/setting_page.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/logs_view_model.dart';
import 'package:code_proxy/view_model/settings_view_model.dart';
import 'package:code_proxy/widgets/theme_switcher.dart';
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
  final endpointsViewModel = GetIt.instance.get<EndpointsViewModel>();
  final logsViewModel = GetIt.instance.get<LogsViewModel>();
  final settingsViewModel = GetIt.instance.get<SettingsViewModel>();

  final icons = [
    LucideIcons.layoutGrid,
    LucideIcons.shell,
    LucideIcons.arrowUpDown,
    LucideIcons.bolt,
  ];
  final labels = ['主页', '端点', '日志', '设置'];

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
    settingsViewModel.initSignals();
  }

  Widget _buildContent() {
    return Watch((context) {
      return switch (viewModel.selectedIndex.value) {
        0 => DashboardPage(),
        1 => EndpointPage(viewModel: endpointsViewModel),
        2 => LogPage(viewModel: logsViewModel),
        3 => SettingPage(viewModel: settingsViewModel),
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
      color: ShadcnColors.border(Theme.of(context).brightness),
      width: ShadcnSpacing.borderWidth,
    );
    var boxDecoration = BoxDecoration(border: Border(right: borderSide));
    return Watch((context) {
      var children = [
        const SizedBox(height: ShadcnSpacing.spacing16),
        ...List.generate(icons.length, (index) {
          return _buildIconButton(index);
        }),
        const Spacer(),
        ThemeSwitcher(),
        const SizedBox(height: ShadcnSpacing.spacing16),
      ];
      var column = Column(spacing: ShadcnSpacing.spacing16, children: children);
      return Container(width: 72, decoration: boxDecoration, child: column);
    });
  }
}
