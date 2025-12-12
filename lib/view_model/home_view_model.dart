import 'dart:async';
import 'dart:convert';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/services/claude_code_setting_service.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_service.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:code_proxy/view_model/logs_view_model.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals.dart';
import 'package:uuid/uuid.dart';

class HomeViewModel {
  final selectedIndex = signal<int>(0);

  ProxyServerService? _proxyServer;

  Future<void> handleRequestCompleted(
    EndpointEntity endpoint,
    ProxyServerRequest request,
    ProxyServerResponse response,
  ) async {
    final repository = RequestLogRepository(Database.instance);
    final success = response.statusCode >= 200 && response.statusCode < 300;
    String? model;
    int? inputTokens;
    int? outputTokens;

    if (request.body.isNotEmpty) {
      final requestJson = jsonDecode(request.body);
      if (requestJson is Map<String, dynamic>) {
        model = requestJson['model'] as String?;
      }
    }

    final contentType = response.headers['content-type'] ?? '';
    final isSSE = contentType.contains('text/event-stream');
    if (success && response.body.isNotEmpty) {
      if (isSSE) {
        final tokens = _parseSSETokens(response.body);
        inputTokens = tokens['input'];
        outputTokens = tokens['output'];
      } else {
        final responseJson = jsonDecode(response.body);
        if (responseJson is Map<String, dynamic>) {
          final usage = responseJson['usage'];
          if (usage is Map<String, dynamic>) {
            inputTokens = usage['input_tokens'] as int?;
            outputTokens = usage['output_tokens'] as int?;
          }
        }
      }
    }
    final log = RequestLog(
      id: const Uuid().v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      path: request.path,
      method: request.method,
      statusCode: response.statusCode,
      responseTime: response.responseTime,
      success: success,
      error: success
          ? null
          : (response.statusCode > 0
                ? 'HTTP ${response.statusCode}'
                : response.body),
      level: success ? LogLevel.info : LogLevel.error,
      header: request.headers,
      message: success
          ? 'Request completed successfully'
          : 'Request failed with status ${response.statusCode}',
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      rawHeader: jsonEncode(request.headers),
      rawRequest: request.body,
      rawResponse: response.body,
    );
    await repository.insert(log);
    final logViewModel = GetIt.instance.get<LogsViewModel>();
    logViewModel.loadLogs();
  }

  Future<void> initSignals() async {
    _autoStartServer();
  }

  Future<void> toggleEndpointEnabled(String id) async {
    final endpointViewModel = GetIt.instance.get<EndpointsViewModel>();
    final endpoints = endpointViewModel.endpoints.value;
    final endpoint = endpoints.firstWhere((e) => e.id == id);
    final updated = endpoint.copyWith(
      enabled: !endpoint.enabled,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    endpointViewModel.updateEndpoint(updated);
    final enabledEndpoints = endpointViewModel.enabledEndpoints.value;
    _proxyServer?.endpoints = enabledEndpoints;
  }

  void updateSelectedIndex(int index) {
    selectedIndex.value = index;
  }

  Future<void> _autoStartServer() async {
    var instance = SharedPreferenceUtil.instance;
    final port = await instance.getPort();
    final maxRetries = await instance.getMaxRetries();

    final config = ProxyServerConfig(
      address: '127.0.0.1',
      port: port,
      maxRetries: maxRetries,
    );
    await ClaudeCodeSettingService().updateProxySetting(port);
    _proxyServer ??= ProxyServerService(
      config: config,
      onRequestCompleted: handleRequestCompleted,
    );
    await _proxyServer?.start();
    final endpointViewModel = GetIt.instance.get<EndpointsViewModel>();
    var endpoints = endpointViewModel.endpoints.value;
    _proxyServer?.endpoints = endpoints.where((e) => e.enabled).toList();
  }

  Map<String, dynamic> _parseSSETokens(String sseBody) {
    int totalInput = 0;
    int totalOutput = 0;
    final lines = sseBody.split('\n');
    for (var line in lines) {
      if (line.startsWith('data: ')) {
        try {
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;
          final json = jsonDecode(jsonStr);
          if (json is Map<String, dynamic>) {
            final usage = json['usage'];
            if (usage is Map<String, dynamic>) {
              totalInput += (usage['input_tokens'] as int? ?? 0);
              totalOutput += (usage['output_tokens'] as int? ?? 0);
            }
          }
        } catch (_) {
          // 解析失败，跳过这一行
        }
      }
    }
    return {
      'input': totalInput > 0 ? totalInput : null,
      'output': totalOutput > 0 ? totalOutput : null,
    };
  }
}
