import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/services/claude_code_config_manager.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/logs_view_model.dart';
import 'package:code_proxy/view_model/settings_view_model.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // 注册 RequestLogRepository（工厂模式，依赖 Database）
  getIt.registerFactory<RequestLogRepository>(
    () => RequestLogRepository(getIt<Database>()),
  );

  // =============================
  // SharedPreferences
  // =============================

  // 注册 SharedPreferences（单例）
  final prefs = await SharedPreferences.getInstance();
  getIt.registerLazySingleton<SharedPreferences>(() => prefs);

  // =============================
  // 服务层（Services）
  // =============================

  // 注册 ClaudeCodeConfigManager（单例）
  getIt.registerLazySingleton<ClaudeCodeConfigManager>(
    () => ClaudeCodeConfigManager(),
  );

  // =============================
  // 初始化全局数据
  // =============================

  // 初始化全局 endpoints signal（从数据库加载）
  final endpoints = await getIt<EndpointRepository>().getAll();
  EndpointsViewModel.endpoints.value = endpoints;

  // =============================
  // ViewModel 层
  // =============================

  // 注册 HomeViewModel（工厂模式，每次获取创建新实例）
  getIt.registerFactory<HomeViewModel>(
    () => HomeViewModel(
      claudeCodeConfigManager: getIt<ClaudeCodeConfigManager>(),
      requestLogRepository: getIt<RequestLogRepository>(),
      prefs: getIt<SharedPreferences>(),
    ),
  );

  // 注册 EndpointsViewModel（单例模式，依赖 EndpointRepository）
  getIt.registerLazySingleton<EndpointsViewModel>(
    () => EndpointsViewModel(endpointRepository: getIt<EndpointRepository>()),
  );

  // 注册 LogsViewModel（单例模式，依赖 RequestLogRepository）
  getIt.registerLazySingleton<LogsViewModel>(
    () => LogsViewModel(requestLogRepository: getIt<RequestLogRepository>()),
  );

  // 注册 SettingsViewModel（单例模式，依赖 Repository 和 SharedPreferences）
  getIt.registerLazySingleton<SettingsViewModel>(
    () => SettingsViewModel(
      endpointRepository: getIt<EndpointRepository>(),
      prefs: getIt<SharedPreferences>(),
    ),
  );
}

/// 重置服务定位器（主要用于测试）
Future<void> resetServiceLocator() async {
  await getIt.reset();
}
