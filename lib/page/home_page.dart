import 'package:auto_route/auto_route.dart';
import 'package:code_proxy/page/dashboard_page.dart';
import 'package:code_proxy/page/endpoint_page.dart';
import 'package:code_proxy/page/log_page.dart';
import 'package:code_proxy/page/setting_page.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/logs_view_model.dart';
import 'package:code_proxy/view_model/monitoring_view_model.dart';
import 'package:code_proxy/view_model/settings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

@RoutePage()
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeViewModel _viewModel;
  late final EndpointsViewModel _endpointsViewModel;
  late final MonitoringViewModel _monitoringViewModel;
  late final LogsViewModel _logsViewModel;
  late final SettingsViewModel _settingsViewModel;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = GetIt.instance.get<HomeViewModel>();
    _endpointsViewModel = GetIt.instance.get<EndpointsViewModel>();
    _monitoringViewModel = GetIt.instance.get<MonitoringViewModel>();
    _logsViewModel = GetIt.instance.get<LogsViewModel>();
    _settingsViewModel = GetIt.instance.get<SettingsViewModel>();

    _viewModel.init();
    _endpointsViewModel.init();
    _monitoringViewModel.init();
    _logsViewModel.init();
    _settingsViewModel.init();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _endpointsViewModel.dispose();
    _monitoringViewModel.dispose();
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
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                ...List.generate(4, (index) {
                  return _buildNavItem(index);
                }),
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
      Icons.home_outlined,
      Icons.dns_outlined,
      Icons.article_outlined,
      Icons.settings_outlined,
    ];
    final selectedIcons = [
      Icons.home,
      Icons.dns,
      Icons.article,
      Icons.settings,
    ];
    final labels = ['主页', '端点', '日志', '设置'];

    return Tooltip(
      message: labels[index],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedIndex = index;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.transparent,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isSelected ? selectedIcons[index] : icons[index],
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
          ),
        ),
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
