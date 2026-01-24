import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/di.dart';
import 'package:code_proxy/router/router.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/util/tray_util.dart';
import 'package:code_proxy/util/window_util.dart';
import 'package:flutter/material.dart';
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

class CodeProxyApp extends StatelessWidget {
  const CodeProxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    var shadDecoration = ShadDecoration(color: ShadcnColors.zinc950);
    var shadThemeData = ShadThemeData(
      textTheme: ShadTextTheme(family: 'Montserrat'),
      sonnerTheme: ShadSonnerTheme(alignment: Alignment.topCenter),
      tooltipTheme: ShadTooltipTheme(decoration: shadDecoration),
    );
    var child = ShadApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router.config(),
      theme: shadThemeData,
      title: 'Code Proxy',
    );

    var actions = Actions(actions: WindowUtil.instance.actions, child: child);
    var shortcuts = Shortcuts(shortcuts: WindowUtil.instance.shortcuts, child: actions);
    return Focus(
      onKeyEvent: (node, event) => KeyEventResult.ignored,
      child: shortcuts,
    );
  }
}
