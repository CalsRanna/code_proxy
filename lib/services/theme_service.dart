import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题管理服务
/// 负责主题设置的持久化（读取和保存）
/// 注意：主题状态由 SettingsViewModel 管理，此服务仅负责持久化
class ThemeService {
  static const String _themeKey = 'app_theme_mode';

  /// 从本地存储加载主题设置
  Future<ThemeMode> loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt(_themeKey);

      if (themeIndex != null && themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
        return ThemeMode.values[themeIndex];
      }
      return ThemeMode.system; // 默认跟随系统
    } catch (e) {
      debugPrint('加载主题设置失败: $e');
      return ThemeMode.system;
    }
  }

  /// 保存主题设置到本地存储
  Future<void> saveTheme(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeKey, mode.index);
    } catch (e) {
      debugPrint('保存主题设置失败: $e');
    }
  }
}
