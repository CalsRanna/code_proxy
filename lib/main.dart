import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/di.dart';
import 'package:code_proxy/router/router.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/util/tray_util.dart';
import 'package:code_proxy/util/window_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Database.instance.ensureInitialized();
  DI.ensureInitialized();
  await WindowUtil.instance.ensureInitialized();
  await TrayUtil.instance.ensureInitialized();

  // 初始化开机自启
  final packageInfo = await PackageInfo.fromPlatform();
  launchAtStartup.setup(
    appName: packageInfo.appName,
    appPath: Platform.resolvedExecutable,
  );

  SignalsObserver.instance = null;
  runApp(const CodeProxyApp());
}

class CodeProxyApp extends StatefulWidget {
  const CodeProxyApp({super.key});

  @override
  State<CodeProxyApp> createState() => _CodeProxyAppState();
}

class _CodeProxyAppState extends State<CodeProxyApp> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyW &&
        HardwareKeyboard.instance.isMetaPressed) {
      WindowUtil.instance.hide();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    var shadDecoration = ShadDecoration(color: ShadcnColors.zinc950);
    var shadThemeData = ShadThemeData(
      textTheme: ShadTextTheme(family: 'Montserrat'),
      sonnerTheme: ShadSonnerTheme(alignment: Alignment.topCenter),
      tooltipTheme: ShadTooltipTheme(decoration: shadDecoration),
    );
    return ShadApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router.config(),
      theme: shadThemeData,
      title: 'Code Proxy',
    );
  }
}
