import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/mcp_server_view_model.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:get_it/get_it.dart';

class DI {
  static void ensureInitialized() {
    final instance = GetIt.instance;
    instance.registerLazySingleton<HomeViewModel>(() => HomeViewModel());
    instance.registerLazySingleton<DashboardViewModel>(
      () => DashboardViewModel(),
    );
    instance.registerLazySingleton<EndpointViewModel>(
      () => EndpointViewModel(),
    );
    instance.registerLazySingleton<RequestLogViewModel>(
      () => RequestLogViewModel(),
    );
    instance.registerLazySingleton<SettingViewModel>(() => SettingViewModel());
    instance.registerLazySingleton<McpServerViewModel>(
      () => McpServerViewModel(),
    );
  }
}
