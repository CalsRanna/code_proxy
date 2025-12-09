import 'package:flutter/material.dart';

/// Shadcn UI 标准颜色系统
/// 基于 zinc 色调的中性灰色调配色方案
class ShadcnColors {
  // ==================== Light Mode Colors ====================

  /// 主背景色 - 纯白
  static const lightBackground = Color(0xFFFFFFFF);

  /// 主前景色/文字色 - 深灰黑 (zinc-950)
  static const lightForeground = Color(0xFF09090B);

  /// 卡片背景色 - 白色
  static const lightCard = Color(0xFFFFFFFF);

  /// 卡片前景色
  static const lightCardForeground = Color(0xFF09090B);

  /// 弱化背景色 - 浅灰 (zinc-100)
  static const lightMuted = Color(0xFFF4F4F5);

  /// 弱化前景色/次要文字 - 中灰 (zinc-500)
  static const lightMutedForeground = Color(0xFF71717A);

  /// 边框色 - 浅灰 (zinc-200)
  static const lightBorder = Color(0xFFE4E4E7);

  /// 输入框边框色 - 同 border
  static const lightInput = Color(0xFFE4E4E7);

  /// 聚焦环颜色 - 深色 (zinc-900)
  static const lightRing = Color(0xFF18181B);

  // ==================== Dark Mode Colors ====================

  /// 主背景色 - 深色 (zinc-950)
  static const darkBackground = Color(0xFF09090B);

  /// 主前景色/文字色 - 近白 (zinc-50)
  static const darkForeground = Color(0xFFFAFAFA);

  /// 卡片背景色 - 深色 (zinc-950)
  static const darkCard = Color(0xFF09090B);

  /// 卡片前景色
  static const darkCardForeground = Color(0xFFFAFAFA);

  /// 弱化背景色 - 深灰 (zinc-800)
  static const darkMuted = Color(0xFF27272A);

  /// 弱化前景色/次要文字 - 浅灰 (zinc-400)
  static const darkMutedForeground = Color(0xFFA1A1AA);

  /// 边框色 - 深灰 (zinc-800)
  static const darkBorder = Color(0xFF27272A);

  /// 输入框边框色 - 同 border
  static const darkInput = Color(0xFF27272A);

  /// 聚焦环颜色 - 浅色 (zinc-300)
  static const darkRing = Color(0xFFD4D4D8);

  // ==================== 状态颜色 ====================

  /// 成功色 - 绿色 (与原主题保持一致)
  static const success = Color(0xFF10B981);

  /// 警告色 - 橙色
  static const warning = Color(0xFFF59E0B);

  /// 错误色 - 红色
  static const error = Color(0xFFEF4444);

  /// 信息色 - 蓝色
  static const info = Color(0xFF3B82F6);

  // ==================== 主题色（可自定义的强调色）====================

  /// 主要强调色 - 可根据品牌调整，默认使用中性蓝色
  static const primary = Color(0xFF3B82F6);

  /// 次要强调色
  static const secondary = Color(0xFF8B5CF6);

  // ==================== Zinc 灰度系列（完整参考）====================

  static const zinc50 = Color(0xFFFAFAFA);
  static const zinc100 = Color(0xFFF4F4F5);
  static const zinc200 = Color(0xFFE4E4E7);
  static const zinc300 = Color(0xFFD4D4D8);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc600 = Color(0xFF52525B);
  static const zinc700 = Color(0xFF3F3F46);
  static const zinc800 = Color(0xFF27272A);
  static const zinc900 = Color(0xFF18181B);
  static const zinc950 = Color(0xFF09090B);

  // ==================== 辅助方法 ====================

  /// 根据亮度模式获取对应的颜色
  static Color getColor(Brightness brightness, Color lightColor, Color darkColor) {
    return brightness == Brightness.light ? lightColor : darkColor;
  }

  /// 获取背景色
  static Color background(Brightness brightness) {
    return brightness == Brightness.light ? lightBackground : darkBackground;
  }

  /// 获取前景色
  static Color foreground(Brightness brightness) {
    return brightness == Brightness.light ? lightForeground : darkForeground;
  }

  /// 获取卡片色
  static Color card(Brightness brightness) {
    return brightness == Brightness.light ? lightCard : darkCard;
  }

  /// 获取弱化背景色
  static Color muted(Brightness brightness) {
    return brightness == Brightness.light ? lightMuted : darkMuted;
  }

  /// 获取弱化前景色
  static Color mutedForeground(Brightness brightness) {
    return brightness == Brightness.light ? lightMutedForeground : darkMutedForeground;
  }

  /// 获取边框色
  static Color border(Brightness brightness) {
    return brightness == Brightness.light ? lightBorder : darkBorder;
  }

  /// 获取输入框色
  static Color input(Brightness brightness) {
    return brightness == Brightness.light ? lightInput : darkInput;
  }

  /// 获取聚焦环色
  static Color ring(Brightness brightness) {
    return brightness == Brightness.light ? lightRing : darkRing;
  }
}
