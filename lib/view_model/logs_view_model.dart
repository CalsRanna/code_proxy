import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:signals/signals.dart';

class LogsViewModel {
  final _requestLogRepository = RequestLogRepository(Database.instance);

  final logs = listSignal<RequestLog>([]);

  final currentPage = signal(1);
  final pageSize = signal(50);
  final totalPages = signal(1);
  final totalRecords = signal(0);

  Future<void> clearLogs() async {
    await _requestLogRepository.clearAll();
    loadLogs();
  }

  void firstPage() {
    goToPage(1);
  }

  void goToPage(int page) {
    if (page < 1) return;
    currentPage.value = page;
    loadLogs();
  }

  void initSignals() {
    loadLogs();
  }

  void loadLogs() async {
    final startIndex = (currentPage.value - 1) * pageSize.value;
    final dbLogs = await _requestLogRepository.getAll(
      limit: pageSize.value,
      offset: startIndex,
    );
    logs.value = dbLogs;

    final total = await _requestLogRepository.getTotalCount();
    totalRecords.value = total;
    totalPages.value = (total / pageSize.value).ceil();
    if (totalPages.value == 0) totalPages.value = 1;

    if (currentPage.value > totalPages.value) {
      currentPage.value = totalPages.value;
      final newStartIndex = (currentPage.value - 1) * pageSize.value;
      final newDbLogs = await _requestLogRepository.getAll(
        limit: pageSize.value,
        offset: newStartIndex,
      );
      logs.value = newDbLogs;
    }
  }

  void nextPage() {
    goToPage(currentPage.value + 1);
  }

  void previousPage() {
    if (currentPage.value > 1) {
      goToPage(currentPage.value - 1);
    }
  }

  void setPageSize(int size) {
    if (size < 1) return;
    pageSize.value = size;
    currentPage.value = 1;
    loadLogs();
  }
}
