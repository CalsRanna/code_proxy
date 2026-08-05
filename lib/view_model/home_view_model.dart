import 'dart:async';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/claude_code_audit_service.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/util/notification_util.dart';
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

    // 发送通知
    NotificationUtil.instance.showEndpointRestoredNotification(
      endpointName: endpoint.name,
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

    // 获取下一个可用端点作为故障转移目标
    final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
    final openIds = getOpenCircuitBreakerEndpointIds(
      endpointViewModel.enabledEndpoints.map((e) => e.id),
    );
    final availableEndpoints = endpointViewModel.enabledEndpoints
        .where((e) => !openIds.contains(e.id))
        .toList();

    // 发送通知（仅当存在备用端点时）
    if (availableEndpoints.isNotEmpty) {
      final nextEndpoint = availableEndpoints.first;
      NotificationUtil.instance.showFailoverNotification(
        toEndpoint: nextEndpoint.name,
      );
    }

    try {
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

    // 2. 插入数据库。日志写入失败不影响代理主流程（请求已转发完成），
    //    只记日志避免未处理异常使代理崩溃。
    try {
      await _requestLogRepository.insert(log);
    } catch (e) {
      LoggerUtil.instance.e('Failed to insert request log: $e');
      // 没有 log.id 则审计日志也无法归档，直接返回
      return;
    }

    // 3. 刷新请求日志页面（loadLogs 内部已有异常保护）
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
        if (!context.mounted) return;
        _showConfigErrorDialog(context, e.message);
      });
      // 配置错误时不启动代理服务器
      return;
    }

    ClaudeCodeAuditService.instance.cleanExpiredLogs();
    await ModelPricingService.instance.load();
    if (!context.mounted) return;
    await _autoStartServer(context);
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
  ///
  /// 顺序：先在新端口监听成功，再改写 Claude Code 配置。
  /// 启动失败时恢复旧服务并抛出异常，保证 Claude Code 不会指向
  /// 一个不存在的服务；调用方负责向用户展示错误。
  Future<void> restartProxyServer(int newPort) async {
    final oldServer = _proxyServer;
    await oldServer?.stop();
    _proxyServer = null;

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
    final newServer = ProxyServerService(
      config: config,
      onRequestCompleted: handleRequestCompleted,
      onEndpointUnavailable: handleEndpointUnavailable,
      onEndpointRestored: handleEndpointRestored,
    );

    try {
      // 先监听成功，失败则 settings.json 保持原样
      await newServer.start();
      _proxyServer = newServer;
      // 服务已就绪后再改写 Claude Code 配置
      await _writeProxySettings();
    } catch (e) {
      // 启动失败：尝试恢复旧服务，避免 Claude Code 悬空指向已停止的端口
      if (oldServer != null) {
        try {
          await oldServer.start();
          _proxyServer = oldServer;
        } catch (e2) {
          LoggerUtil.instance.e(
            'Failed to restore proxy server on old port: $e2',
          );
        }
      }
      rethrow;
    }

    final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
    final enabledEndpoints = endpointViewModel.enabledEndpoints;
    _proxyServer?.endpoints = enabledEndpoints;
  }

  Future<void> toggleEndpointEnabled(String id) async {
    final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
    final endpoints = endpointViewModel.endpoints.value;
    final matching = endpoints.where((e) => e.id == id);
    if (matching.isEmpty) return;
    final endpoint = matching.first;
    final updated = endpoint.copyWith(enabled: !endpoint.enabled);
    await endpointViewModel.updateEndpoint(updated);
    final enabledEndpoints = endpointViewModel.enabledEndpoints;
    _proxyServer?.endpoints = enabledEndpoints;
  }

  /// 更新代理服务器的端点列表
  void updateProxyEndpoints(List<EndpointEntity> enabledEndpoints) {
    final server = _proxyServer;
    if (server == null) {
      LoggerUtil.instance.w(
        'updateProxyEndpoints called but proxy server is not running, '
        'endpoint changes will not take effect until server restarts',
      );
      return;
    }
    server.endpoints = enabledEndpoints;
    LoggerUtil.instance.d(
      'Proxy server endpoints updated: ${enabledEndpoints.length} enabled',
    );
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

  /// 将 Claude Code / Claude Desktop 配置指向当前代理端口
  Future<void> _writeProxySettings() async {
    await ClaudeCodeSettingService().updateProxySetting();
    await ClaudeDesktopSettingService().updateProxySetting();
  }

  Future<void> _autoStartServer(BuildContext context) async {
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
    final server = ProxyServerService(
      config: config,
      onRequestCompleted: handleRequestCompleted,
      onEndpointUnavailable: handleEndpointUnavailable,
      onEndpointRestored: handleEndpointRestored,
    );

    try {
      // 先监听成功再写 Claude Code 配置：端口被占用时不能把
      // settings.json 指向一个不存在的服务。
      await server.start();
      _proxyServer = server;
      await _writeProxySettings();
    } catch (e) {
      LoggerUtil.instance.e('Failed to start proxy server: $e');
      _proxyServer = null;
      // Claude Code 配置保持原样，明确告知用户启动失败原因
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _showStartupErrorDialog(context, port, e);
        }
      });
      return;
    }

    final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
    final enabledEndpoints = endpointViewModel.enabledEndpoints;
    _proxyServer?.endpoints = enabledEndpoints;
  }

  void _showStartupErrorDialog(BuildContext context, int port, Object error) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('代理服务器启动失败'),
        description: Text(
          '无法在端口 $port 上启动代理服务器：\n$error\n\n'
          'Claude Code 的配置未被修改。请检查端口是否被其他程序占用，'
          '然后在设置中更换监听端口。',
        ),
        actions: [
          ShadButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
