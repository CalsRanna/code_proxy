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

@RoutePage()
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeViewModel _viewModel;
  late final EndpointsViewModel _endpointsViewModel;
  late final LogsViewModel _logsViewModel;
  late final SettingsViewModel _settingsViewModel;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = GetIt.instance.get<HomeViewModel>();
    _endpointsViewModel = GetIt.instance.get<EndpointsViewModel>();
    _logsViewModel = GetIt.instance.get<LogsViewModel>();
    _settingsViewModel = GetIt.instance.get<SettingsViewModel>();

    _viewModel.init();
    _endpointsViewModel.init();
    _logsViewModel.init();
    _settingsViewModel.init();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _endpointsViewModel.dispose();
    _logsViewModel.dispose();
    _settingsViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 紧凑的侧边栏 (72px)
          Container(
            width: 72,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: ShadcnColors.border(Theme.of(context).brightness),
                  width: ShadcnSpacing.borderWidth,
                ),
              ),
            ),
            child: Column(
              spacing: ShadcnSpacing.spacing16,
              children: [
                const SizedBox(height: ShadcnSpacing.spacing16),
                ...List.generate(4, (index) {
                  return _buildNavItem(index);
                }),
                const Spacer(),
                // 主题切换器
                ThemeSwitcher(),
                const SizedBox(height: ShadcnSpacing.spacing16),
              ],
            ),
          ),
          // 主内容区
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final isSelected = _selectedIndex == index;
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
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return DashboardPage(viewModel: _viewModel);
      case 1:
        return EndpointPage(viewModel: _endpointsViewModel);
      case 2:
        return LogPage(viewModel: _logsViewModel);
      case 3:
        return SettingPage(viewModel: _settingsViewModel);
      default:
        return DashboardPage(viewModel: _viewModel);
    }
  }
}
