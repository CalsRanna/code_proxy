import 'dart:async';
import 'dart:io';

import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

enum WindowEvent { shown }

class WindowUtil with WindowListener {
  static final WindowUtil instance = WindowUtil._();

  final _controller = StreamController<WindowEvent>();

  WindowUtil._();

  Stream<WindowEvent> get stream => _controller.stream;

  Future<void> ensureInitialized() async {
    var instance = SharedPreferenceUtil.instance;
    var height = await instance.getWindowHeight();
    var width = await instance.getWindowWidth();
    await windowManager.ensureInitialized();

    TitleBarStyle? titleStyle = TitleBarStyle.hidden;
    if (Platform.isWindows) {
      titleStyle = TitleBarStyle.normal;
    }
    final options = WindowOptions(
      center: true,
      minimumSize: const Size(1080, 720),
      size: Size(width, height),
      titleBarStyle: titleStyle,
      windowButtonVisibility: false,
      title: 'Code Proxy',
      // 启动即驻留托盘：不进入任务栏 / Dock，避免图标一闪而过。
      skipTaskbar: true,
    );
    windowManager.addListener(this);
    // 启动时不显示主窗口，应用直接出现在系统托盘；用户点击托盘图标、
    // 点击通知，或启动失败需要提示时再调用 show()。三端原生 runner 也都
    // 改成了不在首帧自动显示窗口，否则会先闪出一个空白窗口。
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPreventClose(true);
    });
  }

  @override
  void onWindowClose() {
    hide();
  }

  Future<void> hide() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<bool> isMaximized() async {
    return await windowManager.isMaximized();
  }

  Future<void> maximize() async {
    await windowManager.maximize();
  }

  Future<void> minimize() async {
    await windowManager.minimize();
  }

  Future<void> show() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
    // 确保 Flutter 根焦点被激活
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.requestFocus();
    });
    _controller.add(WindowEvent.shown);
  }

  Future<void> unmaximize() async {
    await windowManager.unmaximize();
  }
}
