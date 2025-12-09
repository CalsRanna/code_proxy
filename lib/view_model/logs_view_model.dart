import 'dart:async';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/services/database_service.dart';
import 'package:code_proxy/services/stats_collector.dart';
import 'package:signals/signals.dart';
import 'base_view_model.dart';

/// 日志 ViewModel
/// 负责日志管理和过滤
class LogsViewModel extends BaseViewModel {
  final StatsCollector _statsCollector;
  final DatabaseService _databaseService;

  /// 响应式状态
  final logs = listSignal<RequestLog>([]);
  final filteredLogs = listSignal<RequestLog>([]);
  final filterKeyword = signal('');
  final filterLevel = signal<LogLevel?>(null);
  final filterEndpointId = signal<String?>(null);
  final autoRefresh = signal(true);

  /// 分页状态
  final currentPage = signal(1);
  final pageSize = signal(50); // 每页显示 50 条
  final totalPages = signal(1);
  final totalRecords = signal(0);

  /// 自动刷新定时器
  Timer? _refreshTimer;

  LogsViewModel({
    required StatsCollector statsCollector,
    required DatabaseService databaseService,
  }) : _statsCollector = statsCollector,
       _databaseService = databaseService;

  /// 初始化
  void init() {
    ensureNotDisposed();
    loadLogs();
    startAutoRefresh();
  }

  // =========================
  // 日志加载
  // =========================

  /// 加载日志
  void loadLogs() async {
    if (isDisposed) return;

    try {
      // 优先从数据库加载日志
      if (_databaseService.isInitialized) {
        final dbLogs = await _databaseService.getAllRequestLogs(limit: 1000);
        logs.value = dbLogs;
      } else {
        // 如果数据库未初始化，从内存加载
        logs.value = _statsCollector.getAllLogs();
      }

      applyFilter();
    } catch (e) {
      // 出错时从内存加载
      logs.value = _statsCollector.getAllLogs();
      applyFilter();
    }
  }

  /// 开始自动刷新（每 2 秒）
  void startAutoRefresh() {
    if (!autoRefresh.value) return;

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (autoRefresh.value) {
        loadLogs();
      }
    });
  }

  /// 停止自动刷新
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 切换自动刷新
  void toggleAutoRefresh() {
    autoRefresh.value = !autoRefresh.value;

    if (autoRefresh.value) {
      startAutoRefresh();
    } else {
      stopAutoRefresh();
    }
  }

  // =========================
  // 过滤操作
  // =========================

  /// 应用过滤
  void applyFilter() {
    if (isDisposed) return;

    var result = logs.value;

    // 关键词过滤
    if (filterKeyword.value.isNotEmpty) {
      final keyword = filterKeyword.value.toLowerCase();
      result = result.where((log) {
        return log.path.toLowerCase().contains(keyword) ||
            log.endpointName.toLowerCase().contains(keyword) ||
            log.method.toLowerCase().contains(keyword) ||
            (log.error?.toLowerCase().contains(keyword) ?? false);
      }).toList();
    }

    // 日志级别过滤
    if (filterLevel.value != null) {
      result = result.where((log) => log.level == filterLevel.value).toList();
    }

    // 端点过滤
    if (filterEndpointId.value != null) {
      result = result
          .where((log) => log.endpointId == filterEndpointId.value)
          .toList();
    }

    // 计算总记录数和总页数
    totalRecords.value = result.length;
    totalPages.value = (result.length / pageSize.value).ceil();
    if (totalPages.value == 0) totalPages.value = 1;

    // 确保当前页在有效范围内
    if (currentPage.value > totalPages.value) {
      currentPage.value = totalPages.value;
    }

    // 应用分页
    final startIndex = (currentPage.value - 1) * pageSize.value;
    final endIndex = (startIndex + pageSize.value).clamp(0, result.length);

    if (startIndex < result.length) {
      filteredLogs.value = result.sublist(startIndex, endIndex);
    } else {
      filteredLogs.value = [];
    }
  }

  /// 设置关键词过滤
  void setFilterKeyword(String keyword) {
    ensureNotDisposed();
    filterKeyword.value = keyword;
    currentPage.value = 1; // 重置到第一页
    applyFilter();
  }

  /// 设置日志级别过滤
  void setFilterLevel(LogLevel? level) {
    ensureNotDisposed();
    filterLevel.value = level;
    currentPage.value = 1; // 重置到第一页
    applyFilter();
  }

  /// 设置端点过滤
  void setFilterEndpointId(String? endpointId) {
    ensureNotDisposed();
    filterEndpointId.value = endpointId;
    currentPage.value = 1; // 重置到第一页
    applyFilter();
  }

  /// 清除所有过滤
  void clearFilters() {
    ensureNotDisposed();
    filterKeyword.value = '';
    filterLevel.value = null;
    filterEndpointId.value = null;
    currentPage.value = 1; // 重置到第一页
    applyFilter();
  }

  // =========================
  // 分页操作
  // =========================

  /// 跳转到指定页
  void goToPage(int page) {
    ensureNotDisposed();
    if (page < 1 || page > totalPages.value) return;
    currentPage.value = page;
    applyFilter();
  }

  /// 上一页
  void previousPage() {
    if (currentPage.value > 1) {
      goToPage(currentPage.value - 1);
    }
  }

  /// 下一页
  void nextPage() {
    if (currentPage.value < totalPages.value) {
      goToPage(currentPage.value + 1);
    }
  }

  /// 第一页
  void firstPage() {
    goToPage(1);
  }

  /// 最后一页
  void lastPage() {
    goToPage(totalPages.value);
  }

  /// 设置每页数量
  void setPageSize(int size) {
    ensureNotDisposed();
    if (size < 1) return;
    pageSize.value = size;
    currentPage.value = 1; // 重置到第一页
    applyFilter();
  }

  // =========================
  // 日志操作
  // =========================

  /// 清空日志（内存 + 数据库）
  Future<void> clearLogs() async {
    ensureNotDisposed();
    await _statsCollector.clearLogs();
    loadLogs();
  }

  /// 获取最近 N 条日志
  List<RequestLog> getRecentLogs(int count) {
    return _statsCollector.getRecentLogs(count);
  }

  /// 根据端点获取日志
  List<RequestLog> getLogsByEndpoint(String endpointId) {
    return _statsCollector.getLogsByEndpoint(endpointId);
  }

  /// 根据级别获取日志
  List<RequestLog> getLogsByLevel(LogLevel level) {
    return _statsCollector.getLogsByLevel(level);
  }

  // =========================
  // 统计信息
  // =========================

  /// 获取总日志数
  int get totalLogCount => logs.value.length;

  /// 获取过滤后的日志数
  int get filteredLogCount => filteredLogs.value.length;

  /// 获取错误日志数
  int get errorLogCount {
    return logs.value.where((log) => log.level == LogLevel.error).length;
  }

  /// 获取警告日志数
  int get warningLogCount {
    return logs.value.where((log) => log.level == LogLevel.warning).length;
  }

  /// 获取信息日志数
  int get infoLogCount {
    return logs.value.where((log) => log.level == LogLevel.info).length;
  }

  // =========================
  // 清理资源
  // =========================

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
}
