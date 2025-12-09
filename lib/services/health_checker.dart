import 'dart:async';
import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/model/health_status.dart';
import 'package:code_proxy/model/proxy_config.dart';
import 'package:http/http.dart' as http;

/// 健康检查器
/// 负责主动和被动健康检查
class HealthChecker {
  final ProxyConfig config;
  final List<Endpoint> Function() getEndpoints;

  /// 健康状态映射 (endpointId -> HealthStatus)
  final Map<String, HealthStatus> _healthStatuses = {};

  /// 主动健康检查定时器
  Timer? _activeCheckTimer;

  /// 自动恢复检查定时器
  Timer? _autoRecoverTimer;

  /// HTTP 客户端
  final http.Client _httpClient = http.Client();

  HealthChecker({required this.config, required this.getEndpoints});

  // =========================
  // 主动健康检查
  // =========================

  /// 启动主动健康检查
  void startActiveHealthCheck() {
    // 取消现有定时器
    stopActiveHealthCheck();

    // 立即执行一次健康检查
    _performActiveHealthCheck();

    // 启动定时器
    _activeCheckTimer = Timer.periodic(
      Duration(seconds: config.healthCheckInterval),
      (_) => _performActiveHealthCheck(),
    );

    // 启动自动恢复检查定时器（每30秒检查一次）
    _autoRecoverTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkAutoRecover(),
    );
  }

  /// 停止主动健康检查
  void stopActiveHealthCheck() {
    _activeCheckTimer?.cancel();
    _activeCheckTimer = null;
    _autoRecoverTimer?.cancel();
    _autoRecoverTimer = null;
  }

  /// 执行主动健康检查
  Future<void> _performActiveHealthCheck() async {
    final endpoints = getEndpoints();

    for (final endpoint in endpoints) {
      if (!endpoint.enabled) continue;

      await _checkEndpointHealth(endpoint);
    }
  }

  /// 检查单个端点的健康状态
  Future<void> _checkEndpointHealth(Endpoint endpoint) async {
    final url = Uri.parse(endpoint.url).replace(path: config.healthCheckPath);

    try {
      final response = await _httpClient
          .get(url)
          .timeout(Duration(seconds: config.healthCheckTimeout));

      // 2xx 和 3xx 状态码视为健康
      if (response.statusCode >= 200 && response.statusCode < 400) {
        _recordSuccess(endpoint.id);
      } else {
        _recordFailure(
          endpoint.id,
          'Health check failed: HTTP ${response.statusCode}',
        );
      }
    } on TimeoutException {
      _recordFailure(endpoint.id, 'Health check timeout');
    } catch (e) {
      _recordFailure(endpoint.id, 'Health check error: $e');
    }
  }

  /// 检查并执行自动恢复
  void _checkAutoRecover() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entriesToRecover = <String>[];

    // 查找需要恢复的端点
    _healthStatuses.forEach((endpointId, status) {
      if (status.state == HealthState.unhealthy &&
          status.autoRecoverAt != null &&
          now >= status.autoRecoverAt!) {
        entriesToRecover.add(endpointId);
      }
    });

    // 恢复端点
    for (final endpointId in entriesToRecover) {
      _healthStatuses[endpointId] = HealthStatus(
        endpointId: endpointId,
        state: HealthState.healthy,
        consecutiveFailures: 0,
        lastCheckedAt: now,
        lastSuccessAt: now,
        lastFailureAt: _healthStatuses[endpointId]?.lastFailureAt,
        lastError: null,
        autoRecoverAt: null,
      );
      // Endpoint auto-recovered after 10 minutes
    }
  }

  // =========================
  // 被动健康检查
  // =========================

  /// 记录请求成功（被动检查）
  void recordRequestSuccess(String endpointId) {
    _recordSuccess(endpointId);
  }

  /// 记录请求失败（被动检查）
  void recordRequestFailure(String endpointId, String error) {
    _recordFailure(endpointId, error);
  }

  /// 内部记录成功
  void _recordSuccess(String endpointId) {
    final status = _getOrCreateStatus(endpointId);
    final newStatus = status.recordSuccess();
    _healthStatuses[endpointId] = newStatus;

    // 如果状态从不健康变为健康，打印日志
    if (status.state == HealthState.unhealthy &&
        newStatus.state == HealthState.healthy) {}
  }

  /// 内部记录失败
  void _recordFailure(String endpointId, String error) {
    final status = _getOrCreateStatus(endpointId);
    final newStatus = status.recordFailure(
      error,
      config.consecutiveFailureThreshold,
    );
    _healthStatuses[endpointId] = newStatus;

    // 如果状态从健康变为不健康，打印警告
    if (status.state != HealthState.unhealthy &&
        newStatus.state == HealthState.unhealthy) {}
  }

  /// 获取或创建健康状态
  HealthStatus _getOrCreateStatus(String endpointId) {
    return _healthStatuses.putIfAbsent(
      endpointId,
      () => HealthStatus(endpointId: endpointId),
    );
  }

  // =========================
  // 查询健康状态
  // =========================

  /// 检查端点是否健康
  bool isHealthy(String endpointId) {
    final status = _healthStatuses[endpointId];
    if (status == null) return true; // 未知状态默认为健康
    return status.state == HealthState.healthy;
  }

  /// 获取端点健康状态
  HealthStatus getHealthStatus(String endpointId) {
    return _healthStatuses[endpointId] ?? HealthStatus(endpointId: endpointId);
  }

  /// 获取所有健康状态
  Map<String, HealthStatus> getAllHealthStatuses() {
    return Map.unmodifiable(_healthStatuses);
  }

  /// 获取所有健康的端点 ID
  List<String> getHealthyEndpointIds() {
    return _healthStatuses.entries
        .where((entry) => entry.value.state == HealthState.healthy)
        .map((entry) => entry.key)
        .toList();
  }

  /// 获取所有不健康的端点 ID
  List<String> getUnhealthyEndpointIds() {
    return _healthStatuses.entries
        .where((entry) => entry.value.state == HealthState.unhealthy)
        .map((entry) => entry.key)
        .toList();
  }

  // =========================
  // 管理方法
  // =========================

  /// 重置端点健康状态
  void resetEndpointHealth(String endpointId) {
    _healthStatuses[endpointId] = HealthStatus(endpointId: endpointId);
  }

  /// 重置所有健康状态
  void resetAllHealth() {
    _healthStatuses.clear();
  }

  /// 清理资源
  void dispose() {
    stopActiveHealthCheck();
    _httpClient.close();
  }
}
