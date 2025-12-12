import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RequestLogPagination extends StatelessWidget {
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPageSizeChanged;
  final int pageSize;
  final int total;

  const RequestLogPagination({
    super.key,
    required this.currentPage,
    required this.onPageChanged,
    required this.onPageSizeChanged,
    required this.total,
    required this.pageSize,
  });

  int get _totalPage => (total / pageSize).ceil();

  @override
  Widget build(BuildContext context) {
    var previousButton = ShadButton.ghost(
      leading: const Icon(LucideIcons.chevronLeft),
      onPressed: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
      child: const Text('上一页'),
    );
    var nextButton = ShadButton.ghost(
      leading: const Icon(LucideIcons.chevronRight),
      onPressed: currentPage < _totalPage
          ? () => onPageChanged(currentPage + 1)
          : null,
      child: const Text('下一页'),
    );
    var children = [
      previousButton,
      Text('$currentPage / $_totalPage'),
      nextButton,
    ];
    var row = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.max,
      spacing: ShadcnSpacing.spacing12,
      children: children,
    );
    var borderSide = BorderSide(
      color: ShadcnColors.zinc100,
      width: ShadcnSpacing.borderWidth,
    );
    var edgeInsets = const EdgeInsets.symmetric(
      horizontal: ShadcnSpacing.spacing24,
      vertical: ShadcnSpacing.spacing16,
    );
    return Container(
      padding: edgeInsets,
      decoration: BoxDecoration(border: Border(top: borderSide)),
      child: row,
    );
  }
}
