import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'di.dart';
import 'router/router.dart';
import 'services/theme_service.dart';
import 'themes/app_theme.dart';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化依赖注入
  await setupServiceLocator();
  SignalsObserver.instance = null;
  runApp(const CodeProxyRouter());
}

class CodeProxyRouter extends StatelessWidget {
  const CodeProxyRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = getIt<ThemeService>();

    return Watch(
      (context) => MaterialApp.router(
        title: 'Code Proxy',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeService.currentTheme.value,
        routerConfig: router.config(),
      ),
    );
  }
}
