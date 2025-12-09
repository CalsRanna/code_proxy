import 'dart:async';
import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/model/endpoint_stats.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:code_proxy/services/stats_collector.dart';
import 'package:signals/signals.dart';
import 'base_view_model.dart';

/// 监控 ViewModel
/// 负责实时监控端点统计信息
class MonitoringViewModel extends BaseViewModel {
  final StatsCollector _statsCollector;
  final ConfigManager _configManager;

  /// 响应式状态
  final endpointStats = signal<Map<String, EndpointStats>>({});

  /// 端点列表（使用 ConfigManager 的全局 signal）
  ListSignal<Endpoint> get endpoints => _configManager.endpoints;

  /// 监控定时器
  Timer? _monitoringTimer;

  MonitoringViewModel({
    required StatsCollector statsCollector,
    required ConfigManager configManager,
  }) : _statsCollector = statsCollector,
       _configManager = configManager;

  /// 初始化
  Future<void> init() async {
    ensureNotDisposed();
    // 端点已由 ConfigManager 加载
    startMonitoring();
  }

  // =========================
  // 监控控制
  // =========================

  /// 开始监控（每 2 秒更新一次）
  void startMonitoring() {
    ensureNotDisposed();

    // 立即更新一次
    _updateStats();

    // 启动定时器
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _updateStats(),
    );
  }

  /// 停止监控
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  /// 更新统计信息
  void _updateStats() {
    if (isDisposed) return;

    endpointStats.value = _statsCollector.getAllEndpointStats();
  }

  /// 手动刷新统计信息（供 UI 调用）
  void refreshStats() {
    _updateStats();
  }

  // =========================
  // 统计操作
  // =========================

  /// 清空指定端点的统计信息
  void clearEndpointStats(String endpointId) {
    ensureNotDisposed();
    _statsCollector.clearEndpointStats(endpointId);
    _updateStats();
  }

  /// 重置所有统计信息
  void resetAllStats() {
    ensureNotDisposed();
    _statsCollector.resetStats();
    _updateStats();
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
    stopMonitoring();
    super.dispose();
  }
}
