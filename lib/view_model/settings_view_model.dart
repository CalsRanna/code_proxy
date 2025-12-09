import 'package:code_proxy/model/proxy_config.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:signals/signals.dart';
import 'base_view_model.dart';

/// 设置 ViewModel
/// 负责应用设置和配置管理
class SettingsViewModel extends BaseViewModel {
  final ConfigManager _configManager;

  /// 响应式状态
  final config = signal(const ProxyConfig());
  final isSaving = signal(false);
  final isImporting = signal(false);
  final isExporting = signal(false);

  // 应用设置
  final themeMode = signal('system'); // 'light', 'dark', 'system'
  final language = signal('auto'); // 'zh', 'en', 'auto'

  SettingsViewModel({required ConfigManager configManager})
    : _configManager = configManager;

  /// 初始化
  Future<void> init() async {
    ensureNotDisposed();
    await loadConfig();
    loadAppSettings();
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
  Future<void> saveConfig(ProxyConfig newConfig) async {
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
    final updated = ProxyConfig(
      listenAddress: address,
      listenPort: config.value.listenPort,
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
    final updated = ProxyConfig(
      listenAddress: config.value.listenAddress,
      listenPort: port,
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
    await saveConfig(const ProxyConfig());
  }

  // =========================
  // 应用设置
  // =========================

  /// 加载应用设置
  void loadAppSettings() {
    ensureNotDisposed();

    themeMode.value = _configManager.getThemeMode();
    language.value = _configManager.getLanguage();
  }

  /// 设置主题模式
  Future<void> setThemeMode(String mode) async {
    ensureNotDisposed();

    await _configManager.setThemeMode(mode);
    themeMode.value = mode;
  }

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
      loadAppSettings();
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
