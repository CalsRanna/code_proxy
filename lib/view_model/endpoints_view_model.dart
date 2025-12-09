import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:signals/signals.dart';
import 'package:uuid/uuid.dart';
import 'base_view_model.dart';

/// 端点管理 ViewModel
/// 负责端点的 CRUD 操作
class EndpointsViewModel extends BaseViewModel {
  final ConfigManager _configManager;
  final Uuid _uuid = const Uuid();

  /// 响应式状态
  final isLoading = signal(false);
  final errorMessage = signal<String?>(null);
  final searchQuery = signal('');

  /// 端点列表（使用 ConfigManager 的全局 signal）
  ListSignal<Endpoint> get endpoints => _configManager.endpoints;

  /// 过滤后的端点列表（根据搜索查询）
  late final filteredEndpoints = computed(() {
    final query = searchQuery.value.toLowerCase();
    if (query.isEmpty) return endpoints.value;

    return endpoints.value.where((endpoint) {
      return endpoint.name.toLowerCase().contains(query) ||
          endpoint.url.toLowerCase().contains(query) ||
          endpoint.category.toLowerCase().contains(query) ||
          (endpoint.notes?.toLowerCase().contains(query) ?? false);
    }).toList();
  });

  EndpointsViewModel({required ConfigManager configManager})
    : _configManager = configManager;

  /// 初始化
  Future<void> init() async {
    ensureNotDisposed();
    // 端点已由 ConfigManager 加载，无需再次加载
  }

  // =========================
  // 端点 CRUD 操作
  // =========================

  /// 添加端点
  Future<void> addEndpoint({
    required String name,
    required String url,
    required String category,
    String? notes,
    String? icon,
    String? iconColor,
    int weight = 1,
    String? apiKey,
    String authMode = 'standard',
    Map<String, String>? customHeaders,
    Map<String, dynamic>? settingsConfig,
  }) async {
    ensureNotDisposed();

    final now = DateTime.now().millisecondsSinceEpoch;
    final endpoint = Endpoint(
      id: _uuid.v4(),
      name: name,
      url: url,
      category: category,
      notes: notes,
      icon: icon,
      iconColor: iconColor,
      weight: weight,
      enabled: true,
      sortIndex: endpoints.value.length,
      createdAt: now,
      updatedAt: now,
      apiKey: apiKey,
      authMode: authMode,
      customHeaders: customHeaders,
      settingsConfig: settingsConfig,
    );

    try {
      // ConfigManager 会自动更新全局 signal
      await _configManager.saveEndpoint(endpoint);
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 更新端点
  Future<void> updateEndpoint(Endpoint endpoint) async {
    ensureNotDisposed();

    final updated = Endpoint(
      id: endpoint.id,
      name: endpoint.name,
      url: endpoint.url,
      category: endpoint.category,
      notes: endpoint.notes,
      icon: endpoint.icon,
      iconColor: endpoint.iconColor,
      weight: endpoint.weight,
      enabled: endpoint.enabled,
      sortIndex: endpoint.sortIndex,
      createdAt: endpoint.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      apiKey: endpoint.apiKey,
      authMode: endpoint.authMode,
      customHeaders: endpoint.customHeaders,
      settingsConfig: endpoint.settingsConfig,
    );

    try {
      // ConfigManager 会自动更新全局 signal
      await _configManager.saveEndpoint(updated);
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 删除端点
  Future<void> deleteEndpoint(String id) async {
    ensureNotDisposed();

    try {
      // ConfigManager 会自动更新全局 signal
      await _configManager.deleteEndpoint(id);
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 切换启用状态
  Future<void> toggleEnabled(String id) async {
    ensureNotDisposed();

    final endpoint = endpoints.value.firstWhere((e) => e.id == id);
    final updated = Endpoint(
      id: endpoint.id,
      name: endpoint.name,
      url: endpoint.url,
      category: endpoint.category,
      notes: endpoint.notes,
      icon: endpoint.icon,
      iconColor: endpoint.iconColor,
      weight: endpoint.weight,
      enabled: !endpoint.enabled,
      sortIndex: endpoint.sortIndex,
      createdAt: endpoint.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      apiKey: endpoint.apiKey,
      authMode: endpoint.authMode,
      customHeaders: endpoint.customHeaders,
      settingsConfig: endpoint.settingsConfig,
    );

    try {
      // ConfigManager 会自动更新全局 signal
      await _configManager.saveEndpoint(updated);
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 重新排序端点
  Future<void> reorderEndpoints(int oldIndex, int newIndex) async {
    ensureNotDisposed();

    final items = List<Endpoint>.from(endpoints.value);

    // 移除旧位置的项
    final item = items.removeAt(oldIndex);

    // 插入到新位置
    if (newIndex > oldIndex) {
      items.insert(newIndex - 1, item);
    } else {
      items.insert(newIndex, item);
    }

    // 更新所有端点的 sortIndex
    try {
      for (var i = 0; i < items.length; i++) {
        final endpoint = items[i];
        final updated = Endpoint(
          id: endpoint.id,
          name: endpoint.name,
          url: endpoint.url,
          category: endpoint.category,
          notes: endpoint.notes,
          icon: endpoint.icon,
          iconColor: endpoint.iconColor,
          weight: endpoint.weight,
          enabled: endpoint.enabled,
          sortIndex: i,
          createdAt: endpoint.createdAt,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          apiKey: endpoint.apiKey,
          authMode: endpoint.authMode,
          customHeaders: endpoint.customHeaders,
          settingsConfig: endpoint.settingsConfig,
        );
        await _configManager.saveEndpoint(updated);
      }
      // ConfigManager 会自动更新全局 signal
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 清空所有端点
  Future<void> clearAllEndpoints() async {
    ensureNotDisposed();

    try {
      // ConfigManager 会自动更新全局 signal
      await _configManager.clearAllEndpoints();
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  // =========================
  // 辅助方法
  // =========================

  /// 根据 ID 获取端点
  Endpoint? getEndpointById(String id) {
    try {
      return endpoints.value.firstWhere((e) => e.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 获取启用的端点数量
  int get enabledEndpointCount {
    return endpoints.value.where((e) => e.enabled).length;
  }

  /// 获取总端点数量
  int get totalEndpointCount => endpoints.value.length;

  /// 更新搜索查询
  void updateSearchQuery(String query) {
    searchQuery.value = query;
  }
}
