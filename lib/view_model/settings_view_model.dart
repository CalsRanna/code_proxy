import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';
import 'dart:convert';
import 'dart:io';
import 'base_view_model.dart';

/// 设置 ViewModel
/// 负责应用设置和配置管理
class SettingsViewModel extends BaseViewModel {
  final EndpointRepository _endpointRepository;
  late final SharedPreferences _prefs;

  /// 全局共享的主题模式 signal（所有 ViewModel 实例共享）
  /// 使用 static 确保跨实例共享状态，并在应用启动时可访问
  static final currentTheme = signal(ThemeMode.system);

  /// 响应式状态
  final config = signal(const ProxyServerConfig());
  final isSaving = signal(false);
  final isImporting = signal(false);
  final isExporting = signal(false);

  // 应用设置
  final language = signal('auto'); // 'zh', 'en', 'auto'

  // 常量
  static const String _themeKey = 'app_theme_mode';
  static const String _keyLanguage = 'language';
  static const String _keyProxyAddress = 'proxy_address';
  static const String _keyProxyPort = 'proxy_port';
  static const String _keyMaxRetries = 'max_retries';

  SettingsViewModel({
    required EndpointRepository endpointRepository,
    required SharedPreferences prefs,
  }) : _endpointRepository = endpointRepository,
       _prefs = prefs;

  /// 初始化
  Future<void> init() async {
    ensureNotDisposed();
    await loadConfig();
    await loadAppSettings();
  }

  /// 静态方法：初始化全局主题（在应用启动时调用）
  static Future<void> initGlobalTheme(SharedPreferences prefs) async {
    try {
      final themeIndex = prefs.getInt(_themeKey);
      if (themeIndex != null &&
          themeIndex >= 0 &&
          themeIndex < ThemeMode.values.length) {
        currentTheme.value = ThemeMode.values[themeIndex];
      } else {
        currentTheme.value = ThemeMode.system;
      }
    } catch (e) {
      currentTheme.value = ThemeMode.system;
    }
  }

  // =========================
  // 代理配置
  // =========================

  /// 加载代理配置
  Future<void> loadConfig() async {
    ensureNotDisposed();

    try {
      final address = _prefs.getString(_keyProxyAddress) ?? '127.0.0.1';
      final port = _prefs.getInt(_keyProxyPort) ?? 9000;
      final maxRetries = _prefs.getInt(_keyMaxRetries) ?? 3;

      config.value = ProxyServerConfig(
        address: address,
        port: port,
        maxRetries: maxRetries,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// 保存代理配置
  Future<void> saveConfig(ProxyServerConfig newConfig) async {
    ensureNotDisposed();

    isSaving.value = true;

    try {
      await _prefs.setString(_keyProxyAddress, newConfig.address);
      await _prefs.setInt(_keyProxyPort, newConfig.port);
      await _prefs.setInt(_keyMaxRetries, newConfig.maxRetries);
      config.value = newConfig;
    } catch (e) {
      rethrow;
    } finally {
      isSaving.value = false;
    }
  }

  /// 更新监听地址
  Future<void> updateListenAddress(String address) async {
    final updated = ProxyServerConfig(
      address: address,
      port: config.value.port,
      maxRetries: config.value.maxRetries,
    );

    await saveConfig(updated);
  }

  /// 更新监听端口
  Future<void> updateListenPort(int port) async {
    final updated = ProxyServerConfig(
      address: config.value.address,
      port: port,
      maxRetries: config.value.maxRetries,
    );

    await saveConfig(updated);
  }

  /// 更新最大重试次数
  Future<void> updateMaxRetries(int maxRetries) async {
    final updated = ProxyServerConfig(
      address: config.value.address,
      port: config.value.port,
      maxRetries: maxRetries,
    );

    await saveConfig(updated);
  }

  /// 重置为默认配置
  Future<void> resetToDefaults() async {
    ensureNotDisposed();
    await saveConfig(const ProxyServerConfig());
  }

  // =========================
  // 应用设置
  // =========================

  /// 加载应用设置
  Future<void> loadAppSettings() async {
    ensureNotDisposed();

    // 主题已在 initGlobalTheme 中加载，这里只加载其他设置
    language.value = _prefs.getString(_keyLanguage) ?? 'auto';
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
      await _prefs.setInt(_themeKey, mode.index);
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

    await _prefs.setString(_keyLanguage, lang);
    language.value = lang;
  }

  // =========================
  // 导入导出
  // =========================

  /// 导出配置到 JSON 文件
  Future<String> exportConfig() async {
    ensureNotDisposed();

    isExporting.value = true;

    try {
      // 获取导出数据
      final endpoints = await _endpointRepository.getAll();

      // 构建导出对象
      final exportData = {
        'version': '1.0',
        'exportedAt': DateTime.now().toIso8601String(),
        'proxyConfig': {
          'address': config.value.address,
          'port': config.value.port,
          'maxRetries': config.value.maxRetries,
        },
        'endpoints': endpoints.map((e) => e.toJson()).toList(),
      };

      // 获取文档目录
      final docDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportPath = path.join(
        docDir.path,
        'code_proxy_export_$timestamp.json',
      );

      // 写入文件
      final file = File(exportPath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(exportData),
      );

      return exportPath;
    } catch (e) {
      rethrow;
    } finally {
      isExporting.value = false;
    }
  }

  /// 从 JSON 文件导入配置
  Future<void> importConfig(String filePath, {bool merge = false}) async {
    ensureNotDisposed();

    isImporting.value = true;

    try {
      // 读取文件
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('配置文件不存在: $filePath');
      }

      final content = await file.readAsString();
      final jsonData = jsonDecode(content) as Map<String, dynamic>;

      // 验证版本
      final version = jsonData['version'] as String?;
      if (version != '1.0') {
        throw Exception('不支持的配置文件版本: $version');
      }

      // 导入代理配置
      if (jsonData.containsKey('proxyConfig')) {
        final proxyConfigJson = jsonData['proxyConfig'] as Map<String, dynamic>;
        final proxyConfig = ProxyServerConfig(
          address: proxyConfigJson['address'] as String? ?? '127.0.0.1',
          port: proxyConfigJson['port'] as int? ?? 9000,
          maxRetries: proxyConfigJson['maxRetries'] as int? ?? 3,
        );
        await saveConfig(proxyConfig);
      }

      // 导入端点
      if (jsonData.containsKey('endpoints')) {
        final endpointsJson = jsonData['endpoints'] as List;

        // 如果不是合并模式，先清空现有端点
        if (!merge) {
          await _endpointRepository.clearAll();
        }

        // 插入或更新端点
        for (final endpointJson in endpointsJson) {
          final endpoint = EndpointEntity.fromJson(
            endpointJson as Map<String, dynamic>,
          );

          // 检查端点是否已存在
          final existing = await _endpointRepository.getById(endpoint.id);
          if (existing == null) {
            await _endpointRepository.insert(endpoint);
          } else {
            await _endpointRepository.update(endpoint);
          }
        }
      }

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
      // 清空端点
      await _endpointRepository.clearAll();

      // 重置代理配置为默认值
      await saveConfig(const ProxyServerConfig());

      // 清空 SharedPreferences
      await _prefs.clear();

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

  // =========================
  // 清理资源
  // =========================

  @override
  void dispose() {
    // 注意：currentTheme 是静态的，不在这里清理
    // 清理实例信号
    config.dispose();
    isSaving.dispose();
    isImporting.dispose();
    isExporting.dispose();
    language.dispose();

    super.dispose();
  }
}
