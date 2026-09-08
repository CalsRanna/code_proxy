import 'dart:async';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_client_settings_service.dart';
import 'package:code_proxy/service/proxy_request_log_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_service.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/notification_util.dart';
import 'package:code_proxy/util/shared_preference_util.dart';

typedef ProxyServerFactory =
    ProxyServerService Function({
      required ProxyServerConfig config,
      required String authToken,
      void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
      onRequestCompleted,
      void Function(EndpointEntity)? onEndpointUnavailable,
      void Function(EndpointEntity)? onEndpointRestored,
    });

/// 持有代理运行状态；页面只提交端点和配置变更，不参与监听与回滚。
class ProxyServerController {
  ProxyServerController({
    required SharedPreferenceUtil preferences,
    required ProxyClientSettingsService clientSettings,
    required ProxyRequestLogService requestLogs,
    required NotificationUtil notifications,
    ProxyServerFactory createServer = ProxyServerService.new,
  }) : _preferences = preferences,
       _clientSettings = clientSettings,
       _requestLogs = requestLogs,
       _notifications = notifications,
       _createServer = createServer;

  final SharedPreferenceUtil _preferences;
  final ProxyClientSettingsService _clientSettings;
  final ProxyRequestLogService _requestLogs;
  final NotificationUtil _notifications;
  final ProxyServerFactory _createServer;
  final _circuitBreakerChanges = StreamController<void>.broadcast();
  ProxyServerService? _proxyServer;
  List<EndpointEntity> _endpoints = [];

  Stream<void> get circuitBreakerChanges => _circuitBreakerChanges.stream;

  Future<void> start() async {
    _proxyServer = await _startConfiguredServer();
  }

  Future<void> restartProxyServer() async {
    final oldServer = _proxyServer;
    await oldServer?.stop();
    _proxyServer = null;
    try {
      await start();
    } catch (error, stackTrace) {
      if (oldServer != null) {
        try {
          await oldServer.start();
          _proxyServer = oldServer;
          oldServer.endpoints = _endpoints;
        } catch (restoreError) {
          LoggerUtil.instance.e(
            'Failed to restore proxy server on old port: $restoreError',
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<ProxyServerService> _startConfiguredServer() async {
    ProxyServerService? server;
    try {
      final authToken = await _preferences.getOrCreateProxyAuthToken();
      server = await _startServerWithPortScan();
      server.endpoints = _endpoints;
      final port = server.boundPort;
      if (port == null) {
        throw StateError('Proxy server is running but bound port is unknown');
      }
      // 监听成功后才改写客户端配置，并持久化设置页需要的实际端口。
      await _clientSettings.update(authToken: authToken, port: port);
      await _preferences.setPort(port);
      // 写配置期间也可能发生端点编辑，交接时使用最新列表。
      server.endpoints = _endpoints;
      return server;
    } catch (error, stackTrace) {
      try {
        await server?.stop();
      } catch (stopError) {
        LoggerUtil.instance.e('Failed to stop new proxy server: $stopError');
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<ProxyServerService> _startServerWithPortScan() async {
    final preferredPort = await _preferences.getPort();
    final apiTimeout = await _preferences.getApiTimeout();
    final cbThreshold = await _preferences.getCircuitBreakerFailureThreshold();
    final cbRecovery = await _preferences.getCircuitBreakerRecoveryTimeout();
    final authToken = await _preferences.getOrCreateProxyAuthToken();
    const maxAttempts = 100;
    if (preferredPort < 1 || preferredPort > 65535) {
      throw StateError('Invalid preferred port: $preferredPort');
    }
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final port = preferredPort + attempt;
      if (port > 65535) break;
      final server = _createServer(
        config: ProxyServerConfig(
          address: '127.0.0.1',
          port: port,
          apiTimeoutMs: apiTimeout,
          circuitBreakerFailureThreshold: cbThreshold,
          circuitBreakerRecoveryTimeoutMs: cbRecovery,
        ),
        authToken: authToken,
        onRequestCompleted: _requestLogs.record,
        onEndpointUnavailable: _handleEndpointUnavailable,
        onEndpointRestored: _handleEndpointRestored,
      );
      try {
        await server.start();
        if (port != preferredPort) {
          LoggerUtil.instance.i(
            'Preferred port $preferredPort is unavailable, proxy server started on port $port',
          );
        }
        return server;
      } on SocketException catch (error) {
        lastError = error;
        LoggerUtil.instance.w(
          'Port $port is unavailable (${error.message}), trying next port',
        );
      }
    }
    throw lastError ??
        StateError(
          'No available port in range $preferredPort-${preferredPort + maxAttempts - 1}',
        );
  }

  void updateProxyEndpoints(List<EndpointEntity> endpoints) {
    _endpoints = List.of(endpoints);
    _proxyServer?.endpoints = _endpoints;
  }

  Set<String> getOpenCircuitBreakerEndpointIds(Iterable<String> ids) =>
      _proxyServer?.getOpenCircuitBreakerEndpointIds(ids) ?? {};

  void resetCircuitBreaker(String id) {
    _proxyServer?.resetCircuitBreaker(id);
    _circuitBreakerChanges.add(null);
  }

  void removeCircuitBreaker(String id) =>
      _proxyServer?.removeCircuitBreaker(id);

  void _handleEndpointRestored(EndpointEntity endpoint) {
    LoggerUtil.instance.i(
      'Endpoint ${endpoint.name} has been automatically restored',
    );
    _notifications.showEndpointRestoredNotification(
      endpointName: endpoint.name,
    );
    _circuitBreakerChanges.add(null);
  }

  void _handleEndpointUnavailable(EndpointEntity endpoint) {
    LoggerUtil.instance.w('Endpoint ${endpoint.name} circuit breaker opened');
    final openIds = getOpenCircuitBreakerEndpointIds(
      _endpoints.map((e) => e.id),
    );
    final available = _endpoints.where((e) => !openIds.contains(e.id));
    if (available.isNotEmpty) {
      _notifications.showFailoverNotification(toEndpoint: available.first.name);
    }
    _circuitBreakerChanges.add(null);
  }

  Future<void> dispose() async {
    await _proxyServer?.stop();
    await _circuitBreakerChanges.close();
  }
}
