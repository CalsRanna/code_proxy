import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/page/request_log/request_log_clear_dialog.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals.dart';

class RequestLogViewModel {
  final _requestLogRepository = RequestLogRepository(Database.instance);

  final logs = listSignal<RequestLog>([]);

  final currentPage = signal(1);
  final pageSize = signal(50);
  final total = signal(0);

  late final totalPages = computed(() {
    var pages = (total.value / pageSize.value).ceil();
    if (pages == 0) pages = 1;
    return pages;
  });

  void clearLogs(BuildContext context) {
    var dialog = RequestLogClearDialog(onClear: _clearLogs);
    showShadDialog(context: context, builder: (context) => dialog);
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
    this.total.value = total;

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
    paginate(currentPage.value + 1);
  }

  void paginate(int page) {
    if (page < 1) return;
    currentPage.value = page;
    loadLogs();
  }

  void previousPage() {
    if (currentPage.value > 1) {
      paginate(currentPage.value - 1);
    }
  }

  void setPageSize(int size) {
    if (size < 1) return;
    pageSize.value = size;
    currentPage.value = 1;
    loadLogs();
  }

  Future<void> _clearLogs() async {
    await _requestLogRepository.clearAll();
    loadLogs();
  }
}
