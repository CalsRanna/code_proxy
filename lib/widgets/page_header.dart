import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:flutter/material.dart';

/// 统一的页面头部组件
///
/// 提供页面标题、副标题、图标、操作按钮和搜索框的统一布局
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    var titleTextStyle = Theme.of(
      context,
    ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold);
    var subtitleTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: ShadcnColors.mutedForeground(Theme.of(context).brightness),
    );
    var columnChildren = [
      Text(title, style: titleTextStyle),
      if (subtitle != null) Text(subtitle!, style: subtitleTextStyle),
    ];
    var column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: ShadcnSpacing.spacing4,
      children: columnChildren,
    );
    var rowChildren = [
      Expanded(child: column),
      if (actions != null) ...actions!,
    ];
    var borderSide = BorderSide(
      color: ShadcnColors.zinc100,
      width: ShadcnSpacing.borderWidth,
    );
    return Container(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
      decoration: BoxDecoration(border: Border(bottom: borderSide)),
      child: Row(children: rowChildren),
    );
  }
}
