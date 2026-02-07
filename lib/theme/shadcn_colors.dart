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

  /// 聚焦环颜色 - 中灰 (zinc-400) - 官方标准
  static const lightRing = Color(0xFFA1A1AA);

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

  /// 聚焦环颜色 - 中深灰 (zinc-500) - 官方标准
  static const darkRing = Color(0xFF71717A);

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

  // ==================== Tailwind 完整色彩系统 ====================

  // Neutral 系列
  static const neutral50 = Color(0xFFFAFAFA);
  static const neutral100 = Color(0xFFF5F5F5);
  static const neutral200 = Color(0xFFE5E5E5);
  static const neutral300 = Color(0xFFD4D4D4);
  static const neutral400 = Color(0xFFA3A3A3);
  static const neutral500 = Color(0xFF737373);
  static const neutral600 = Color(0xFF525252);
  static const neutral700 = Color(0xFF404040);
  static const neutral800 = Color(0xFF262626);
  static const neutral900 = Color(0xFF171717);
  static const neutral950 = Color(0xFF0A0A0A);

  // Stone 系列
  static const stone50 = Color(0xFFFAFAF9);
  static const stone100 = Color(0xFFF5F5F4);
  static const stone200 = Color(0xFFE7E5E4);
  static const stone300 = Color(0xFFD6D3D1);
  static const stone400 = Color(0xFFA8A29E);
  static const stone500 = Color(0xFF78716C);
  static const stone600 = Color(0xFF57534E);
  static const stone700 = Color(0xFF44403C);
  static const stone800 = Color(0xFF292524);
  static const stone900 = Color(0xFF1C1917);
  static const stone950 = Color(0xFF0C0A09);

  // Zinc 系列（灰度参考）
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

  // Slate 系列
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);

  // Gray 系列
  static const gray50 = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray600 = Color(0xFF4B5563);
  static const gray700 = Color(0xFF374151);
  static const gray800 = Color(0xFF1F2937);
  static const gray900 = Color(0xFF111827);
  static const gray950 = Color(0xFF030712);

  // Red 系列
  static const red50 = Color(0xFFFEF2F2);
  static const red100 = Color(0xFFFEE2E2);
  static const red200 = Color(0xFFFECACA);
  static const red300 = Color(0xFFFCA5A5);
  static const red400 = Color(0xFFF87171);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red700 = Color(0xFFB91C1C);
  static const red800 = Color(0xFF991B1B);
  static const red900 = Color(0xFF7F1D1D);
  static const red950 = Color(0xFF450A0A);

  // Orange 系列
  static const orange50 = Color(0xFFFFF7ED);
  static const orange100 = Color(0xFFFFEDD5);
  static const orange200 = Color(0xFFFED7AA);
  static const orange300 = Color(0xFFFDBA74);
  static const orange400 = Color(0xFFFB923C);
  static const orange500 = Color(0xFFF97316);
  static const orange600 = Color(0xFFEA580C);
  static const orange700 = Color(0xFFC2410C);
  static const orange800 = Color(0xFF9A3412);
  static const orange900 = Color(0xFF7C2D12);
  static const orange950 = Color(0xFF431407);

  // Amber 系列
  static const amber50 = Color(0xFFFFFBEB);
  static const amber100 = Color(0xFFFEF3C7);
  static const amber200 = Color(0xFFFDE68A);
  static const amber300 = Color(0xFFFCD34D);
  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const amber800 = Color(0xFF92400E);
  static const amber900 = Color(0xFF78350F);
  static const amber950 = Color(0xFF451A03);

  // Yellow 系列
  static const yellow50 = Color(0xFFFEFCE8);
  static const yellow100 = Color(0xFFFEF9C3);
  static const yellow200 = Color(0xFFFEF08A);
  static const yellow300 = Color(0xFFFDE047);
  static const yellow400 = Color(0xFFFACC15);
  static const yellow500 = Color(0xFFEAB308);
  static const yellow600 = Color(0xFFCA8A04);
  static const yellow700 = Color(0xFFA16207);
  static const yellow800 = Color(0xFF854D0E);
  static const yellow900 = Color(0xFF713F12);
  static const yellow950 = Color(0xFF3F2409);

  // Lime 系列
  static const lime50 = Color(0xFFF7FEE7);
  static const lime100 = Color(0xFFECFCCB);
  static const lime200 = Color(0xFFD9F99D);
  static const lime300 = Color(0xFFBEF264);
  static const lime400 = Color(0xFFA3E635);
  static const lime500 = Color(0xFF84CC16);
  static const lime600 = Color(0xFF65A30D);
  static const lime700 = Color(0xFF4D7C0F);
  static const lime800 = Color(0xFF3F6212);
  static const lime900 = Color(0xFF365314);
  static const lime950 = Color(0xFF1A2E05);

  // Green 系列
  static const green50 = Color(0xFFF0FDF4);
  static const green100 = Color(0xFFDCFCE7);
  static const green200 = Color(0xFFBBF7D0);
  static const green300 = Color(0xFF86EFAC);
  static const green400 = Color(0xFF4ADE80);
  static const green500 = Color(0xFF22C55E);
  static const green600 = Color(0xFF16A34A);
  static const green700 = Color(0xFF15803D);
  static const green800 = Color(0xFF166534);
  static const green900 = Color(0xFF14532D);
  static const green950 = Color(0xFF052E16);

  // Emerald 系列
  static const emerald50 = Color(0xFFECFDF5);
  static const emerald100 = Color(0xFFD1FAE5);
  static const emerald200 = Color(0xFFA7F3D0);
  static const emerald300 = Color(0xFF6EE7B7);
  static const emerald400 = Color(0xFF34D399);
  static const emerald500 = Color(0xFF10B981);
  static const emerald600 = Color(0xFF059669);
  static const emerald700 = Color(0xFF047857);
  static const emerald800 = Color(0xFF065F46);
  static const emerald900 = Color(0xFF064E3B);
  static const emerald950 = Color(0xFF022C22);

  // Teal 系列
  static const teal50 = Color(0xFFF0FDFA);
  static const teal100 = Color(0xFFCCFBF1);
  static const teal200 = Color(0xFF99F6E4);
  static const teal300 = Color(0xFF5EEAD4);
  static const teal400 = Color(0xFF2DD4BF);
  static const teal500 = Color(0xFF14B8A6);
  static const teal600 = Color(0xFF0D9488);
  static const teal700 = Color(0xFF0F766E);
  static const teal800 = Color(0xFF115E59);
  static const teal900 = Color(0xFF134E4A);
  static const teal950 = Color(0xFF042F2E);

  // Cyan 系列
  static const cyan50 = Color(0xFFECFEFF);
  static const cyan100 = Color(0xFFCFFAFE);
  static const cyan200 = Color(0xFFA5F3FC);
  static const cyan300 = Color(0xFF67E8F9);
  static const cyan400 = Color(0xFF22D3EE);
  static const cyan500 = Color(0xFF06B6D4);
  static const cyan600 = Color(0xFF0891B2);
  static const cyan700 = Color(0xFF0E7490);
  static const cyan800 = Color(0xFF155E75);
  static const cyan900 = Color(0xFF164E63);
  static const cyan950 = Color(0xFF083344);

  // Sky 系列
  static const sky50 = Color(0xFFF0F9FF);
  static const sky100 = Color(0xFFE0F2FE);
  static const sky200 = Color(0xFFBAE6FD);
  static const sky300 = Color(0xFF7DD3FC);
  static const sky400 = Color(0xFF38BDF8);
  static const sky500 = Color(0xFF0EA5E9);
  static const sky600 = Color(0xFF0284C7);
  static const sky700 = Color(0xFF0369A1);
  static const sky800 = Color(0xFF075985);
  static const sky900 = Color(0xFF0C4A6E);
  static const sky950 = Color(0xFF082F49);

  // Blue 系列
  static const blue50 = Color(0xFFEFF6FF);
  static const blue100 = Color(0xFFDBEAFE);
  static const blue200 = Color(0xFFBFDBFE);
  static const blue300 = Color(0xFF93C5FD);
  static const blue400 = Color(0xFF60A5FA);
  static const blue500 = Color(0xFF3B82F6);
  static const blue600 = Color(0xFF2563EB);
  static const blue700 = Color(0xFF1D4ED8);
  static const blue800 = Color(0xFF1E40AF);
  static const blue900 = Color(0xFF1E3A8A);
  static const blue950 = Color(0xFF172554);

  // Indigo 系列
  static const indigo50 = Color(0xFFEEF2FF);
  static const indigo100 = Color(0xFFE0E7FF);
  static const indigo200 = Color(0xFFC7D2FE);
  static const indigo300 = Color(0xFFA5B4FC);
  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);
  static const indigo800 = Color(0xFF3730A3);
  static const indigo900 = Color(0xFF312E81);
  static const indigo950 = Color(0xFF1E1B4B);

  // Violet 系列
  static const violet50 = Color(0xFFF5F3FF);
  static const violet100 = Color(0xFFEDE9FE);
  static const violet200 = Color(0xFFDDD6FE);
  static const violet300 = Color(0xFFC4B5FD);
  static const violet400 = Color(0xFFA78BFA);
  static const violet500 = Color(0xFF8B5CF6);
  static const violet600 = Color(0xFF7C3AED);
  static const violet700 = Color(0xFF6D28D9);
  static const violet800 = Color(0xFF5B21B6);
  static const violet900 = Color(0xFF4C1D95);
  static const violet950 = Color(0xFF2E1065);

  // Purple 系列
  static const purple50 = Color(0xFFFAF5FF);
  static const purple100 = Color(0xFFF3E8FF);
  static const purple200 = Color(0xFFE9D5FF);
  static const purple300 = Color(0xFFD8B4FE);
  static const purple400 = Color(0xFFC084FC);
  static const purple500 = Color(0xFFA855F7);
  static const purple600 = Color(0xFF9333EA);
  static const purple700 = Color(0xFF7E22CE);
  static const purple800 = Color(0xFF6B21A8);
  static const purple900 = Color(0xFF581C87);
  static const purple950 = Color(0xFF3B0764);

  // Fuchsia 系列
  static const fuchsia50 = Color(0xFFFDF4FF);
  static const fuchsia100 = Color(0xFFFAE8FF);
  static const fuchsia200 = Color(0xFFF5D0FE);
  static const fuchsia300 = Color(0xFFF0ABFC);
  static const fuchsia400 = Color(0xFFE879F9);
  static const fuchsia500 = Color(0xFFD946EF);
  static const fuchsia600 = Color(0xFFC026D3);
  static const fuchsia700 = Color(0xFFA21CAF);
  static const fuchsia800 = Color(0xFF86198F);
  static const fuchsia900 = Color(0xFF701A75);
  static const fuchsia950 = Color(0xFF4A044E);

  // Pink 系列
  static const pink50 = Color(0xFFFDF2F8);
  static const pink100 = Color(0xFFFCE7F3);
  static const pink200 = Color(0xFFFBCFE8);
  static const pink300 = Color(0xFFF9A8D4);
  static const pink400 = Color(0xFFF472B6);
  static const pink500 = Color(0xFFEC4899);
  static const pink600 = Color(0xFFDB2777);
  static const pink700 = Color(0xFFBE185D);
  static const pink800 = Color(0xFF9D174D);
  static const pink900 = Color(0xFF831843);
  static const pink950 = Color(0xFF500724);

  // Rose 系列
  static const rose50 = Color(0xFFFFF1F2);
  static const rose100 = Color(0xFFFFE4E6);
  static const rose200 = Color(0xFFFECDD3);
  static const rose300 = Color(0xFFFDA4AF);
  static const rose400 = Color(0xFFFB7185);
  static const rose500 = Color(0xFFF43F5E);
  static const rose600 = Color(0xFFE11D48);
  static const rose700 = Color(0xFFBE123C);
  static const rose800 = Color(0xFF9F1239);
  static const rose900 = Color(0xFF881337);
  static const rose950 = Color(0xFF4C0519);

  // ==================== 辅助方法 ====================

  /// 根据亮度模式获取对应的颜色
  static Color getColor(
    Brightness brightness,
    Color lightColor,
    Color darkColor,
  ) {
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
    return brightness == Brightness.light
        ? lightMutedForeground
        : darkMutedForeground;
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
