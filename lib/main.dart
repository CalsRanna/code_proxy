import 'package:code_proxy/util/window_util.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'di.dart';
import 'router/router.dart';
import 'services/proxy_server/proxy_server_service.dart';
import 'view_model/settings_view_model.dart';
import 'themes/app_theme.dart';

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

class CodeProxyRouter extends StatelessWidget {
  const CodeProxyRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp.custom(
      appBuilder: (context) => Watch(
        (context) => MaterialApp.router(
          title: 'Code Proxy',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: SettingsViewModel.currentTheme.value,
          routerConfig: router.config(),
        ),
      ),
    );
  }
}

class _CodeProxyAppState extends State<CodeProxyApp> {
  @override
  Widget build(BuildContext context) {
    return const CodeProxyRouter();
  }

  @override
  void dispose() {
    // 应用退出时停止代理服务器
    _stopProxyServer();
    super.dispose();
  }

  /// 停止代理服务器
  void _stopProxyServer() {
    try {
      final proxyServer = getIt<ProxyServerService>();
      proxyServer.stop().catchError((error) {
        // 静默处理错误
      });
    } catch (e) {
      // 如果服务未注册，忽略错误
    }
  }
}
