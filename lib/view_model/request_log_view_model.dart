import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:signals/signals.dart';

class RequestLogViewModel {
  final _requestLogRepository = RequestLogRepository(Database.instance);

  final logs = listSignal<RequestLogEntity>([]);

  final currentPage = signal(1);
  final pageSize = signal(50);
  final total = signal(0);

  /// null=全部, 200=仅成功, -1=仅失败(非200)
  final statusCodeFilter = signal<int?>(null);

  late final totalPages = computed(() {
    var pages = (total.value / pageSize.value).ceil();
    if (pages == 0) pages = 1;
    return pages;
  });

  void initSignals() {
    loadLogs();
  }

  Future<void> loadLogs() async {
    try {
      final filter = statusCodeFilter.value;

      // 先获取总数，再根据总数计算有效页码，避免重复查库
      final totalCount = await _requestLogRepository.getTotalCount(
        statusCodeFilter: filter,
      );
      total.value = totalCount;

      // 修正越界页码
      if (currentPage.value > totalPages.value) {
        currentPage.value = totalPages.value;
      }

      final startIndex = (currentPage.value - 1) * pageSize.value;
      final dbLogs = await _requestLogRepository.getAll(
        limit: pageSize.value,
        offset: startIndex,
        statusCodeFilter: filter,
      );
      logs.value = dbLogs;
    } catch (e) {
      // 查询失败不崩溃（该方法是代理主流程回调的常见入口）
      LoggerUtil.instance.e('Failed to load request logs: $e');
    }
  }

  void paginate(int page) {
    if (page < 1) return;
    currentPage.value = page;
    loadLogs();
  }

  void setPageSize(int size) {
    if (size < 1) return;
    pageSize.value = size;
    currentPage.value = 1;
    loadLogs();
  }

  void setStatusCodeFilter(int? filter) {
    statusCodeFilter.value = filter;
    currentPage.value = 1;
    loadLogs();
  }
}
