import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:signals/signals.dart';
import 'base_view_model.dart';

/// 日志 ViewModel
/// 负责日志管理和过滤
class LogsViewModel extends BaseViewModel {
  final RequestLogRepository _requestLogRepository;

  /// 全局信号：通知有新日志插入（用于跨 ViewModel 通信）
  /// 使用 static 确保跨实例共享
  static final newLogInserted = signal(0);

  /// 响应式状态
  final logs = listSignal<RequestLog>([]);

  /// 分页状态
  final currentPage = signal(1);
  final pageSize = signal(50); // 每页显示 50 条
  final totalPages = signal(1);
  final totalRecords = signal(0);

  /// Signal 监听器
  EffectCleanup? _logInsertedEffect;

  LogsViewModel({
    required RequestLogRepository requestLogRepository,
  })  : _requestLogRepository = requestLogRepository;

  /// 初始化
  void init() {
    ensureNotDisposed();
    loadLogs();
    _listenToNewLogs();
  }

  // =========================
  // 日志加载
  // =========================

  /// 监听新日志插入信号
  void _listenToNewLogs() {
    _logInsertedEffect = effect(() {
      // 监听 newLogInserted 的变化
      final _ = newLogInserted.value;

      // 当有新日志插入时，如果当前在第一页，则刷新数据
      if (currentPage.value == 1) {
        loadLogs();
      }
    });
  }

  /// 加载日志（真正的分页加载）
  void loadLogs() async {
    if (isDisposed) return;

    try {
      // 从数据库分页加载
      final startIndex = (currentPage.value - 1) * pageSize.value;
      final dbLogs = await _requestLogRepository.getAll(
        limit: pageSize.value,
        offset: startIndex,
      );
      logs.value = dbLogs;

      // 获取总记录数并计算总页数
      final total = await _requestLogRepository.getTotalCount();
      totalRecords.value = total;
      totalPages.value = (total / pageSize.value).ceil();
      if (totalPages.value == 0) totalPages.value = 1;

      // 确保当前页在有效范围内
      if (currentPage.value > totalPages.value) {
        currentPage.value = totalPages.value;
        // 重新加载当前页数据
        final newStartIndex = (currentPage.value - 1) * pageSize.value;
        final newDbLogs = await _requestLogRepository.getAll(
          limit: pageSize.value,
          offset: newStartIndex,
        );
        logs.value = newDbLogs;
      }
    } catch (e) {
      // 出错时返回空列表
      logs.value = [];
      totalRecords.value = 0;
      totalPages.value = 1;
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
    await _requestLogRepository.clearAll();
    loadLogs(); // 重新加载（当前页）
  }

  // =========================
  // 清理资源
  // =========================

  @override
  void dispose() {
    // 清理 effect 监听器
    _logInsertedEffect?.call();

    // 清理所有信号
    logs.dispose();
    currentPage.dispose();
    pageSize.dispose();
    totalPages.dispose();
    totalRecords.dispose();

    super.dispose();
  }
}
