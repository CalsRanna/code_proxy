import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/repository/proxy_config_repository.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/services/claude_code_config_manager.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:code_proxy/services/database_service.dart';
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
  // 数据库层（Database）
  // =============================

  // 注册 Database（单例，底层数据库连接）
  getIt.registerLazySingleton<Database>(() => Database.instance);

  // 初始化数据库
  await getIt<Database>().ensureInitialized();

  // =============================
  // 仓库层（Repositories）
  // =============================

  // 注册 EndpointRepository（工厂模式，依赖 Database）
  getIt.registerFactory<EndpointRepository>(
    () => EndpointRepository(getIt<Database>()),
  );

  // 注册 ProxyConfigRepository（工厂模式，依赖 Database）
  getIt.registerFactory<ProxyConfigRepository>(
    () => ProxyConfigRepository(getIt<Database>()),
  );

  // 注册 RequestLogRepository（工厂模式，依赖 Database）
  getIt.registerFactory<RequestLogRepository>(
    () => RequestLogRepository(getIt<Database>()),
  );

  // =============================
  // 服务层（Services）
  // =============================

  // 注册 DatabaseService（单例，包装仓库层以保持向后兼容）
  getIt.registerLazySingleton<DatabaseService>(() => DatabaseService(
    endpointRepository: getIt<EndpointRepository>(),
    proxyConfigRepository: getIt<ProxyConfigRepository>(),
    requestLogRepository: getIt<RequestLogRepository>(),
  ));

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

  // 注册 StatsCollector（单例）
  getIt.registerLazySingleton<StatsCollector>(
    () => StatsCollector(databaseService: getIt<DatabaseService>()),
  );

  // 注册 ClaudeCodeConfigManager（单例）
  getIt.registerLazySingleton<ClaudeCodeConfigManager>(
    () => ClaudeCodeConfigManager(),
  );

  // =============================
  // ViewModel 层
  // =============================

  // 注册 HomeViewModel（工厂模式，每次获取创建新实例）
  getIt.registerFactory<HomeViewModel>(
    () => HomeViewModel(
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
    () => MonitoringViewModel(statsCollector: getIt<StatsCollector>()),
  );

  // 注册 LogsViewModel（工厂模式）
  getIt.registerFactory<LogsViewModel>(
    () => LogsViewModel(
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
