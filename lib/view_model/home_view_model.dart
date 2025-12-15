import 'dart:async';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/services/claude_code_setting_service.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_service.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_log_handler.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals.dart';

class HomeViewModel {
  final selectedIndex = signal<int>(0);

  ProxyServerService? _proxyServer;
  final ProxyServerLogHandler _requestLogger = ProxyServerLogHandler.create();
  final RequestLogRepository _requestLogRepository = RequestLogRepository(
    Database.instance,
  );

  Future<void> handleRequestCompleted(
    EndpointEntity endpoint,
    ProxyServerRequest request,
    ProxyServerResponse response,
  ) async {
    // 使用 RequestLogger 解析数据并组装 RequestLog 对象
    final RequestLog log = _requestLogger.buildRequestLog(
      endpoint: endpoint,
      request: request,
      response: response,
    );

    // 插入数据库
    await _requestLogRepository.insert(log);

    // 刷新请求日志页面
    try {
      final logViewModel = GetIt.instance.get<RequestLogViewModel>();
      logViewModel.loadLogs();
    } catch (e) {
      // 忽略获取 ViewModel 的错误（可能在某些情况下 ViewModel 还未初始化）
    }
  }

  Future<void> initSignals() async {
    _autoStartServer();
  }

  /// 重启代理服务器（用于端口变更等配置修改）
  Future<void> restartProxyServer(int newPort) async {
    await _proxyServer?.stop();
    _proxyServer = null;
    await ClaudeCodeSettingService().updateProxySetting(newPort);
    final instance = SharedPreferenceUtil.instance;
    final maxRetries = await instance.getMaxRetries();
    final config = ProxyServerConfig(
      address: '127.0.0.1',
      port: newPort,
      maxRetries: maxRetries,
    );
    _proxyServer = ProxyServerService(
      config: config,
      onRequestCompleted: handleRequestCompleted,
    );
    await _proxyServer?.start();
    final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
    final endpoints = endpointViewModel.endpoints.value;
    _proxyServer?.endpoints = endpoints.where((e) => e.enabled).toList();
  }

  Future<void> toggleEndpointEnabled(String id) async {
    final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
    final endpoints = endpointViewModel.endpoints.value;
    final endpoint = endpoints.firstWhere((e) => e.id == id);
    final updated = endpoint.copyWith(
      enabled: !endpoint.enabled,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await endpointViewModel.updateEndpoint(updated);
    final enabledEndpoints = endpointViewModel.enabledEndpoints;
    _proxyServer?.endpoints = enabledEndpoints;
  }

  /// 更新代理服务器的端点列表
  void updateProxyEndpoints(List<EndpointEntity> enabledEndpoints) {
    _proxyServer?.endpoints = enabledEndpoints;
  }

  void updateSelectedIndex(int index) {
    final previousIndex = selectedIndex.value;
    selectedIndex.value = index;
    if (index == 0 && previousIndex != 0) {
      final dashboardViewModel = GetIt.instance.get<DashboardViewModel>();
      dashboardViewModel.refreshData();
    }
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
    final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
    var endpoints = endpointViewModel.endpoints.value;
    _proxyServer?.endpoints = endpoints.where((e) => e.enabled).toList();
  }
}
