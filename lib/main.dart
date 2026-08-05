import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/di.dart';
import 'package:code_proxy/router/router.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/util/notification_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
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
  await SharedPreferenceUtil.instance.migrateIfNeeded();
  await Database.instance.ensureInitialized();
  DI.ensureInitialized();
  await NotificationUtil.instance.ensureInitialized();
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
    // Cmd+W 隐藏窗口仅适用于 macOS（隐藏标题栏 + 自定义按钮的配套行为）。
    // Windows 的 Win+W（小组件面板）和 Linux 的 Meta+W 不应触发此逻辑。
    if (!Platform.isMacOS) return false;
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
    final fallbackFonts = <String>[];
    if (Platform.isMacOS) {
      fallbackFonts.add('PingFang SC');
    } else if (Platform.isWindows) {
      fallbackFonts.add('Microsoft YaHei');
    } else if (Platform.isLinux) {
      fallbackFonts.add('Noto Sans SC');
    }

    var shadThemeData = ShadThemeData(
      textTheme:
          ShadTextTheme(family: 'Montserrat')
              .apply(fontFamilyFallback: fallbackFonts),
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
