import 'dart:async';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/services/database_service.dart';
import 'package:signals/signals.dart';
import 'base_view_model.dart';

/// 日志 ViewModel
/// 负责日志管理和过滤
class LogsViewModel extends BaseViewModel {
  final DatabaseService _databaseService;

  /// 响应式状态
  final logs = listSignal<RequestLog>([]);
  final autoRefresh = signal(true);

  /// 分页状态
  final currentPage = signal(1);
  final pageSize = signal(50); // 每页显示 50 条
  final totalPages = signal(1);
  final totalRecords = signal(0);

  /// 自动刷新定时器
  Timer? _refreshTimer;

  LogsViewModel({
    required DatabaseService databaseService,
  })  : _databaseService = databaseService;

  /// 初始化
  void init() {
    ensureNotDisposed();
    loadLogs();
    startAutoRefresh();
  }

  // =========================
  // 日志加载
  // =========================

  /// 加载日志（真正的分页加载）
  void loadLogs() async {
    if (isDisposed) return;

    try {
      // 优先从数据库分页加载
      if (_databaseService.isInitialized) {
        final startIndex = (currentPage.value - 1) * pageSize.value;
        final dbLogs = await _databaseService.getAllRequestLogs(
          limit: pageSize.value,
          offset: startIndex,
        );
        logs.value = dbLogs;

        // 获取总记录数并计算总页数
        final total = await _databaseService.getRequestLogTotalCount();
        totalRecords.value = total;
        totalPages.value = (total / pageSize.value).ceil();
        if (totalPages.value == 0) totalPages.value = 1;

        // 确保当前页在有效范围内
        if (currentPage.value > totalPages.value) {
          currentPage.value = totalPages.value;
          // 重新加载当前页数据
          final newStartIndex = (currentPage.value - 1) * pageSize.value;
          final newDbLogs = await _databaseService.getAllRequestLogs(
            limit: pageSize.value,
            offset: newStartIndex,
          );
          logs.value = newDbLogs;
        }
      } else {
        // 如果数据库未初始化，返回空列表
        logs.value = [];
        totalRecords.value = 0;
        totalPages.value = 1;
      }
    } catch (e) {
      // 出错时返回空列表
      logs.value = [];
      totalRecords.value = 0;
      totalPages.value = 1;
    }
  }

  /// 开始自动刷新（每 10 秒）
  void startAutoRefresh() {
    if (!autoRefresh.value) return;

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) { // 从2秒改为10秒
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
  // 分页操作
  // =========================

  /// 跳转到指定页
  void goToPage(int page) {
    ensureNotDisposed();
    if (page < 1) return;
    currentPage.value = page;
    loadLogs();
  }

  /// 上一页
  void previousPage() {
    if (currentPage.value > 1) {
      goToPage(currentPage.value - 1);
    }
  }

  /// 下一页
  void nextPage() {
    goToPage(currentPage.value + 1);
  }

  /// 第一页
  void firstPage() {
    goToPage(1);
  }

  /// 设置每页数量
  void setPageSize(int size) {
    ensureNotDisposed();
    if (size < 1) return;
    pageSize.value = size;
    currentPage.value = 1; // 重置到第一页
    loadLogs();
  }

  // =========================
  // 日志操作
  // =========================

  /// 清空日志（仅清空数据库）
  Future<void> clearLogs() async {
    ensureNotDisposed();
    if (_databaseService.isInitialized) {
      await _databaseService.clearAllRequestLogs();
      loadLogs(); // 重新加载（当前页）
    }
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
