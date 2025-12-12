import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals.dart';
import 'package:uuid/uuid.dart';

class EndpointsViewModel {
  final _endpointRepository = EndpointRepository(Database.instance);
  final Uuid _uuid = const Uuid();

  final endpoints = listSignal<EndpointEntity>([]);
  late final enabledEndpoints = computed(
    () => endpoints.value.where((e) => e.enabled).toList(),
  );

  final shadPopoverController = ShadPopoverController();

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
    await _endpointRepository.insert(endpoint);
    await _loadEndpoints();
  }

  Future<void> deleteEndpoint(String id) async {
    await _endpointRepository.delete(id);
    await _loadEndpoints();
  }

  Future<void> initSignals() async {
    await _loadEndpoints();
  }

  Future<void> toggleEnabled(String id) async {
    final endpoint = endpoints.value.firstWhere((e) => e.id == id);
    final updated = endpoint.copyWith(
      enabled: !endpoint.enabled,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _endpointRepository.update(updated);
    await _loadEndpoints();
  }

  Future<void> updateEndpoint(EndpointEntity endpoint) async {
    final updated = endpoint.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _endpointRepository.update(updated);
    await _loadEndpoints();
  }

  Future<void> _loadEndpoints() async {
    endpoints.value = await _endpointRepository.getAll();
  }
}
