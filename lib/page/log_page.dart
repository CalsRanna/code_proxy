import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/logs_view_model.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/widgets/log/log_detail_dialog.dart';
import 'package:code_proxy/widgets/log/log_pagination.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

class LogPage extends StatelessWidget {
  final LogsViewModel viewModel;

  const LogPage({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final logs = viewModel.logs.value;
      final currentPage = viewModel.currentPage.value;
      final totalPages = viewModel.totalPages.value;
      final totalRecords = viewModel.totalRecords.value;
      final pageSize = viewModel.pageSize.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '请求日志',
            subtitle: '$totalRecords 条记录',
            icon: LucideIcons.arrowUpDown,
            actions: [
              ShadButton.destructive(
                onPressed: () => _showClearDialog(context),
                leading: const Icon(LucideIcons.trash2),
                child: const Text('清空日志'),
              ),
            ],
          ),
          Expanded(
            child: Watch((context) {
              return logs.isEmpty
                  ? const EmptyState(
                      icon: LucideIcons.arrowUpDown,
                      message: '暂无日志记录',
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ShadcnSpacing.spacing24,
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return ShadTable(
                                  columnSpanExtent: (column) {
                                    final totalFixedWidth =
                                        180 + 160 + 100 + 120 + 120;
                                    final availableWidth = constraints.maxWidth;
                                    final remainingWidth =
                                        (availableWidth - totalFixedWidth)
                                            .clamp(120.0, double.infinity);

                                    return switch (column) {
                                      0 => FixedSpanExtent(180),
                                      1 => FixedSpanExtent(160),
                                      2 => FixedSpanExtent(remainingWidth),
                                      3 => FixedSpanExtent(100),
                                      4 => FixedSpanExtent(120),
                                      5 => FixedSpanExtent(120),
                                      _ => null,
                                    };
                                  },
                                  pinnedRowCount: 1,
                                  onRowTap: (row) {
                                    if (row == 0) return;
                                    LogDetailDialog.show(
                                      context,
                                      logs[row - 1],
                                    );
                                  },
                                  header: (context, column) {
                                    var text = switch (column) {
                                      0 => '请求时间',
                                      1 => '端点',
                                      2 => '模型',
                                      3 => '状态码',
                                      4 => '响应时间',
                                      5 => 'Token',
                                      _ => '',
                                    };
                                    return ShadTableCell.header(
                                      child: Text(text),
                                    );
                                  },
                                  builder: (context, index) {
                                    var log = logs[index.row];
                                    var text = switch (index.column) {
                                      0 => DateTime.fromMillisecondsSinceEpoch(
                                        log.timestamp,
                                      ).toString().substring(0, 19),
                                      1 => log.endpointName,
                                      2 => log.model,
                                      3 => (log.statusCode ?? 0).toString(),
                                      4 =>
                                        '${((log.responseTime ?? 0) / 1000).toStringAsFixed(2)}s',
                                      5 =>
                                        '${log.inputTokens ?? 0} / ${log.outputTokens ?? 0}',
                                      _ => '',
                                    };
                                    return ShadTableCell(
                                      alignment: Alignment.centerLeft,
                                      child: Text(text ?? 'null'),
                                    );
                                  },
                                  columnCount: 6,
                                  rowCount: logs.length,
                                );
                              },
                            ),
                          ),
                        ),
                        LogPagination(
                          currentPage: currentPage,
                          totalPages: totalPages,
                          totalRecords: totalRecords,
                          pageSize: pageSize,
                          onPageChanged: viewModel.goToPage,
                          onPageSizeChanged: viewModel.setPageSize,
                        ),
                      ],
                    );
            }),
          ),
        ],
      );
    });
  }

  void _showClearDialog(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('确认清空'),
        description: Padding(
          padding: const EdgeInsets.only(bottom: ShadcnSpacing.spacing8),
          child: const Text('确定要清空所有日志记录吗？此操作无法撤销。'),
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ShadButton(
            onPressed: () {
              viewModel.clearLogs();
              Navigator.of(context).pop();
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}
