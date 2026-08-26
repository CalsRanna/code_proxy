import 'package:flutter/material.dart';

/// Shadcn UI 标准颜色系统
/// 基于 zinc 色调的中性灰色调配色方案
///
/// 只保留项目实际引用的色值。此前这里放的是整份 Tailwind 调色板
/// （22 个色系 × 11 档，266 个常量），其中 245 个从未被引用。
/// 需要新色值时按需添加，不要成套导入。
class ShadcnColors {
  // ==================== Light Mode Colors ====================

  /// 主背景色 - 纯白
  static const lightBackground = Color(0xFFFFFFFF);

  /// 弱化前景色（次要文本）
  static const lightMutedForeground = Color(0xFF71717A);

  // ==================== Dark Mode Colors ====================

  /// 主背景色
  static const darkBackground = Color(0xFF09090B);

  /// 弱化前景色（次要文本）
  static const darkMutedForeground = Color(0xFFA1A1AA);

  // ==================== Semantic Colors ====================

  /// 警告色（热力图基色）
  static const warning = Color(0xFFF59E0B);

  /// 主色调（折线图、选中态）
  static const primary = Color(0xFF3B82F6);

  // ==================== Zinc Scale ====================

  static const zinc100 = Color(0xFFF4F4F5);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc950 = Color(0xFF09090B);

  // ==================== Chart Series Palette ====================
  //
  // Token 柱状图按端点/模型循环取色，需要一组区分度足够高的同明度色值。

  static const blue500 = Color(0xFF3B82F6);
  static const emerald500 = Color(0xFF10B981);
  static const amber500 = Color(0xFFF59E0B);
  static const violet500 = Color(0xFF8B5CF6);
  static const rose500 = Color(0xFFF43F5E);
  static const cyan500 = Color(0xFF06B6D4);
  static const pink500 = Color(0xFFEC4899);
  static const teal500 = Color(0xFF14B8A6);
  static const orange500 = Color(0xFFF97316);
  static const indigo500 = Color(0xFF6366F1);

  /// 图例用的浅色变体
  static const emerald400 = Color(0xFF34D399);
  static const amber400 = Color(0xFFFBBF24);
  static const violet300 = Color(0xFFC4B5FD);

  // ==================== Brightness Helpers ====================

  /// 获取背景色
  static Color background(Brightness brightness) {
    return brightness == Brightness.light ? lightBackground : darkBackground;
  }

  /// 获取弱化前景色
  static Color mutedForeground(Brightness brightness) {
    return brightness == Brightness.light
        ? lightMutedForeground
        : darkMutedForeground;
  }
}
