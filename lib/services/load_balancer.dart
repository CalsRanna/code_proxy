import 'dart:collection';
import 'package:code_proxy/model/endpoint.dart';

/// 负载均衡器
/// 实现响应时间优先策略
class LoadBalancer {
  final List<Endpoint> Function() getEndpoints;
  final bool Function(String endpointId) isHealthy;
  final int responseTimeWindowSize;

  /// 响应时间窗口映射 (endpointId -> Queue of responseTime)
  final Map<String, Queue<int>> _responseTimeWindows = {};

  /// 默认响应时间（用于没有历史数据的端点）
  static const int defaultResponseTime = 1000;

  LoadBalancer({
    required this.getEndpoints,
    required this.isHealthy,
    this.responseTimeWindowSize = 10,
  });

  // =========================
  // 端点选择
  // =========================

  /// 选择最优端点（响应时间最短的健康端点）
  /// 返回 null 表示没有可用端点
  Endpoint? selectEndpoint() {
    // 获取所有启用且健康的端点
    final allEndpoints = getEndpoints();
    final availableEndpoints = allEndpoints.where((endpoint) {
      final healthy = endpoint.enabled && isHealthy(endpoint.id);
      if (endpoint.enabled && !isHealthy(endpoint.id)) {}
      return healthy;
    }).toList();

    if (availableEndpoints.isEmpty) {
      return null;
    }

    // 只有一个端点时直接返回
    if (availableEndpoints.length == 1) {
      return availableEndpoints.first;
    }

    // 计算每个端点的平均响应时间并选择最快的
    Endpoint? bestEndpoint;
    double bestAvgResponseTime = double.infinity;

    for (final endpoint in availableEndpoints) {
      final avgResponseTime = getAverageResponseTime(endpoint.id);

      if (avgResponseTime < bestAvgResponseTime) {
        bestAvgResponseTime = avgResponseTime;
        bestEndpoint = endpoint;
      }
    }

    return bestEndpoint;
  }

  // =========================
  // 响应时间统计
  // =========================

  /// 记录端点响应时间
  void recordResponseTime(String endpointId, int responseTimeMs) {
    final window = _responseTimeWindows.putIfAbsent(
      endpointId,
      () => Queue<int>(),
    );

    window.add(responseTimeMs);

    // 保持窗口大小
    while (window.length > responseTimeWindowSize) {
      window.removeFirst();
    }
  }

  /// 获取端点的平均响应时间
  /// 如果没有历史数据，返回默认值（1000ms）
  double getAverageResponseTime(String endpointId) {
    final window = _responseTimeWindows[endpointId];

    if (window == null || window.isEmpty) {
      return defaultResponseTime.toDouble();
    }

    // 计算简单移动平均 (SMA)
    final sum = window.reduce((a, b) => a + b);
    return sum / window.length;
  }

  /// 获取端点的最小响应时间
  int? getMinResponseTime(String endpointId) {
    final window = _responseTimeWindows[endpointId];
    if (window == null || window.isEmpty) return null;

    return window.reduce((a, b) => a < b ? a : b);
  }

  /// 获取端点的最大响应时间
  int? getMaxResponseTime(String endpointId) {
    final window = _responseTimeWindows[endpointId];
    if (window == null || window.isEmpty) return null;

    return window.reduce((a, b) => a > b ? a : b);
  }

  /// 获取端点的响应时间样本数量
  int getResponseTimeSampleCount(String endpointId) {
    final window = _responseTimeWindows[endpointId];
    return window?.length ?? 0;
  }

  // =========================
  // 管理方法
  // =========================

  /// 清空端点的响应时间历史
  void clearEndpointHistory(String endpointId) {
    _responseTimeWindows.remove(endpointId);
  }

  /// 清空所有响应时间历史
  void clearAllHistory() {
    _responseTimeWindows.clear();
  }

  /// 获取所有端点的平均响应时间
  Map<String, double> getAllAverageResponseTimes() {
    final result = <String, double>{};
    for (final endpointId in _responseTimeWindows.keys) {
      result[endpointId] = getAverageResponseTime(endpointId);
    }
    return result;
  }
}
