import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/logs_view_model.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/widgets/log/log_detail_dialog.dart';
import 'package:code_proxy/widgets/log/log_list_item.dart';
import 'package:code_proxy/widgets/log/log_pagination.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class LogPage extends StatelessWidget {
  final LogsViewModel viewModel;

  const LogPage({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final filteredLogs = viewModel.filteredLogs.value;
      final currentPage = viewModel.currentPage.value;
      final totalPages = viewModel.totalPages.value;
      final totalRecords = viewModel.totalRecords.value;
      final pageSize = viewModel.pageSize.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
            child: Row(
              children: [
                const Text(
                  '请求日志',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  onPressed: () => _showClearDialog(context),
                  tooltip: '清空日志',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 主内容
          Expanded(
            child: filteredLogs.isEmpty
                ? const EmptyState(
                    icon: Icons.article_outlined,
                    message: '暂无日志记录',
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.all(ShadcnSpacing.spacing24),
                          itemCount: filteredLogs.length,
                          itemBuilder: (context, index) {
                            return LogListItem(
                              log: filteredLogs[index],
                              onTap: () => LogDetailDialog.show(
                                context,
                                filteredLogs[index],
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
