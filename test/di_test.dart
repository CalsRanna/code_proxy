import 'package:code_proxy/di.dart';
import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DI.ensureInitialized();
  });
  tearDown(() => GetIt.instance.reset());

  for (final homeFirst in [true, false]) {
    test(
      'VM construction and disposal are independent of resolution order (homeFirst=$homeFirst)',
      () {
        final getIt = GetIt.instance;
        if (homeFirst) getIt.get<HomeViewModel>();
        final settings = getIt.get<SettingViewModel>();
        final endpoints = getIt.get<EndpointViewModel>();
        getIt.get<DashboardViewModel>();
        getIt.get<RequestLogViewModel>();
        getIt.get<HomeViewModel>();
        expect(identical(settings, getIt.get<SettingViewModel>()), isTrue);
        expect(identical(endpoints, getIt.get<EndpointViewModel>()), isTrue);
      },
    );
  }
}
