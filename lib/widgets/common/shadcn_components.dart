import 'package:flutter/material.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/themes/shadcn_color_helpers.dart';

/// Shadcn UI 风格的通用组件库
/// 包含符合Shadcn设计规范的基础组件

// ============================================================================
// 1. SectionHeader - 统一的段落标题
// ============================================================================

/// 段落标题组件
///
/// 用于标识页面中的不同section，提供统一的标题样式
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: ShadcnSpacing.spacing12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(ShadcnSpacing.spacing8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
              ),
              child: Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: ShadcnSpacing.spacing12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: ShadcnColors.mutedForeground(brightness),
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ============================================================================
// 2. IconBadge - 图标容器徽章
// ============================================================================

enum IconBadgeSize {
  small(32),
  medium(40),
  large(48);

  final double size;
  const IconBadgeSize(this.size);

  double get iconSize {
    switch (this) {
      case IconBadgeSize.small:
        return 16;
      case IconBadgeSize.medium:
        return 20;
      case IconBadgeSize.large:
        return 24;
    }
  }

  double get padding {
    switch (this) {
      case IconBadgeSize.small:
        return ShadcnSpacing.spacing8;
      case IconBadgeSize.medium:
        return ShadcnSpacing.spacing12;
      case IconBadgeSize.large:
        return ShadcnSpacing.spacing12;
    }
  }
}

/// 图标容器徽章组件
///
/// 用于显示带有背景色容器的图标，常用于卡片、对话框标题等
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final IconBadgeSize size;

  const IconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = IconBadgeSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    return Container(
      width: size.size,
      height: size.size,
      padding: EdgeInsets.all(size.padding),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
      ),
      child: Icon(
        icon,
        size: size.iconSize,
        color: effectiveColor,
      ),
    );
  }
}

// ============================================================================
// 3. StatusBadge - 状态标签
// ============================================================================

/// 状态标签组件
///
/// 用于显示状态信息，支持不同的状态类型和颜色
class StatusBadge extends StatelessWidget {
  final String label;
  final StatusType type;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.label,
    this.type = StatusType.neutral,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = ShadcnColorHelpers.forStatus(type, brightness);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? ShadcnSpacing.spacing8 : ShadcnSpacing.spacing12,
        vertical: compact ? 2 : ShadcnSpacing.spacing4,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusSmall),
        border: Border.all(
          color: colors.border,
          width: ShadcnSpacing.borderWidth,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 12,
              fontFamily: label.contains(':') ? 'monospace' : null,
            ),
      ),
    );
  }
}

// ============================================================================
// 4. InfoRow - 键值对信息展示
// ============================================================================

/// 信息行组件
///
/// 用于展示键值对信息，常用于详情对话框
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final bool selectable;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: ShadcnColors.mutedForeground(brightness),
            ),
            const SizedBox(width: ShadcnSpacing.spacing8),
          ],
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ShadcnColors.mutedForeground(brightness),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Expanded(
            child: selectable
                ? SelectableText(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                : Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. EmptyState - 空状态占位
// ============================================================================

/// 空状态组件
///
/// 用于在列表为空时显示占位内容
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Center(
      child: Container(
        constraints: const BoxConstraints(minHeight: 200),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: ShadcnColors.mutedForeground(brightness).withValues(alpha: 0.5),
            ),
            const SizedBox(height: ShadcnSpacing.spacing16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: ShadcnColors.mutedForeground(brightness),
                  ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: ShadcnSpacing.spacing24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 6. StatCard - 统计卡片
// ============================================================================

/// 统计卡片组件
///
/// 用于显示统计数据，符合Shadcn UI的卡片设计规范（无渐变）
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final effectiveColor = accentColor ?? Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusLarge),
        border: Border.all(
          color: ShadcnColors.border(brightness),
          width: ShadcnSpacing.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: brightness == Brightness.dark
                  ? ShadcnSpacing.shadowOpacityDarkSmall
                  : ShadcnSpacing.shadowOpacityLightSmall,
            ),
            blurRadius: ShadcnSpacing.shadowBlurSmall,
            offset: Offset(0, ShadcnSpacing.shadowOffsetSmall),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(ShadcnSpacing.spacing20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(
                  icon: icon,
                  color: effectiveColor,
                  size: IconBadgeSize.small,
                ),
                const Spacer(),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: effectiveColor,
                      ),
                ),
              ],
            ),
            const SizedBox(height: ShadcnSpacing.spacing12),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ShadcnColors.mutedForeground(brightness),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
