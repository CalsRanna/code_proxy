import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:flutter/material.dart';

/// 统一的页面头部组件
///
/// 提供页面标题、副标题、图标、操作按钮和搜索框的统一布局
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget>? actions;
  final Widget? searchField;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions,
    this.searchField,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ShadcnColors.border(Theme.of(context).brightness),
            width: ShadcnSpacing.borderWidth,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                IconBadge(
                  icon: icon!,
                  color: Theme.of(context).colorScheme.primary,
                  size: IconBadgeSize.medium,
                ),
                const SizedBox(width: ShadcnSpacing.spacing12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: ShadcnColors.mutedForeground(
                                Theme.of(context).brightness,
                              ),
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions != null) ...actions!,
            ],
          ),
          if (searchField != null) ...[
            const SizedBox(height: ShadcnSpacing.spacing16),
            searchField!,
          ],
        ],
      ),
    );
  }
}
