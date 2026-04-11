import 'dart:async';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/claude_code_audit_service.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals.dart';

class HomeViewModel {
  final selectedIndex = signal<int>(0);

  ProxyServerService? _proxyServer;
  StreamSubscription<WindowEvent>? _subscription;
  final ProxyServerLogHandler _requestLogger = ProxyServerLogHandler.create();
  final RequestLogRepository _requestLogRepository = RequestLogRepository(
    Database.instance,
  );

  /// 处理端点恢复事件（断路器自动恢复）
  void handleEndpointRestored(EndpointEntity endpoint) {
    LoggerUtil.instance.i(
      'Endpoint ${endpoint.name} has been automatically restored',
    );

    try {
      final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
      endpointViewModel.markRestored(endpoint.id);
    } catch (e) {
      LoggerUtil.instance.e('Failed to update endpoint state: $e');
    }
  }

  /// 处理端点不可用事件（断路器打开后触发）
  Future<void> handleEndpointUnavailable(EndpointEntity endpoint) async {
    LoggerUtil.instance.w('Endpoint ${endpoint.name} circuit breaker opened');

    try {
      final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
      endpointViewModel.markForbidden(endpoint.id);
    } catch (e) {
      // 忽略获取 ViewModel 的错误
    }
  }

  /// 重置指定端点的断路器状态
  void resetCircuitBreaker(String endpointId) {
    _proxyServer?.resetCircuitBreaker(endpointId);

    try {
      final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
      endpointViewModel.markRestored(endpointId);
    } catch (e) {
      LoggerUtil.instance.e('Failed to update endpoint state: $e');
    }
  }

  /// 重置所有端点的断路器状态
  void resetAllCircuitBreakers() {
    _proxyServer?.resetAllCircuitBreakers();

    try {
      final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
      endpointViewModel.forbiddenEndpointIds.clear();
    } catch (e) {
      LoggerUtil.instance.e('Failed to update endpoint state: $e');
    }
  }

  /// 获取当前仍处于断路中的端点 ID
  Set<String> getOpenCircuitBreakerEndpointIds(Iterable<String> endpointIds) {
    return _proxyServer?.getOpenCircuitBreakerEndpointIds(endpointIds) ?? {};
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

    // 4. 异步写入审计日志文件
    if (response.responseBody != null) {
      ClaudeCodeAuditService.instance.writeAuditLog(
        id: log.id,
        request: request.body,
        response: response.responseBody!,
        requestHeaders: request.headers,
        forwardedHeaders: request.forwardedHeaders,
        responseHeaders: response.headers,
        forwardedResponseHeaders: response.forwardedHeaders,
      );
    }
  }

  Future<void> initSignals(BuildContext context) async {
    // 加载模型配置
    try {
      await ClaudeCodeModelConfigService.instance.load();
    } on ModelConfigException catch (e) {
      LoggerUtil.instance.e('模型配置加载失败: ${e.message}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showConfigErrorDialog(context, e.message);
      });
      // 配置错误时不启动代理服务器
      return;
    }

    ClaudeCodeAuditService.instance.cleanExpiredLogs();
    await ModelPricingService.instance.load();
    _autoStartServer();
    _subscription ??= WindowUtil.instance.stream.listen((event) {
      if (event == WindowEvent.shown && selectedIndex.value == 0) {
        final dashboardViewModel = GetIt.instance.get<DashboardViewModel>();
        dashboardViewModel.initSignals();
      }
    });
  }

  void _showConfigErrorDialog(BuildContext context, String error) {
    final configPath = ClaudeCodeModelConfigService.instance.getConfigPath();
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: Text('模型配置文件错误'),
        description: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 8),
            Text(error),
            SizedBox(height: 16),
            Text('配置文件路径:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    configPath,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                ShadIconButton.ghost(
                  icon: Icon(LucideIcons.copy, size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: configPath));
                    ShadToaster.of(
                      context,
                    ).show(ShadToast(title: Text('已复制配置文件路径')));
                  },
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              '请修改配置文件后重启应用',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          ShadButton(
            child: Text('确定'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 重启代理服务器（用于端口变更等配置修改）
  Future<void> restartProxyServer(int newPort) async {
    await _proxyServer?.stop();
    _proxyServer = null;
    await ClaudeCodeSettingService().updateProxySetting();
    final instance = SharedPreferenceUtil.instance;
    final apiTimeout = await instance.getApiTimeout();
    final cbThreshold = await instance.getCircuitBreakerFailureThreshold();
    final cbRecovery = await instance.getCircuitBreakerRecoveryTimeout();
    final config = ProxyServerConfig(
      address: '127.0.0.1',
      port: newPort,
      apiTimeoutMs: apiTimeout,
      circuitBreakerFailureThreshold: cbThreshold,
      circuitBreakerRecoveryTimeoutMs: cbRecovery,
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

  /// 移除端点的断路器实例（端点被删除时调用）
  void removeCircuitBreaker(String endpointId) {
    _proxyServer?.removeCircuitBreaker(endpointId);
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  void updateSelectedIndex(int index) {
    final previousIndex = selectedIndex.value;
    selectedIndex.value = index;
    if (index == 0 && previousIndex != 0) {
      final dashboardViewModel = GetIt.instance.get<DashboardViewModel>();
      dashboardViewModel.initSignals();
    }
    if (index == 1 && previousIndex != 1) {
      final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
      endpointViewModel.initSignals();
    }
    if (index == 2 && previousIndex != 2) {
      final logViewModel = GetIt.instance.get<RequestLogViewModel>();
      logViewModel.initSignals();
    }
    if (index == 3 && previousIndex != 3) {
      final settingViewModel = GetIt.instance.get<SettingViewModel>();
      settingViewModel.initSignals();
    }
  }

  Future<void> _autoStartServer() async {
    var instance = SharedPreferenceUtil.instance;
    final port = await instance.getPort();
    final apiTimeout = await instance.getApiTimeout();
    final cbThreshold = await instance.getCircuitBreakerFailureThreshold();
    final cbRecovery = await instance.getCircuitBreakerRecoveryTimeout();

    final config = ProxyServerConfig(
      address: '127.0.0.1',
      port: port,
      apiTimeoutMs: apiTimeout,
      circuitBreakerFailureThreshold: cbThreshold,
      circuitBreakerRecoveryTimeoutMs: cbRecovery,
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
