import 'package:code_proxy/di.dart';
import 'package:code_proxy/router/router.dart';
import 'package:code_proxy/themes/app_theme.dart';
import 'package:code_proxy/util/window_util.dart';
import 'package:code_proxy/view_model/settings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowUtil.ensureInitialized();
  await setupServiceLocator();
  SignalsObserver.instance = null;
  runApp(const CodeProxyApp());
}

class CodeProxyApp extends StatefulWidget {
  const CodeProxyApp({super.key});

  @override
  State<CodeProxyApp> createState() => _CodeProxyAppState();
}

class _CodeProxyAppState extends State<CodeProxyApp> {
  final settingViewModel = GetIt.instance.get<SettingsViewModel>();
  final sharedPreferences = GetIt.instance.get<SharedPreferences>();

  @override
  void initState() {
    settingViewModel.initGlobalTheme(sharedPreferences);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ShadApp.custom(
      appBuilder: (context) => Watch(
        (context) => MaterialApp.router(
          title: 'Code Proxy',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: settingViewModel.currentTheme.value,
          routerConfig: router.config(),
        ),
      ),
    );
  }
}
