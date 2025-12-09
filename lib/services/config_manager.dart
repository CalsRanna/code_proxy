import 'dart:convert';
import 'dart:io';
import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/model/proxy_config.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';
import 'database_service.dart';

/// 配置管理器
/// 使用 DatabaseService 管理业务数据（端点、代理配置）
/// 使用 SharedPreferences 管理应用配置（主题、语言、窗口状态）
class ConfigManager {
  final DatabaseService _databaseService;
  late SharedPreferences _prefs;
  bool _initialized = false;

  /// 全局端点列表 signal（所有 ViewModel 共享）
  final endpoints = listSignal<Endpoint>([]);

  ConfigManager(this._databaseService);

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 初始化配置管理器
  Future<void> init() async {
    if (_initialized) return;

    // 初始化数据库
    await _databaseService.init();

    // 初始化 SharedPreferences
    _prefs = await SharedPreferences.getInstance();

    // 加载端点到全局 signal（直接加载，不调用 refreshEndpoints 避免初始化检查）
    final data = await _databaseService.getAllEndpoints();
    endpoints.value = data;

    _initialized = true;
  }

  // =========================
  // 业务数据（通过 DatabaseService）
  // =========================

  /// 加载代理配置
  Future<ProxyConfig> loadProxyConfig() async {
    _ensureInitialized();
    return await _databaseService.getProxyConfig();
  }

  /// 保存代理配置
  Future<void> saveProxyConfig(ProxyConfig config) async {
    _ensureInitialized();
    await _databaseService.saveProxyConfig(config);
  }

  /// 加载所有端点
  Future<List<Endpoint>> loadEndpoints() async {
    _ensureInitialized();
    return await _databaseService.getAllEndpoints();
  }

  /// 刷新全局端点列表（从数据库重新加载）
  Future<void> refreshEndpoints() async {
    _ensureInitialized();
    final data = await _databaseService.getAllEndpoints();
    endpoints.value = data;
  }

  /// 保存端点（插入或更新）
  Future<void> saveEndpoint(Endpoint endpoint) async {
    _ensureInitialized();

    // 检查端点是否已存在
    final existing = await _databaseService.getEndpointById(endpoint.id);
    if (existing == null) {
      await _databaseService.insertEndpoint(endpoint);
    } else {
      await _databaseService.updateEndpoint(endpoint);
    }

    // 刷新全局端点列表
    await refreshEndpoints();
  }

  /// 删除端点
  Future<void> deleteEndpoint(String id) async {
    _ensureInitialized();
    await _databaseService.deleteEndpoint(id);

    // 刷新全局端点列表
    await refreshEndpoints();
  }

  /// 根据 ID 获取端点
  Future<Endpoint?> getEndpointById(String id) async {
    _ensureInitialized();
    return await _databaseService.getEndpointById(id);
  }

  /// 清空所有端点
  Future<void> clearAllEndpoints() async {
    _ensureInitialized();
    await _databaseService.clearAllEndpoints();

    // 刷新全局端点列表
    await refreshEndpoints();
  }

  // =========================
  // 应用配置（通过 SharedPreferences）
  // =========================

  // 主题模式键
  static const String _keyThemeMode = 'theme_mode';
  // 语言键
  static const String _keyLanguage = 'language';
  // 最后使用的端点 ID
  static const String _keyLastUsedEndpointId = 'last_used_endpoint_id';
  // 窗口大小
  static const String _keyWindowWidth = 'window_width';
  static const String _keyWindowHeight = 'window_height';
  // 窗口位置
  static const String _keyWindowX = 'window_x';
  static const String _keyWindowY = 'window_y';

  /// 获取主题模式
  /// 返回值: 'light', 'dark', 'system'
  String getThemeMode() {
    _ensureInitialized();
    return _prefs.getString(_keyThemeMode) ?? 'system';
  }

  /// 设置主题模式
  Future<void> setThemeMode(String mode) async {
    _ensureInitialized();
    await _prefs.setString(_keyThemeMode, mode);
  }

