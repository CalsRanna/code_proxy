import 'dart:async';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/endpoint_stats.dart';
import 'package:code_proxy/services/stats_collector.dart';
import 'package:signals/signals.dart';
import 'base_view_model.dart';
import 'endpoints_view_model.dart';

/// 监控 ViewModel
/// 负责实时监控端点统计信息
class MonitoringViewModel extends BaseViewModel {
  final StatsCollector _statsCollector;

  /// 响应式状态
  final endpointStats = signal<Map<String, EndpointStats>>({});

  /// 端点列表（使用 EndpointsViewModel 的全局 static signal）
  ListSignal<EndpointEntity> get endpoints => EndpointsViewModel.endpoints;

  MonitoringViewModel({required StatsCollector statsCollector})
    : _statsCollector = statsCollector;

  /// 初始化
  Future<void> init() async {
    ensureNotDisposed();
    // 端点已由 ConfigManager 加载
    // 立即更新一次
    endpointStats.value = _statsCollector.getAllEndpointStats();
  }

  /// 手动刷新统计信息（供 UI 调用）
  void refreshStats() {
    if (isDisposed) return;
    endpointStats.value = _statsCollector.getAllEndpointStats();
  }

  // =========================
  // 统计操作
  // =========================

  /// 清空指定端点的统计信息
  void clearEndpointStats(String endpointId) {
    ensureNotDisposed();
    _statsCollector.clearEndpointStats(endpointId);
    refreshStats();
  }

  /// 重置所有统计信息
  void resetAllStats() {
    ensureNotDisposed();
    _statsCollector.resetStats();
    refreshStats();
  }

  // =========================
  // 数据访问
  // =========================

  /// 获取指定端点的统计信息
  EndpointStats? getEndpointStats(String endpointId) {
    return endpointStats.value[endpointId];
  }

  /// 获取总请求数
  int get totalRequests {
    return endpointStats.value.values.fold(
      0,
      (sum, stats) => sum + stats.totalRequests,
    );
  }

  /// 获取总成功率
  double get overallSuccessRate {
    final total = totalRequests;
    if (total == 0) return 0.0;

    final successCount = endpointStats.value.values.fold(
      0,
      (sum, stats) => sum + stats.successRequests,
    );

    return (successCount / total) * 100.0;
  }

  // =========================
  // 清理资源
  // =========================

  @override
  void dispose() {
    // 清理所有信号
    endpointStats.dispose();

    super.dispose();
  }
}
