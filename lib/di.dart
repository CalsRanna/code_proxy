import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/logs_view_model.dart';
import 'package:code_proxy/view_model/settings_view_model.dart';
import 'package:get_it/get_it.dart';

class DI {
  static void ensureInitialized() {
    final instance = GetIt.instance;
    instance.registerLazySingleton<HomeViewModel>(() => HomeViewModel());
    instance.registerLazySingleton<DashboardViewModel>(
      () => DashboardViewModel(),
    );
    instance.registerLazySingleton<EndpointsViewModel>(
      () => EndpointsViewModel(),
    );
    instance.registerLazySingleton<LogsViewModel>(() => LogsViewModel());
    instance.registerLazySingleton<SettingsViewModel>(
      () => SettingsViewModel(),
    );
  }
}