  /// 获取语言
  /// 返回值: 'zh', 'en', 'auto'
  String getLanguage() {
    _ensureInitialized();
    return _prefs.getString(_keyLanguage) ?? 'auto';
  }

  /// 设置语言
  Future<void> setLanguage(String language) async {
    _ensureInitialized();
    await _prefs.setString(_keyLanguage, language);
  }

  /// 获取最后使用的端点 ID
  String? getLastUsedEndpointId() {
    _ensureInitialized();
    return _prefs.getString(_keyLastUsedEndpointId);
  }

  /// 设置最后使用的端点 ID
  Future<void> setLastUsedEndpointId(String? id) async {
    _ensureInitialized();
    if (id == null) {
      await _prefs.remove(_keyLastUsedEndpointId);
    } else {
      await _prefs.setString(_keyLastUsedEndpointId, id);
    }
  }

  /// 获取窗口大小
  /// 返回 (width, height)，如果未设置则返回 null
  (double, double)? getWindowSize() {
    _ensureInitialized();
    final width = _prefs.getDouble(_keyWindowWidth);
    final height = _prefs.getDouble(_keyWindowHeight);
    if (width == null || height == null) return null;
    return (width, height);
  }

  /// 设置窗口大小
  Future<void> setWindowSize(double width, double height) async {
    _ensureInitialized();
    await _prefs.setDouble(_keyWindowWidth, width);
    await _prefs.setDouble(_keyWindowHeight, height);
  }

  /// 获取窗口位置
  /// 返回 (x, y)，如果未设置则返回 null
  (double, double)? getWindowPosition() {
    _ensureInitialized();
    final x = _prefs.getDouble(_keyWindowX);
    final y = _prefs.getDouble(_keyWindowY);
    if (x == null || y == null) return null;
    return (x, y);
  }

  /// 设置窗口位置
  Future<void> setWindowPosition(double x, double y) async {
    _ensureInitialized();
    await _prefs.setDouble(_keyWindowX, x);
    await _prefs.setDouble(_keyWindowY, y);
  }

  // =========================
  // 导入导出功能
  // =========================

  /// 导出配置到 JSON 文件
  /// 返回导出的文件路径
  Future<String> exportConfig() async {
    _ensureInitialized();

    // 获取导出数据
    final proxyConfig = await loadProxyConfig();
    final endpoints = await loadEndpoints();

    // 构建导出对象
    final exportData = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'proxyConfig': proxyConfig.toJson(),
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
  }

  /// 从 JSON 文件导入配置
  /// 参数:
  ///   - filePath: JSON 文件路径
  ///   - merge: 是否合并（true）或替换（false）现有数据
  Future<void> importConfig(String filePath, {bool merge = false}) async {
    _ensureInitialized();

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
      final proxyConfig = ProxyConfig.fromJson(
        jsonData['proxyConfig'] as Map<String, dynamic>,
      );
      await saveProxyConfig(proxyConfig);
    }

    // 导入端点
    if (jsonData.containsKey('endpoints')) {
      final endpointsJson = jsonData['endpoints'] as List;

      // 如果不是合并模式，先清空现有端点
      if (!merge) {
        await clearAllEndpoints();
      }

      // 插入或更新端点
      for (final endpointJson in endpointsJson) {
        final endpoint = Endpoint.fromJson(
          endpointJson as Map<String, dynamic>,
        );
        await saveEndpoint(endpoint);
      }
    }
  }

  /// 清空所有数据（包括数据库和 SharedPreferences）
  Future<void> clearAll() async {
    _ensureInitialized();

    // 清空数据库中的端点
    await clearAllEndpoints();

    // 重置代理配置为默认值
    await saveProxyConfig(const ProxyConfig());

    // 清空 SharedPreferences
    await _prefs.clear();
  }

  // =========================
  // 辅助方法
  // =========================

  /// 确保配置管理器已初始化
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('ConfigManager not initialized. Call init() first.');
    }
  }
}
