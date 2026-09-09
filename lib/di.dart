import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/app_maintenance_service.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/dashboard_stats_loader.dart';
import 'package:code_proxy/service/default_model_config_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/service/proxy_audit_service.dart';
import 'package:code_proxy/service/proxy_client_settings_service.dart';
import 'package:code_proxy/service/proxy_request_log_service.dart';
import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:code_proxy/service/request_log_factory.dart';
import 'package:code_proxy/util/notification_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:get_it/get_it.dart';

class DI {
  static void ensureInitialized() {
    final instance = GetIt.instance;
    instance.registerLazySingleton(() => EndpointRepository(Database.instance));
    instance.registerLazySingleton(
      () => RequestLogRepository(Database.instance),
    );
    instance.registerLazySingleton(() => ClaudeCodeSettingService());
    instance.registerLazySingleton(() => ClaudeDesktopSettingService());
    instance.registerLazySingleton(
      () => ProxyClientSettingsService(
        code: instance.get<ClaudeCodeSettingService>(),
        desktop: instance.get<ClaudeDesktopSettingService>(),
      ),
    );
    instance.registerLazySingleton(
      () => AppMaintenanceService(
        database: Database.instance,
        endpoints: instance.get<EndpointRepository>(),
        requestLogs: instance.get<RequestLogRepository>(),
        preferences: SharedPreferenceUtil.instance,
      ),
    );
    instance.registerLazySingleton(
      () => ProxyRequestLogService(
        repository: instance.get<RequestLogRepository>(),
        audit: ProxyAuditService.instance,
        logFactory: RequestLogFactory.create(),
      ),
      dispose: (service) => service.dispose(),
    );
    instance.registerLazySingleton(
      () => ProxyServerController(
        preferences: SharedPreferenceUtil.instance,
        clientSettings: instance.get<ProxyClientSettingsService>(),
        requestLogs: instance.get<ProxyRequestLogService>(),
        notifications: NotificationUtil.instance,
      ),
      dispose: (controller) => controller.dispose(),
    );
    instance.registerLazySingleton(
      () => HomeViewModel(
        proxy: instance.get<ProxyServerController>(),
        modelConfig: DefaultModelConfigService.instance,
        audit: ProxyAuditService.instance,
        pricing: ModelPricingService.instance,
      ),
    );
    instance.registerLazySingleton(
      () => DashboardViewModel(
        database: Database.instance,
        statsLoader: DashboardStatsLoader(),
        pricing: ModelPricingService.instance,
        logChanges: instance.get<ProxyRequestLogService>().changes,
      ),
      dispose: (vm) => vm.dispose(),
    );
    instance.registerLazySingleton(
      () => EndpointViewModel(
        repository: instance.get<EndpointRepository>(),
        proxy: instance.get<ProxyServerController>(),
      ),
      dispose: (vm) => vm.dispose(),
    );
    instance.registerLazySingleton(
      () => RequestLogViewModel(
        repository: instance.get<RequestLogRepository>(),
        logChanges: instance.get<ProxyRequestLogService>().changes,
      ),
      dispose: (vm) => vm.dispose(),
    );
    instance.registerLazySingleton(
      () => SettingViewModel(
        proxy: instance.get<ProxyServerController>(),
        preferences: SharedPreferenceUtil.instance,
        codeSettings: instance.get<ClaudeCodeSettingService>(),
        desktopSettings: instance.get<ClaudeDesktopSettingService>(),
        modelConfig: DefaultModelConfigService.instance,
        pricing: ModelPricingService.instance,
        maintenance: instance.get<AppMaintenanceService>(),
      ),
    );
  }
}
