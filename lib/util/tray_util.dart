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

  Future<void> ensureInitialized() async {
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
      bool isTemplate;
      if (Platform.isWindows) {
        iconPath = 'asset/tray_icon.ico';
        isTemplate = false;
      } else if (Platform.isMacOS) {
        iconPath = 'asset/tray_icon.png';
        isTemplate = true;
      } else if (Platform.isLinux) {
        iconPath = 'asset/tray_icon.png';
        isTemplate = false;
      } else {
        LoggerUtil.instance.w('不支持的平台');
        return;
      }

      await trayManager.setIcon(iconPath, isTemplate: isTemplate);
      await trayManager.setToolTip('Code Proxy');
    } catch (e, stackTrace) {
      LoggerUtil.instance.e(e, stackTrace: stackTrace);
    }
  }
}
