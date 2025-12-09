import 'package:flutter/material.dart';
import 'shadcn_colors.dart';

/// Shadcn颜色辅助扩展
///
/// 提供常用的颜色获取方法，统一颜色使用规范
extension ShadcnColorHelpers on ShadcnColors {
  /// 获取状态颜色对（前景+背景+边框）
  ///
  /// 用于根据状态类型获取一致的颜色组合
  static ColorPair forStatus(StatusType type, Brightness brightness) {
    switch (type) {
      case StatusType.success:
        return ColorPair(
          foreground: ShadcnColors.success,
          background: ShadcnColors.success.withValues(alpha: 0.1),
          border: ShadcnColors.success.withValues(alpha: 0.2),
        );
      case StatusType.warning:
        return ColorPair(
          foreground: ShadcnColors.warning,
          background: ShadcnColors.warning.withValues(alpha: 0.1),
          border: ShadcnColors.warning.withValues(alpha: 0.2),
        );
      case StatusType.error:
        return ColorPair(
          foreground: ShadcnColors.error,
          background: ShadcnColors.error.withValues(alpha: 0.1),
          border: ShadcnColors.error.withValues(alpha: 0.2),
        );
      case StatusType.info:
        return ColorPair(
          foreground: ShadcnColors.info,
          background: ShadcnColors.info.withValues(alpha: 0.1),
          border: ShadcnColors.info.withValues(alpha: 0.2),
        );
      case StatusType.neutral:
        return ColorPair(
          foreground: ShadcnColors.mutedForeground(brightness),
          background: ShadcnColors.muted(brightness),
          border: ShadcnColors.border(brightness),
        );
    }
  }

  /// 获取响应时间对应的颜色
  ///
  /// 根据响应时间毫秒数返回对应的颜色：
  /// - < 500ms: 绿色（成功）
  /// - 500-2000ms: 橙色（警告）
  /// - >= 2000ms: 红色（错误）
  static Color forResponseTime(int milliseconds) {
    if (milliseconds < 500) {
      return ShadcnColors.success;
    } else if (milliseconds < 2000) {
      return ShadcnColors.warning;
    } else {
      return ShadcnColors.error;
    }
  }

  /// 根据主题获取Hover颜色
  ///
  /// 返回适合当前主题的悬停状态颜色
  static Color hover(Brightness brightness) {
    return ShadcnColors.muted(brightness);
  }

  /// 获取带透明度的主题相关颜色
  ///
  /// 根据深色/浅色模式返回不同透明度的颜色
  static Color withThemeDependentAlpha(
    Color color,
    double darkAlpha,
    double lightAlpha,
    Brightness brightness,
  ) {
    return color.withValues(
      alpha: brightness == Brightness.dark ? darkAlpha : lightAlpha,
    );
  }
}

/// 颜色对
///
/// 包含前景色、背景色和边框色的组合
class ColorPair {
  final Color foreground;
  final Color background;
  final Color border;

  const ColorPair({
    required this.foreground,
    required this.background,
    required this.border,
  });
}

/// 状态类型枚举
///
/// 定义系统中的各种状态类型
enum StatusType {
  /// 成功状态（绿色）
  success,

  /// 警告状态（橙色）
  warning,

  /// 错误状态（红色）
  error,

  /// 信息状态（蓝色）
  info,

  /// 中性状态（灰色）
  neutral,
}
