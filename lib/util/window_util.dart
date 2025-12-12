import 'package:code_proxy/util/logger_util.dart';
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

  /// 销毁窗口（退出应用前调用）
  Future<void> destroy() async {
    try {
      LoggerUtil.instance.i('销毁窗口');
      await windowManager.destroy();
    } catch (e, stackTrace) {
      LoggerUtil.instance.e('销毁窗口失败', error: e, stackTrace: stackTrace);
    }
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
    try {
      LoggerUtil.instance.i('隐藏窗口到托盘');
      // 先从任务栏移除图标（Dock 和应用切换器）
      await windowManager.setSkipTaskbar(true);
      // 再隐藏窗口
      await windowManager.hide();
      LoggerUtil.instance.i('窗口已隐藏');
    } catch (e, stackTrace) {
      LoggerUtil.instance.e('隐藏窗口失败', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> restore() async {
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
        LoggerUtil.instance.i('窗口已恢复');
      }
    } catch (e, stackTrace) {
      LoggerUtil.instance.e('恢复窗口失败', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> show() async {
    try {
      LoggerUtil.instance.i('显示窗口');
      // 先恢复任务栏图标（Dock 和应用切换器）
      await windowManager.setSkipTaskbar(false);
      // 再显示窗口
      await windowManager.show();
      await windowManager.focus();
      LoggerUtil.instance.i('窗口已显示');
    } catch (e, stackTrace) {
      LoggerUtil.instance.e('显示窗口失败', error: e, stackTrace: stackTrace);
    }
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
