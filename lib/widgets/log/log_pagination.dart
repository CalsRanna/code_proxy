import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 日志分页组件
class LogPagination extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalRecords;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPageSizeChanged;

  const LogPagination({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalRecords,
    required this.pageSize,
    required this.onPageChanged,
    required this.onPageSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing24,
        vertical: ShadcnSpacing.spacing16,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: ShadcnColors.border(brightness),
            width: ShadcnSpacing.borderWidth,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.max,
        spacing: ShadcnSpacing.spacing12,
        children: [
          ShadButton.ghost(
            leading: const Icon(LucideIcons.chevronLeft),
            onPressed: currentPage > 1
                ? () => onPageChanged(currentPage - 1)
                : null,
            child: const Text('上一页'),
          ),
          Text('$currentPage / $totalPages'),
          ShadButton.ghost(
            leading: const Icon(LucideIcons.chevronRight),
            onPressed: currentPage < totalPages
                ? () => onPageChanged(currentPage + 1)
                : null,
            child: const Text('下一页'),
          ),
        ],
      ),
    );
  }
}
