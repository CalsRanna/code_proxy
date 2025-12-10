import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/logs_view_model.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/widgets/log/log_detail_dialog.dart';
import 'package:code_proxy/widgets/log/log_list_item.dart';
import 'package:code_proxy/widgets/log/log_pagination.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
              FilledButton.icon(
                onPressed: () => _showClearDialog(context),
                icon: const Icon(LucideIcons.trash2),
                label: const Text('清空日志'),
                style: FilledButton.styleFrom(
                  backgroundColor: ShadcnColors.error,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          Expanded(
            child: logs.isEmpty
                ? const EmptyState(
                    icon: LucideIcons.arrowUpDown,
                    message: '暂无日志记录',
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(
                            ShadcnSpacing.spacing24,
                          ),
                          itemCount: logs.length,
                          itemBuilder: (context, index) {
                            return LogListItem(
                              log: logs[index],
                              onTap: () => LogDetailDialog.show(
                                context,
                                logs[index],
                              ),
                            );
                          },
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
                  ),
          ),
        ],
      );
    });
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有日志记录吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              viewModel.clearLogs();
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}
