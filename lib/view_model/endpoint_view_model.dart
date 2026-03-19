import 'dart:async';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals.dart';
import 'package:uuid/uuid.dart';

class EndpointViewModel {
  final _endpointRepository = EndpointRepository(Database.instance);
  final Uuid _uuid = const Uuid();
  Timer? _circuitBreakerSyncTimer;

  // 初始化空列表
  final endpoints = listSignal<EndpointEntity>([]);

  /// 断路中的端点 ID 集合（纯内存状态）
  final forbiddenEndpointIds = setSignal<String>({});

  // 使用 getter 来安全地访问 enabledEndpoints
  List<EndpointEntity> get enabledEndpoints {
    return endpoints.value.where((e) => e.enabled).toList();
  }

  final shadPopoverController = ShadPopoverController();

  Future<void> initSignals() async {
    _ensureCircuitBreakerSyncStarted();
    await _loadEndpoints();
  }

  /// 标记端点为断路中
  void markForbidden(String endpointId) {
    forbiddenEndpointIds.add(endpointId);
  }

  /// 移除端点的断路标记
  void markRestored(String endpointId) {
    forbiddenEndpointIds.remove(endpointId);
  }

  Future<void> addEndpoint({
    required String name,
    String? note,
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
    // 计算新的 weight 值：当前列表数量 + 1（作为最后一个）
    final newWeight = endpoints.value.length + 1;

    final endpoint = EndpointEntity(
      id: _uuid.v4(),
      name: name,
      note: note,
      weight: newWeight,
      enabled: true,
      anthropicAuthToken: anthropicAuthToken,
      anthropicBaseUrl: anthropicBaseUrl,
      anthropicModel: anthropicModel,
      anthropicSmallFastModel: anthropicSmallFastModel,
      anthropicDefaultHaikuModel: anthropicDefaultHaikuModel,
      anthropicDefaultSonnetModel: anthropicDefaultSonnetModel,
      anthropicDefaultOpusModel: anthropicDefaultOpusModel,
    );
    await _endpointRepository.insert(endpoint);
    await _loadEndpoints();
  }

  Future<void> deleteEndpoint(String id) async {
    await _endpointRepository.delete(id);
    forbiddenEndpointIds.remove(id);
    // 清理断路器实例，避免内存泄漏
    final homeViewModel = GetIt.instance.get<HomeViewModel>();
    homeViewModel.removeCircuitBreaker(id);
    await _loadEndpoints();
  }

  /// 重置指定端点的断路器
  Future<void> resetCircuitBreaker(String id) async {
    final homeViewModel = GetIt.instance.get<HomeViewModel>();
    homeViewModel.resetCircuitBreaker(id);
  }

  Future<void> toggleEnabled(String id) async {
    final endpoint = endpoints.value.firstWhere((e) => e.id == id);
    final updated = endpoint.copyWith(enabled: !endpoint.enabled);
    await _endpointRepository.update(updated);
    await _loadEndpoints();
    // 重新启用端点时，重置断路器状态并清除 UI 断路标记
    if (!endpoint.enabled && updated.enabled) {
      resetCircuitBreaker(id);
    }
  }

  Future<void> updateEndpoint(EndpointEntity endpoint) async {
    await _endpointRepository.update(endpoint);
    await _loadEndpoints();
  }

  Future<void> _loadEndpoints() async {
    final allEndpoints = await _endpointRepository.getAll();
    endpoints.value = allEndpoints;
    // 通知代理服务器端点列表已更新
    _notifyProxyServer();
    _syncForbiddenEndpointIds();
  }

  /// 通知代理服务器端点列表已更新
  void _notifyProxyServer() {
    final homeViewModel = GetIt.instance.get<HomeViewModel>();
    final enabled = endpoints.value.where((e) => e.enabled).toList();
    homeViewModel.updateProxyEndpoints(enabled);
  }

  void _ensureCircuitBreakerSyncStarted() {
    _circuitBreakerSyncTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _syncForbiddenEndpointIds(),
    );
  }

  void _syncForbiddenEndpointIds() {
    final homeViewModel = GetIt.instance.get<HomeViewModel>();
    final endpointIds = endpoints.value.map((e) => e.id);
    final openEndpointIds = homeViewModel.getOpenCircuitBreakerEndpointIds(
      endpointIds,
    );

    if (_setEquals(forbiddenEndpointIds.value, openEndpointIds)) {
      return;
    }

    forbiddenEndpointIds.value = openEndpointIds;
  }

  bool _setEquals(Set<String> left, Set<String> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (final value in left) {
      if (!right.contains(value)) return false;
    }
    return true;
  }

  /// 重新排序端点列表并更新 weight 字段
  Future<void> reorderEndpoints(int oldIndex, int newIndex) async {
    final currentEndpoints = List<EndpointEntity>.from(endpoints.value);

    // 如果目标位置在原位置之前，调整索引
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    // 移动元素
    final movedEndpoint = currentEndpoints.removeAt(oldIndex);
    currentEndpoints.insert(newIndex, movedEndpoint);

    // 重新分配 weight 值（从1开始，按顺序递增）
    final reorderedEndpoints = currentEndpoints.asMap().entries.map((entry) {
      final index = entry.key;
      final endpoint = entry.value;
      return endpoint.copyWith(weight: index + 1);
    }).toList();

    // 批量更新数据库
    for (final endpoint in reorderedEndpoints) {
      await _endpointRepository.update(endpoint);
    }

    // 重新加载端点列表
    await _loadEndpoints();
  }
}
