import 'dart:io';

import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/window_util.dart';
import 'package:tray_manager/tray_manager.dart';

class TrayUtil with TrayListener {
  static final TrayUtil instance = TrayUtil._();

  TrayUtil._();

  Future<void> dispose() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }

  Future<void> ensureInitialized({Function()? onShow}) async {
    trayManager.addListener(this);
    await _setTrayIcon();
  }

  @override
  void onTrayIconMouseDown() {
    WindowUtil.instance.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    WindowUtil.instance.show();
  }

  Future<void> _setTrayIcon() async {
    try {
      String iconPath;
      if (Platform.isWindows) {
        iconPath = 'asset/tray_icon.ico';
      } else if (Platform.isMacOS) {
        iconPath = 'asset/tray_icon.png';
      } else if (Platform.isLinux) {
        iconPath = 'asset/tray_icon.png';
      } else {
        LoggerUtil.instance.w('不支持的平台');
        return;
      }

      await trayManager.setIcon(iconPath, isTemplate: true);
    } catch (e, stackTrace) {
      LoggerUtil.instance.e(e, stackTrace: stackTrace);
    }
  }
}
