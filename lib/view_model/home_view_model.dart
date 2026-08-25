import 'dart:async';
import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/default_model_mapper_entity.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/claude_code_audit_service.dart';
import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/service/claude_code_setting_service.dart';
import 'package:code_proxy/service/claude_desktop_setting_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/service/proxy_settings_snapshot.dart';
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

  /// 请求日志标签页在 home_page 导航中的序号（'概览', '端点', '请求', '设置'）。
  static const _requestLogTabIndex = 2;

  /// 请求日志刷新的节流窗口。
  static const _logRefreshInterval = Duration(milliseconds: 500);

  Timer? _logRefreshTimer;
  bool _logRefreshPending = false;

  /// 请求日志页刷新，leading-edge 节流：窗口内第一次立即执行，窗口期内的
  /// 后续触发合并成窗口结束时的一次补刷。
  ///
  /// 高频请求下逐条刷新会让 COUNT(*) + SELECT 持续占用主 isolate。
  void _scheduleLogRefresh() {
    if (_logRefreshTimer?.isActive ?? false) {
      _logRefreshPending = true;
      return;
    }
    _refreshLogsNow();
    _logRefreshTimer = Timer(_logRefreshInterval, () {
      final pending = _logRefreshPending;
      _logRefreshPending = false;
      if (pending) _scheduleLogRefresh();
    });
  }

  void _refreshLogsNow() {
    // 用户不在请求页时不查库：切回该页时 updateSelectedIndex 会调用
    // initSignals() 重新加载，不会漏数据。
    if (selectedIndex.value != _requestLogTabIndex) return;
    try {
      GetIt.instance.get<RequestLogViewModel>().loadLogs();
    } catch (e) {
      // 忽略获取 ViewModel 的错误（启动早期可能尚未注册）
    }
  }

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

    // 3. 刷新请求日志页面 —— 仅在用户正停留在该页时，且做节流。
    //
    // 此前每条请求都无条件 loadLogs()（一次 COUNT(*) 加一次
    // SELECT ... LIMIT 50），不管用户在哪个标签页，与 UI 渲染抢同一个
    // isolate。
    _scheduleLogRefresh();

    // 4. 异步写入审计日志文件
    if (response.responseBody != null) {
      ClaudeCodeAuditService.instance.writeAuditLog(
        id: log.id,
        request: request.body,
        response: response.responseBody!,
        originalRequest: request.originalBody,
        rawResponse: response.rawResponseBody,
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

  /// 重启代理服务器（用于 API 超时、熔断阈值等配置修改）
  ///
  /// 顺序：先在新端口监听成功，再改写 Claude Code 配置。
  /// 启动失败时恢复旧服务并抛出异常，保证 Claude Code 不会指向
  /// 一个不存在的服务；调用方负责向用户展示错误。
  Future<void> restartProxyServer() async {
    final oldServer = _proxyServer;
    await oldServer?.stop();
    _proxyServer = null;

    final instance = SharedPreferenceUtil.instance;
    final authToken = await instance.getOrCreateProxyAuthToken();

    ProxyServerService? newServer;
    try {
      newServer = await _startServerWithPortScan();
      final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
      newServer.endpoints = endpointViewModel.enabledEndpoints;
      final boundPort = newServer.boundPort;
      if (boundPort == null) {
        throw StateError('Proxy server is running but bound port is unknown');
      }
      // 服务已就绪后再以跨文件事务改写 Claude 配置。
      await _writeProxySettings(authToken: authToken, port: boundPort);
      // 持久化实际绑定端口：无参 updateProxySetting()（设置页开关）依赖它
      // 把 Claude Code 指向正确端口。
      await instance.setPort(boundPort);
      _proxyServer = newServer;
    } catch (e, stackTrace) {
      // newServer 可能已经监听成功，也可能仅创建了出站 HttpClient。
      // 两种情况都必须关闭，才能安全地恢复旧服务。
      try {
        await newServer?.stop();
      } catch (stopError) {
        LoggerUtil.instance.e('Failed to stop new proxy server: $stopError');
      }
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
      Error.throwWithStackTrace(e, stackTrace);
    }
  }

  /// 启动代理服务器时的端口探测。
  ///
  /// 端口不再对用户暴露：从最近一次成功绑定的端口（默认 9000）开始，
  /// 被占用则顺延尝试下一个，返回第一个成功启动的服务器实例；
  /// 所有候选端口均不可用时抛出最后一次绑定错误。
  Future<ProxyServerService> _startServerWithPortScan() async {
    final instance = SharedPreferenceUtil.instance;
    final preferredPort = await instance.getPort();
    final apiTimeout = await instance.getApiTimeout();
    final cbThreshold = await instance.getCircuitBreakerFailureThreshold();
    final cbRecovery = await instance.getCircuitBreakerRecoveryTimeout();
    final authToken = await instance.getOrCreateProxyAuthToken();

    const maxAttempts = 100;
    if (preferredPort < 1 || preferredPort > 65535) {
      throw StateError('Invalid preferred port: $preferredPort');
    }

    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final port = preferredPort + attempt;
      if (port > 65535) break;
      final server = ProxyServerService(
        config: ProxyServerConfig(
          address: '127.0.0.1',
          port: port,
          apiTimeoutMs: apiTimeout,
          circuitBreakerFailureThreshold: cbThreshold,
          circuitBreakerRecoveryTimeoutMs: cbRecovery,
        ),
        authToken: authToken,
        onRequestCompleted: handleRequestCompleted,
        onEndpointUnavailable: handleEndpointUnavailable,
        onEndpointRestored: handleEndpointRestored,
      );
      try {
        await server.start();
        if (port != preferredPort) {
          LoggerUtil.instance.i(
            'Preferred port $preferredPort is unavailable, '
            'proxy server started on port $port',
          );
        }
        return server;
      } on SocketException catch (e) {
        lastError = e;
        LoggerUtil.instance.w(
          'Port $port is unavailable (${e.message}), trying next port',
        );
      }
    }
    throw lastError ??
        StateError(
          'No available port in range $preferredPort-'
          '${preferredPort + maxAttempts - 1}',
        );
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
    _logRefreshTimer?.cancel();
    _logRefreshTimer = null;
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
  Future<void> _writeProxySettings({
    required String authToken,
    required int port,
  }) async {
    final codeSettings = ClaudeCodeSettingService();
    final desktopSettings = ClaudeDesktopSettingService();
    final snapshot = await ProxySettingsSnapshot.capture([
      ...codeSettings.managedFilePaths,
      ...desktopSettings.managedFilePaths,
    ]);

    try {
      await codeSettings.updateProxySetting(authToken: authToken, port: port);
      await desktopSettings.updateProxySetting(
        authToken: authToken,
        port: port,
      );
    } catch (error, stackTrace) {
      try {
        await snapshot.restore();
      } catch (rollbackError) {
        throw ProxySettingsRollbackException(
          updateError: error,
          rollbackError: rollbackError,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _autoStartServer(BuildContext context) async {
    final instance = SharedPreferenceUtil.instance;
    final authToken = await instance.getOrCreateProxyAuthToken();

    ProxyServerService? server;
    try {
      server = await _startServerWithPortScan();
      final endpointViewModel = GetIt.instance.get<EndpointViewModel>();
      server.endpoints = endpointViewModel.enabledEndpoints;
      final boundPort = server.boundPort;
      if (boundPort == null) {
        throw StateError('Proxy server is running but bound port is unknown');
      }
      // 先监听成功再写 Claude Code 配置：所有候选端口均被占用时不能把
      // settings.json 指向一个不存在的服务。
      await _writeProxySettings(authToken: authToken, port: boundPort);
      await instance.setPort(boundPort);
      _proxyServer = server;
    } catch (e) {
      LoggerUtil.instance.e('Failed to start proxy server: $e');
      try {
        await server?.stop();
      } catch (stopError) {
        LoggerUtil.instance.e(
          'Failed to clean up proxy server after startup error: $stopError',
        );
      }
      _proxyServer = null;
      // Claude Code 配置保持原样，明确告知用户启动失败原因
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _showStartupErrorDialog(context, e);
        }
      });
    }
  }

  void _showStartupErrorDialog(BuildContext context, Object error) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('代理服务器启动失败'),
        description: Text(
          '无法启动代理服务器：\n$error\n\n'
          'Claude Code 的配置未被修改。请检查占用端口的程序并释放后重试。',
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
