import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class WindowUtil {
  static final WindowUtil instance = WindowUtil._();

  WindowUtil._();

  Map<Type, Action<Intent>> get actions => {
    _HideWindowIntent: _HideWindowAction(),
  };

  Map<ShortcutActivator, Intent> get shortcuts => {
    const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
        const _HideWindowIntent(),
  };

  Future<void> destroy() async {
    await windowManager.destroy();
  }

  Future<void> ensureInitialized() async {
    var instance = SharedPreferenceUtil.instance;
    var height = await instance.getWindowHeight();
    var width = await instance.getWindowWidth();
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      center: true,
      minimumSize: const Size(1080, 720),
      size: Size(width, height),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      title: 'Code Proxy',
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true);
    });
  }

  Future<void> hide() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> restore() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
  }

  Future<void> show() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }
}

class _HideWindowAction extends Action<_HideWindowIntent> {
  @override
  Future<void> invoke(_HideWindowIntent intent) async {
    await WindowUtil.instance.hide();
  }
}

class _HideWindowIntent extends Intent {
  const _HideWindowIntent();
}
