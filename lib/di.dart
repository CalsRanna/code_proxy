import 'package:code_proxy/services/claude_code_config_manager.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:code_proxy/services/database_service.dart';
import 'package:code_proxy/services/health_checker.dart';
import 'package:code_proxy/services/load_balancer.dart';
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

  // 加载初始配置
  final config = await getIt<ConfigManager>().loadProxyConfig();

  // 注册 StatsCollector（单例）
  getIt.registerLazySingleton<StatsCollector>(
    () => StatsCollector(
      maxLogEntries: config.maxLogEntries,
      databaseService: getIt<DatabaseService>(),
    ),
  );

  // 注册 HealthChecker（单例）
  getIt.registerLazySingleton<HealthChecker>(
    () => HealthChecker(
      config: config,
      // 从 ConfigManager 获取端点列表
      getEndpoints: () => getIt<ConfigManager>().endpoints.value,
    ),
  );

  // 注册 LoadBalancer（单例）
  getIt.registerLazySingleton<LoadBalancer>(
    () => LoadBalancer(
      // 从 ConfigManager 获取端点列表
      getEndpoints: () => getIt<ConfigManager>().endpoints.value,
      isHealthy: (endpointId) => getIt<HealthChecker>().isHealthy(endpointId),
      responseTimeWindowSize: config.responseTimeWindowSize,
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
      // 从 ConfigManager 获取端点列表
      getEndpoints: () => getIt<ConfigManager>().endpoints.value,
      loadBalancer: getIt<LoadBalancer>(),
      healthChecker: getIt<HealthChecker>(),
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
      healthChecker: getIt<HealthChecker>(),
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
      healthChecker: getIt<HealthChecker>(),
      configManager: getIt<ConfigManager>(),
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
    () => SettingsViewModel(configManager: getIt<ConfigManager>()),
  );
}

/// 重置服务定位器（主要用于测试）
Future<void> resetServiceLocator() async {
  await getIt.reset();
}
