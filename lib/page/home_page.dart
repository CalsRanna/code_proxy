import 'package:auto_route/auto_route.dart';
import 'package:code_proxy/page/dashboard_page.dart';
import 'package:code_proxy/page/endpoint/endpoint_page.dart';
import 'package:code_proxy/page/log_page.dart';
import 'package:code_proxy/page/setting_page.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
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
  final endpointsViewModel = GetIt.instance.get<EndpointsViewModel>();
  final logsViewModel = GetIt.instance.get<LogsViewModel>();
  final settingsViewModel = GetIt.instance.get<SettingsViewModel>();

  @override
  void initState() {
    super.initState();
    viewModel.initSignals();
    endpointsViewModel.initSignals();
    logsViewModel.initSignals();
    settingsViewModel.initSignals();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 紧凑的侧边栏 (72px)
          _buildLeftBar(context),
          // 主内容区
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildLeftBar(BuildContext context) {
    var borderSide = BorderSide(
      color: ShadcnColors.border(Theme.of(context).brightness),
      width: ShadcnSpacing.borderWidth,
    );
    return Watch((context) {
      return Container(
        width: 72,
        decoration: BoxDecoration(border: Border(right: borderSide)),
        child: Column(
          spacing: ShadcnSpacing.spacing16,
          children: [
            const SizedBox(height: ShadcnSpacing.spacing16),
            ...List.generate(4, (index) {
              return _buildNavItem(index);
            }),
            const Spacer(),
            ThemeSwitcher(),
            const SizedBox(height: ShadcnSpacing.spacing16),
          ],
        ),
      );
    });
  }

  Widget _buildNavItem(int index) {
    final isSelected = viewModel.selectedIndex.value == index;
    final icons = [
      LucideIcons.layoutGrid,
      LucideIcons.shell,
      LucideIcons.arrowUpDown,
      LucideIcons.bolt,
    ];
    final labels = ['主页', '端点', '日志', '设置'];

    return ShadTooltip(
      anchor: ShadAnchor(
        overlayAlignment: Alignment.centerRight,
        childAlignment: Alignment.centerLeft,
      ),
      builder: (context) => Text(labels[index]),
      child: ShadIconButton.ghost(
        icon: Icon(
          icons[index],
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onPressed: () {
          viewModel.updateSelectedIndex(index);
        },
      ),
    );
  }

  Widget _buildContent() {
    return Watch((context) {
      switch (viewModel.selectedIndex.value) {
        case 0:
          return DashboardPage(viewModel: viewModel);
        case 1:
          return EndpointPage(viewModel: endpointsViewModel);
        case 2:
          return LogPage(viewModel: logsViewModel);
        case 3:
          return SettingPage(viewModel: settingsViewModel);
        default:
          return DashboardPage(viewModel: viewModel);
      }
    });
  }
}
