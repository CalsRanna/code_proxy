import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:signals/signals.dart';
import 'package:uuid/uuid.dart';
import 'base_view_model.dart';

/// 端点管理 ViewModel
/// 负责端点的 CRUD 操作
class EndpointsViewModel extends BaseViewModel {
  final ConfigManager _configManager;
  final Uuid _uuid = const Uuid();

  /// 全局共享的端点列表 signal（所有 ViewModel 实例共享）
  /// 使用 static 确保跨实例共享状态
  static final endpoints = listSignal<EndpointEntity>([]);

  /// 响应式状态
  final isLoading = signal(false);
  final errorMessage = signal<String?>(null);
  final searchQuery = signal('');

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
    // 从 ConfigManager 加载端点到 ViewModel 的 signal
    await _loadEndpoints();
  }

  /// 从数据库加载端点列表
  Future<void> _loadEndpoints() async {
    ensureNotDisposed();
    try {
      final data = await _configManager.loadEndpoints();
      endpoints.value = data;
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
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
    final endpoint = EndpointEntity(
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
      await _configManager.saveEndpoint(endpoint);
      // 重新加载端点列表以更新 signal
      await _loadEndpoints();
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 更新端点
  Future<void> updateEndpoint(EndpointEntity endpoint) async {
    ensureNotDisposed();

    final updated = EndpointEntity(
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
      await _configManager.saveEndpoint(updated);
      // 重新加载端点列表以更新 signal
      await _loadEndpoints();
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 删除端点
  Future<void> deleteEndpoint(String id) async {
    ensureNotDisposed();

    try {
      await _configManager.deleteEndpoint(id);
      // 重新加载端点列表以更新 signal
      await _loadEndpoints();
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 切换启用状态
  Future<void> toggleEnabled(String id) async {
    ensureNotDisposed();

    final endpoint = endpoints.value.firstWhere((e) => e.id == id);
    final updated = EndpointEntity(
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
      await _configManager.saveEndpoint(updated);
      // 重新加载端点列表以更新 signal
      await _loadEndpoints();
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 重新排序端点
  Future<void> reorderEndpoints(int oldIndex, int newIndex) async {
    ensureNotDisposed();

    final items = List<EndpointEntity>.from(endpoints.value);

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
        final updated = EndpointEntity(
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
      // 重新加载端点列表以更新 signal
      await _loadEndpoints();
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 清空所有端点
  Future<void> clearAllEndpoints() async {
    ensureNotDisposed();

    try {
      await _configManager.clearAllEndpoints();
      // 重新加载端点列表以更新 signal
      await _loadEndpoints();
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  // =========================
  // 辅助方法
  // =========================

  /// 根据 ID 获取端点
  EndpointEntity? getEndpointById(String id) {
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
