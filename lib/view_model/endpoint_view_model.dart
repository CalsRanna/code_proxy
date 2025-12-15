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

  // 初始化空列表
  final endpoints = listSignal<EndpointEntity>([]);

  // 使用 getter 来安全地访问 enabledEndpoints
  List<EndpointEntity> get enabledEndpoints {
    return endpoints.value.where((e) => e.enabled && !e.forbidden).toList();
  }

  final shadPopoverController = ShadPopoverController();

  Future<void> initSignals() async {
    await _checkAndRestoreExpiredForAllEndpoints();
    await _loadEndpoints();
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
    await _loadEndpoints();
  }

  Future<void> toggleEnabled(String id) async {
    final endpoint = endpoints.value.firstWhere((e) => e.id == id);
    final updated = endpoint.copyWith(enabled: !endpoint.enabled);
    await _endpointRepository.update(updated);
    await _loadEndpoints();
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
  }

  /// 检查并恢复所有过期的临时禁用端点
  Future<void> _checkAndRestoreExpiredForAllEndpoints() async {
    final allEndpoints = await _endpointRepository.getAll();
    for (final endpoint in allEndpoints) {
      if (endpoint.forbidden && endpoint.forbiddenUntil != null) {
        final restored = await _endpointRepository.checkAndRestoreExpired(
          endpoint.id,
        );
        if (restored) {
          // 这里可以添加日志记录
        }
      }
    }
  }

  /// 通知代理服务器端点列表已更新
  void _notifyProxyServer() {
    final homeViewModel = GetIt.instance.get<HomeViewModel>();
    final enabled = endpoints.value.where((e) => e.enabled).toList();
    homeViewModel.updateProxyEndpoints(enabled);
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
