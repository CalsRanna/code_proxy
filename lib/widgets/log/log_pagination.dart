import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:flutter/material.dart';

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
        color: ShadcnColors.muted(brightness),
        border: Border(
          top: BorderSide(
            color: ShadcnColors.border(brightness),
            width: ShadcnSpacing.borderWidth,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左: 记录数信息
          Text(
            '共 $totalRecords 条记录',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ShadcnColors.mutedForeground(brightness),
                ),
          ),
          // 中: 分页按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: currentPage > 1 ? () => onPageChanged(1) : null,
                tooltip: '首页',
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed:
                    currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
                tooltip: '上一页',
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ShadcnSpacing.spacing16,
                  vertical: ShadcnSpacing.spacing8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius:
                      BorderRadius.circular(ShadcnSpacing.radiusSmall),
                  border: Border.all(
                    color: ShadcnColors.border(brightness),
                    width: ShadcnSpacing.borderWidth,
                  ),
                ),
                child: Text(
                  '$currentPage / $totalPages',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: currentPage < totalPages
                    ? () => onPageChanged(currentPage + 1)
                    : null,
                tooltip: '下一页',
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: currentPage < totalPages
                    ? () => onPageChanged(totalPages)
                    : null,
                tooltip: '尾页',
              ),
            ],
          ),
          // 右: 每页条数选择
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '每页',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ShadcnColors.mutedForeground(brightness),
                    ),
              ),
              const SizedBox(width: ShadcnSpacing.spacing8),
              DropdownButton<int>(
                value: pageSize,
                items: [20, 50, 100, 200]
                    .map((size) => DropdownMenuItem(
                          value: size,
                          child: Text('$size'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) onPageSizeChanged(value);
                },
                underline: const SizedBox(),
              ),
              const SizedBox(width: ShadcnSpacing.spacing8),
              Text(
                '条',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ShadcnColors.mutedForeground(brightness),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
