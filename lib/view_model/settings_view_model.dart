import 'package:code_proxy/model/proxy_server_config_entity.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:code_proxy/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals.dart';
import 'base_view_model.dart';

/// 设置 ViewModel
/// 负责应用设置和配置管理
class SettingsViewModel extends BaseViewModel {
  final ConfigManager _configManager;
  final ThemeService _themeService;

  /// 全局共享的主题模式 signal（所有 ViewModel 实例共享）
  /// 使用 static 确保跨实例共享状态，并在应用启动时可访问
  static final currentTheme = signal(ThemeMode.system);

  /// 响应式状态
  final config = signal(const ProxyServerConfigEntity());
  final isSaving = signal(false);
  final isImporting = signal(false);
  final isExporting = signal(false);

  // 应用设置
  final language = signal('auto'); // 'zh', 'en', 'auto'

  SettingsViewModel({
    required ConfigManager configManager,
    required ThemeService themeService,
  }) : _configManager = configManager,
       _themeService = themeService;

  /// 初始化
  Future<void> init() async {
    ensureNotDisposed();
    await loadConfig();
    await loadAppSettings();
  }

  /// 静态方法：初始化全局主题（在应用启动时调用）
  static Future<void> initGlobalTheme(ThemeService themeService) async {
    final theme = await themeService.loadTheme();
    currentTheme.value = theme;
  }

  // =========================
  // 代理配置
  // =========================

  /// 加载代理配置
  Future<void> loadConfig() async {
    ensureNotDisposed();

    try {
      config.value = await _configManager.loadProxyConfig();
    } catch (e) {
      rethrow;
    }
  }

  /// 保存代理配置
  Future<void> saveConfig(ProxyServerConfigEntity newConfig) async {
    ensureNotDisposed();

    isSaving.value = true;

    try {
      await _configManager.saveProxyConfig(newConfig);
      config.value = newConfig;
    } catch (e) {
      rethrow;
    } finally {
      isSaving.value = false;
    }
  }

  /// 更新监听地址
  Future<void> updateListenAddress(String address) async {
    final updated = ProxyServerConfigEntity(
      address: address,
      port: config.value.port,
      maxRetries: config.value.maxRetries,
      requestTimeout: config.value.requestTimeout,
      healthCheckInterval: config.value.healthCheckInterval,
      healthCheckTimeout: config.value.healthCheckTimeout,
      healthCheckPath: config.value.healthCheckPath,
      consecutiveFailureThreshold: config.value.consecutiveFailureThreshold,
      enableLogging: config.value.enableLogging,
      maxLogEntries: config.value.maxLogEntries,
      responseTimeWindowSize: config.value.responseTimeWindowSize,
    );

    await saveConfig(updated);
  }

  /// 更新监听端口
  Future<void> updateListenPort(int port) async {
    final updated = ProxyServerConfigEntity(
      address: config.value.address,
      port: port,
      maxRetries: config.value.maxRetries,
      requestTimeout: config.value.requestTimeout,
      healthCheckInterval: config.value.healthCheckInterval,
      healthCheckTimeout: config.value.healthCheckTimeout,
      healthCheckPath: config.value.healthCheckPath,
      consecutiveFailureThreshold: config.value.consecutiveFailureThreshold,
      enableLogging: config.value.enableLogging,
      maxLogEntries: config.value.maxLogEntries,
      responseTimeWindowSize: config.value.responseTimeWindowSize,
    );

    await saveConfig(updated);
  }

  /// 重置为默认配置
  Future<void> resetToDefaults() async {
    ensureNotDisposed();
    await saveConfig(const ProxyServerConfigEntity());
  }

  // =========================
  // 应用设置
  // =========================

  /// 加载应用设置
  Future<void> loadAppSettings() async {
    ensureNotDisposed();

    // 主题已在 initGlobalTheme 中加载，这里只加载其他设置
    language.value = _configManager.getLanguage();
  }

  // =========================
  // 主题设置
  // =========================

  /// 是否为暗色模式
  bool get isDark => currentTheme.value == ThemeMode.dark;

  /// 是否为浅色模式
  bool get isLight => currentTheme.value == ThemeMode.light;

  /// 是否跟随系统
  bool get isSystem => currentTheme.value == ThemeMode.system;

  /// 设置主题模式
  Future<void> setTheme(ThemeMode mode) async {
    ensureNotDisposed();

    if (currentTheme.value != mode) {
      currentTheme.value = mode;
      await _themeService.saveTheme(mode);
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

  // =========================
  // 语言设置
  // =========================

  /// 设置语言
  Future<void> setLanguage(String lang) async {
    ensureNotDisposed();

    await _configManager.setLanguage(lang);
    language.value = lang;
  }

  // =========================
  // 导入导出
  // =========================

  /// 导出配置到文件
  Future<String> exportConfig() async {
    ensureNotDisposed();

    isExporting.value = true;

    try {
      final filePath = await _configManager.exportConfig();
      return filePath;
    } catch (e) {
      rethrow;
    } finally {
      isExporting.value = false;
    }
  }

  /// 从文件导入配置
  Future<void> importConfig(String filePath, {bool merge = false}) async {
    ensureNotDisposed();

    isImporting.value = true;

    try {
      await _configManager.importConfig(filePath, merge: merge);
      await loadConfig();
    } catch (e) {
      rethrow;
    } finally {
      isImporting.value = false;
    }
  }

  // =========================
  // 清空数据
  // =========================

  /// 清空所有数据
  Future<void> clearAllData() async {
    ensureNotDisposed();

    try {
      await _configManager.clearAll();
      await loadConfig();
      await loadAppSettings();
    } catch (e) {
      rethrow;
    }
  }

  // =========================
  // 验证
  // =========================

  /// 验证监听地址
  bool isValidListenAddress(String address) {
    // 简单的 IP 地址验证
    if (address == '127.0.0.1' || address == 'localhost') return true;
    if (address == '0.0.0.0') return true;

    // 更完整的 IP 验证可以使用正则表达式
    final ipPattern = RegExp(
      r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
    );

    return ipPattern.hasMatch(address);
  }

  /// 验证端口号
  bool isValidPort(int port) {
    return port >= 1 && port <= 65535;
  }

  /// 验证健康检查路径
  bool isValidHealthCheckPath(String path) {
    return path.startsWith('/') && path.isNotEmpty;
  }
}
