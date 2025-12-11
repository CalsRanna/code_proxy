import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals.dart';
import 'package:uuid/uuid.dart';
import 'base_view_model.dart';

/// 端点管理 ViewModel
/// 负责端点的 CRUD 操作
class EndpointsViewModel extends BaseViewModel {
  final EndpointRepository _endpointRepository;
  final Uuid _uuid = const Uuid();

  /// 全局共享的端点列表 signal（所有 ViewModel 实例共享）
  /// 使用 static 确保跨实例共享状态
  static final endpoints = listSignal<EndpointEntity>([]);

  /// 响应式状态
  final isLoading = signal(false);
  final errorMessage = signal<String?>(null);
  final searchQuery = signal('');

  final shadPopoverController = ShadPopoverController();

  /// 过滤后的端点列表（根据搜索查询）
  late final filteredEndpoints = computed(() {
    final query = searchQuery.value.toLowerCase();
    if (query.isEmpty) return endpoints.value;

    return endpoints.value.where((endpoint) {
      return endpoint.name.toLowerCase().contains(query) ||
          (endpoint.anthropicBaseUrl?.toLowerCase().contains(query) ?? false) ||
          (endpoint.note?.toLowerCase().contains(query) ?? false);
    }).toList();
  });

  EndpointsViewModel({required EndpointRepository endpointRepository})
      : _endpointRepository = endpointRepository;

  /// 初始化
  Future<void> init() async {
    ensureNotDisposed();
    await _loadEndpoints();
  }

  /// 从数据库加载端点列表
  Future<void> _loadEndpoints() async {
    ensureNotDisposed();
    try {
      final data = await _endpointRepository.getAll();
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
    String? note,
    int weight = 1,
    String? anthropicAuthToken,
    String? anthropicBaseUrl,
    int? apiTimeoutMs,
    String? anthropicModel,
    String? anthropicSmallFastModel,
    String? anthropicDefaultHaikuModel,
    String? anthropicDefaultSonnetModel,
    String? anthropicDefaultOpusModel,
    bool claudeCodeDisableNonessentialTraffic = false,
  }) async {
    ensureNotDisposed();

    final now = DateTime.now().millisecondsSinceEpoch;
    final endpoint = EndpointEntity(
      id: _uuid.v4(),
      name: name,
      note: note,
      weight: weight,
      enabled: true,
      createdAt: now,
      updatedAt: now,
      anthropicAuthToken: anthropicAuthToken,
      anthropicBaseUrl: anthropicBaseUrl,
      apiTimeoutMs: apiTimeoutMs,
      anthropicModel: anthropicModel,
      anthropicSmallFastModel: anthropicSmallFastModel,
      anthropicDefaultHaikuModel: anthropicDefaultHaikuModel,
      anthropicDefaultSonnetModel: anthropicDefaultSonnetModel,
      anthropicDefaultOpusModel: anthropicDefaultOpusModel,
      claudeCodeDisableNonessentialTraffic:
          claudeCodeDisableNonessentialTraffic,
    );

    try {
      await _endpointRepository.insert(endpoint);
      await _loadEndpoints();
    } catch (e) {
      errorMessage.value = e.toString();
      rethrow;
    }
  }

  /// 更新端点
  Future<void> updateEndpoint(EndpointEntity endpoint) async {
    ensureNotDisposed();

    final updated = endpoint.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      await _endpointRepository.update(updated);
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
      await _endpointRepository.delete(id);
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
    final updated = endpoint.copyWith(
      enabled: !endpoint.enabled,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      await _endpointRepository.update(updated);
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
      await _endpointRepository.clearAll();
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

  @override
  void dispose() {
    shadPopoverController.dispose();

    // 清理所有信号
    isLoading.dispose();
    searchQuery.dispose();

    super.dispose();
  }
}
