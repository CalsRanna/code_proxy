import 'dart:async';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/service/proxy_server_controller.dart';
import 'package:signals/signals.dart';
import 'package:uuid/uuid.dart';

class EndpointViewModel {
  EndpointViewModel({
    required EndpointRepository repository,
    required ProxyServerController proxy,
  }) : _endpointRepository = repository,
       _proxy = proxy;

  final EndpointRepository _endpointRepository;
  final ProxyServerController _proxy;
  StreamSubscription<void>? _circuitBreakerSubscription;
  final Uuid _uuid = const Uuid();
  Timer? _circuitBreakerSyncTimer;

  // 初始化空列表
  final endpoints = listSignal<EndpointEntity>([]);

  /// 断路中的端点 ID 集合（纯内存状态）
  final forbiddenEndpointIds = setSignal<String>({});

  Future<void> initSignals() async {
    _ensureCircuitBreakerSyncStarted();
    await _loadEndpoints();
  }

  Future<void> addEndpoint({
    required String name,
    String? note,
    String? authToken,
    String? baseUrl,
    String? haikuModel,
    String? sonnetModel,
    String? opusModel,
    String? fableModel,
    EndpointAuthMode authMode = EndpointAuthMode.preserve,
    EndpointApiFormat apiFormat = EndpointApiFormat.anthropic,
  }) async {
    // 按当前顺序重编，清理删除后的空隙和旧版已产生的重复权重。
    final current = List<EndpointEntity>.of(endpoints.value);
    for (final (index, endpoint) in current.indexed) {
      if (endpoint.weight != index + 1) {
        await _endpointRepository.update(endpoint.copyWith(weight: index + 1));
      }
    }
    final newWeight = current.length + 1;

    final endpoint = EndpointEntity(
      id: _uuid.v4(),
      name: name,
      note: note,
      weight: newWeight,
      enabled: true,
      authMode: authMode,
      apiFormat: apiFormat,
      authToken: authToken,
      baseUrl: baseUrl,
      haikuModel: haikuModel,
      sonnetModel: sonnetModel,
      opusModel: opusModel,
      fableModel: fableModel,
    );
    await _endpointRepository.insert(endpoint);
    await _loadEndpoints();
  }

  Future<void> deleteEndpoint(String id) async {
    await _endpointRepository.delete(id);
    forbiddenEndpointIds.remove(id);
    // 清理断路器实例，避免内存泄漏
    _proxy.removeCircuitBreaker(id);
    await _loadEndpoints();
  }

  /// 重置指定端点的断路器
  Future<void> resetCircuitBreaker(String id) async {
    _proxy.resetCircuitBreaker(id);
  }

  Future<void> toggleEnabled(String id) async {
    final matching = endpoints.value.where((e) => e.id == id);
    if (matching.isEmpty) return;
    final endpoint = matching.first;
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
    final enabled = endpoints.value.where((e) => e.enabled).toList();
    _proxy.updateProxyEndpoints(enabled);
  }

  void _ensureCircuitBreakerSyncStarted() {
    _circuitBreakerSubscription ??= _proxy.circuitBreakerChanges.listen(
      (_) => _syncForbiddenEndpointIds(),
    );
    _circuitBreakerSyncTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _syncForbiddenEndpointIds(),
    );
  }

  void _syncForbiddenEndpointIds() {
    final endpointIds = endpoints.value.map((e) => e.id);
    final openEndpointIds = _proxy.getOpenCircuitBreakerEndpointIds(
      endpointIds,
    );

    if (_setEquals(forbiddenEndpointIds.value, openEndpointIds)) {
      return;
    }

    forbiddenEndpointIds.value = openEndpointIds;
  }

  void dispose() {
    _circuitBreakerSubscription?.cancel();
    _circuitBreakerSyncTimer?.cancel();
  }

  bool _setEquals(Set<String> left, Set<String> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (final value in left) {
      if (!right.contains(value)) return false;
    }
    return true;
  }

  /// 按拖拽后的顺序重排端点并持久化 weight。
  ///
  /// 排序包回调给出的是重排后的完整列表，而不是 ReorderableListView 的
  /// (oldIndex, newIndex) 下标对。先更新内存 signal，让松手后的回弹动画
  /// 立刻落在新位置，再逐条写库。
  Future<void> reorderEndpointsByOrder(List<EndpointEntity> ordered) async {
    final current = List<EndpointEntity>.of(endpoints.value);
    final byId = {for (final endpoint in current) endpoint.id: endpoint};

    // 只按 id 认顺序，实体以上一帧的当前列表为准，避免拖拽期间发生的
    // 列表刷新被旧实例覆盖。
    final reordered = <EndpointEntity>[];
    for (final item in ordered) {
      final endpoint = byId.remove(item.id);
      if (endpoint == null) return;
      reordered.add(endpoint);
    }
    if (byId.isNotEmpty) return;

    var changed = false;
    final updated = <EndpointEntity>[];
    for (final (index, endpoint) in reordered.indexed) {
      final weight = index + 1;
      if (endpoint.weight == weight) {
        updated.add(endpoint);
      } else {
        changed = true;
        updated.add(endpoint.copyWith(weight: weight));
      }
    }
    if (!changed) return;

    endpoints.value = updated;
    _notifyProxyServer();

    final previousWeights = {
      for (final endpoint in current) endpoint.id: endpoint.weight,
    };
    for (final endpoint in updated) {
      if (previousWeights[endpoint.id] == endpoint.weight) continue;
      await _endpointRepository.update(endpoint);
    }
  }
}
