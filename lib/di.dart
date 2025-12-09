import 'package:code_proxy/services/claude_code_config_manager.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:code_proxy/services/database_service.dart';
import 'package:code_proxy/services/proxy_server.dart';
import 'package:code_proxy/services/stats_collector.dart';
import 'package:code_proxy/services/theme_service.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/logs_view_model.dart';
import 'package:code_proxy/view_model/monitoring_view_model.dart';
import 'package:code_proxy/view_model/settings_view_model.dart';
import 'package:get_it/get_it.dart';

/// 全局服务定位器实例
final getIt = GetIt.instance;

/// 初始化依赖注入
/// 必须在应用启动时调用
Future<void> setupServiceLocator() async {
  // =============================
  // 服务层（Services）
  // =============================

  // 注册 DatabaseService（单例）
  getIt.registerLazySingleton<DatabaseService>(() => DatabaseService());

  // 注册 ThemeService（单例，独立服务）
  getIt.registerLazySingleton<ThemeService>(() => ThemeService());

  // 注册 ConfigManager（单例，依赖 DatabaseService）
  getIt.registerLazySingleton<ConfigManager>(
    () => ConfigManager(getIt<DatabaseService>()),
  );

  // 初始化 ConfigManager（会自动初始化 DatabaseService）
  await getIt<ConfigManager>().init();

  // 初始化全局 endpoints signal（从数据库加载）
  final endpoints = await getIt<ConfigManager>().loadEndpoints();
  EndpointsViewModel.endpoints.value = endpoints;

  // 初始化全局主题 signal（从 SharedPreferences 加载）
  await SettingsViewModel.initGlobalTheme(getIt<ThemeService>());

  // 加载初始配置
  final config = await getIt<ConfigManager>().loadProxyConfig();

  // 注册 StatsCollector（单例）
  getIt.registerLazySingleton<StatsCollector>(
    () => StatsCollector(
      maxLogEntries: config.maxLogEntries,
      databaseService: getIt<DatabaseService>(),
    ),
  );

  // 注册 ClaudeCodeConfigManager（单例）
  getIt.registerLazySingleton<ClaudeCodeConfigManager>(
    () => ClaudeCodeConfigManager(),
  );

  // 注册 ProxyServer（单例）
  getIt.registerLazySingleton<ProxyServer>(
    () => ProxyServer(
      config: config,
      // 从 EndpointsViewModel 的 static signal 获取端点列表
      getEndpoints: () => EndpointsViewModel.endpoints.value,
      // 更新端点 enabled 状态的回调
      updateEndpointEnabled: (endpointId, enabled) async {
        final configManager = getIt<ConfigManager>();
        final endpoint = EndpointsViewModel.endpoints.value
            .firstWhere((e) => e.id == endpointId);
        final updatedEndpoint = endpoint.copyWith(enabled: enabled);
        await configManager.saveEndpoint(updatedEndpoint);
        // 重新加载端点到 signal
        final updatedEndpoints = await configManager.loadEndpoints();
        EndpointsViewModel.endpoints.value = updatedEndpoints;
      },
      statsCollector: getIt<StatsCollector>(),
      claudeCodeConfigManager: getIt<ClaudeCodeConfigManager>(),
    ),
  );

  // =============================
  // ViewModel 层
  // =============================

  // 注册 HomeViewModel（工厂模式，每次获取创建新实例）
  getIt.registerFactory<HomeViewModel>(
    () => HomeViewModel(
      proxyServer: getIt<ProxyServer>(),
      statsCollector: getIt<StatsCollector>(),
      configManager: getIt<ConfigManager>(),
      claudeCodeConfigManager: getIt<ClaudeCodeConfigManager>(),
      databaseService: getIt<DatabaseService>(),
    ),
  );

  // 注册 EndpointsViewModel（工厂模式）
  getIt.registerFactory<EndpointsViewModel>(
    () => EndpointsViewModel(configManager: getIt<ConfigManager>()),
  );

  // 注册 MonitoringViewModel（工厂模式）
  getIt.registerFactory<MonitoringViewModel>(
    () => MonitoringViewModel(
      statsCollector: getIt<StatsCollector>(),
    ),
  );

  // 注册 LogsViewModel（工厂模式）
  getIt.registerFactory<LogsViewModel>(
    () => LogsViewModel(
      statsCollector: getIt<StatsCollector>(),
      databaseService: getIt<DatabaseService>(),
    ),
  );

  // 注册 SettingsViewModel（工厂模式）
  getIt.registerFactory<SettingsViewModel>(
    () => SettingsViewModel(
      configManager: getIt<ConfigManager>(),
      themeService: getIt<ThemeService>(),
    ),
  );
}

/// 重置服务定位器（主要用于测试）
Future<void> resetServiceLocator() async {
  await getIt.reset();
}
