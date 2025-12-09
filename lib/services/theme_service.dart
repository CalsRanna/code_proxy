import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';

/// 主题管理服务
/// 负责管理应用的亮色/暗色主题切换
class ThemeService {
  static const String _themeKey = 'app_theme_mode';

  /// 当前主题模式（响应式信号）
  late final Signal<ThemeMode> currentTheme;

  /// 是否为暗色模式
  bool get isDark => currentTheme.value == ThemeMode.dark;

  /// 是否为浅色模式
  bool get isLight => currentTheme.value == ThemeMode.light;

  /// 是否跟随系统
  bool get isSystem => currentTheme.value == ThemeMode.system;

  ThemeService() {
    // 初始化为系统主题
    currentTheme = Signal(ThemeMode.system);
    // 异步加载保存的主题设置
    _loadTheme();
  }

  /// 从本地存储加载主题设置
  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt(_themeKey);

      if (themeIndex != null) {
        currentTheme.value = ThemeMode.values[themeIndex];
      }
    } catch (e) {
      // 加载失败，使用默认主题（system）
      debugPrint('加载主题设置失败: $e');
    }
  }

  /// 保存主题设置到本地存储
  Future<void> _saveTheme(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeKey, mode.index);
    } catch (e) {
      debugPrint('保存主题设置失败: $e');
    }
  }

  /// 设置主题模式
  Future<void> setTheme(ThemeMode mode) async {
    if (currentTheme.value != mode) {
      currentTheme.value = mode;
      await _saveTheme(mode);
    }
  }

  /// 切换到浅色主题
  Future<void> setLightTheme() async {
    await setTheme(ThemeMode.light);
  }

  /// 切换到暗色主题
  Future<void> setDarkTheme() async {
    await setTheme(ThemeMode.dark);
  }

  /// 切换到跟随系统
  Future<void> setSystemTheme() async {
    await setTheme(ThemeMode.system);
  }

  /// 在浅色和暗色之间切换
  /// 如果当前是 system 模式，则切换到 light
  Future<void> toggleTheme() async {
    switch (currentTheme.value) {
      case ThemeMode.light:
        await setDarkTheme();
        break;
      case ThemeMode.dark:
      case ThemeMode.system:
        await setLightTheme();
        break;
    }
  }

  /// 获取主题模式的显示名称
  String getThemeDisplayName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '暗色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  /// 获取当前主题的显示名称
  String get currentThemeDisplayName => getThemeDisplayName(currentTheme.value);
}
