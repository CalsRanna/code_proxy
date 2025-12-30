import 'dart:async';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_log_handler.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_service.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';
import 'package:code_proxy/util/window_util.dart';
import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:get_it/get_it.dart';
import 'package:signals/signals.dart';

class HomeViewModel {
  final selectedIndex = signal<int>(0);

  ProxyServerService? _proxyServer;
  StreamSubscription<WindowEvent>? _subscription;
  final ProxyServerLogHandler _requestLogger = ProxyServerLogHandler.create();
  final RequestLogRepository _requestLogRepository = RequestLogRepository(
    Database.instance,
  );
  final EndpointRepository _endpointRepository = EndpointRepository(
    Database.instance,
  );

  /// 处理端点恢复事件（临时禁用到期后自动恢复）
  Future<void> handleEndpointRestored(EndpointEntity endpoint) async {
    LoggerUtil.instance.i(
      'Endpoint ${endpoint.name} has been automatically restored from temporary disable',
    );

    // 刷新端点列表 UI
    try {
      final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
      await endpointViewModel.initSignals();
    } catch (e) {
      LoggerUtil.instance.e('Failed to refresh endpoint list: $e');
    }
  }

  /// 处理端点不可用事件（重试用尽后触发）
  Future<void> handleEndpointUnavailable(EndpointEntity endpoint) async {
    LoggerUtil.instance.w(
      'Endpoint ${endpoint.name} exhausted retries, triggering temporary disable',
    );

    // 获取配置以获取临时禁用时长
    final instance = SharedPreferenceUtil.instance;
    final config = ProxyServerConfig(
      address: '127.0.0.1',
      port: await instance.getPort(),
      maxRetries: await instance.getMaxRetries(),
      apiTimeoutMs: await instance.getApiTimeout(),
    );

    // 触发临时禁用
    await _endpointRepository.forbid(
      endpoint.id,
      config.defaultTempDisableDurationMs,
    );

    LoggerUtil.instance.i(
      'Endpoint ${endpoint.name} temporarily disabled for '
      '${config.defaultTempDisableDurationMs ~/ 60000} minutes',
    );

    // 刷新端点列表以更新状态
    try {
      final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
      endpointViewModel.initSignals();
    } catch (e) {
      // 忽略获取 ViewModel 的错误
    }
  }

  Future<void> handleRequestCompleted(
    EndpointEntity endpoint,
    ProxyServerRequest request,
    ProxyServerResponse response,
  ) async {
    // 1. 构建数据库日志对象（使用现有的 LogHandler）
    final log = _requestLogger.buildRequestLog(
      endpoint: endpoint,
      request: request,
      response: response,
    );

    // 2. 插入数据库
    await _requestLogRepository.insert(log);

    // 3. 刷新请求日志页面
    try {
      final logViewModel = GetIt.instance.get<RequestLogViewModel>();
      logViewModel.loadLogs();
    } catch (e) {
      // 忽略获取 ViewModel 的错误（可能在某些情况下 ViewModel 还未初始化）
    }
  }

  Future<void> initSignals() async {
    _autoStartServer();
    _subscription ??= WindowUtil.instance.stream.listen((event) {
      if (event == WindowEvent.shown && selectedIndex.value == 0) {
        final dashboardViewModel = GetIt.instance.get<DashboardViewModel>();
        dashboardViewModel.refreshData();
      }
    });
  }

  /// 重启代理服务器（用于端口变更等配置修改）
  Future<void> restartProxyServer(int newPort) async {
    await _proxyServer?.stop();
    _proxyServer = null;
    await ClaudeCodeSettingService().updateProxySetting();
    final instance = SharedPreferenceUtil.instance;
    final maxRetries = await instance.getMaxRetries();
    final apiTimeout = await instance.getApiTimeout();
    final config = ProxyServerConfig(
      address: '127.0.0.1',
      port: newPort,
      maxRetries: maxRetries,
      apiTimeoutMs: apiTimeout,
    );
    _proxyServer = ProxyServerService(
      config: config,
      onRequestCompleted: handleRequestCompleted,
      onEndpointUnavailable: handleEndpointUnavailable,
      onEndpointRestored: handleEndpointRestored,
    );
    await _proxyServer?.start();
    final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
    final enabledEndpoints = endpointViewModel.enabledEndpoints;
    _proxyServer?.endpoints = enabledEndpoints;
  }

  Future<void> toggleEndpointEnabled(String id) async {
    final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
    final endpoints = endpointViewModel.endpoints.value;
    final endpoint = endpoints.firstWhere((e) => e.id == id);
    final updated = endpoint.copyWith(enabled: !endpoint.enabled);
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
    if (index == 5 && previousIndex != 5) {
      final settingViewModel = GetIt.instance.get<SettingViewModel>();
      settingViewModel.getSqliteFileSize();
    }
  }

  Future<void> _autoStartServer() async {
    var instance = SharedPreferenceUtil.instance;
    final port = await instance.getPort();
    final maxRetries = await instance.getMaxRetries();
    final apiTimeout = await instance.getApiTimeout();

    final config = ProxyServerConfig(
      address: '127.0.0.1',
      port: port,
      maxRetries: maxRetries,
      apiTimeoutMs: apiTimeout,
    );
    await ClaudeCodeSettingService().updateProxySetting();
    _proxyServer ??= ProxyServerService(
      config: config,
      onRequestCompleted: handleRequestCompleted,
      onEndpointUnavailable: handleEndpointUnavailable,
      onEndpointRestored: handleEndpointRestored,
    );
    await _proxyServer?.start();
    final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
    final enabledEndpoints = endpointViewModel.enabledEndpoints;
    _proxyServer?.endpoints = enabledEndpoints;
  }
}
