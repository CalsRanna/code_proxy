import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/di.dart';
import 'package:code_proxy/router/router.dart';
import 'package:code_proxy/util/tray_util.dart';
import 'package:code_proxy/util/window_util.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Database.instance.ensureInitialized();
  DI.ensureInitialized();
  await WindowUtil.instance.ensureInitialized();
  await TrayUtil.instance.ensureInitialized();
  SignalsObserver.instance = null;
  runApp(const CodeProxyApp());
}

class CodeProxyApp extends StatelessWidget {
  const CodeProxyApp({super.key});

  @override
  Widget build(BuildContext context) {
    var child = ShadApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router.config(),
      theme: ShadThemeData(
        textTheme: ShadTextTheme(family: 'Montserrat'),
        sonnerTheme: ShadSonnerTheme(alignment: Alignment.topCenter),
      ),
      title: 'Code Proxy',
    );

    var actions = Actions(actions: WindowUtil.instance.actions, child: child);
    return Shortcuts(shortcuts: WindowUtil.instance.shortcuts, child: actions);
  }
}
