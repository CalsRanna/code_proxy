/// Shadcn UI 间距和圆角系统
/// 基于 4px 基础单元的设计系统
class ShadcnSpacing {
  // ==================== 间距系统（4px 基础单元）====================

  /// 4px - 最小间距
  static const double spacing4 = 4.0;

  /// 8px - 小间距
  static const double spacing8 = 8.0;

  /// 12px - 中小间距
  static const double spacing12 = 12.0;

  /// 16px - 中等间距（最常用）
  static const double spacing16 = 16.0;

  /// 20px - 中大间距
  static const double spacing20 = 20.0;

  /// 24px - 大间距
  static const double spacing24 = 24.0;

  /// 32px - 超大间距
  static const double spacing32 = 32.0;

  /// 48px - 巨大间距
  static const double spacing48 = 48.0;

  // ==================== 圆角系统 ====================

  /// 2px - 极小圆角（用于小元素，如热力图单元格）
  static const double radiusTiny = 2.0;

  /// 4px - 微小圆角
  static const double radiusXs = 4.0;

  /// 6px - 小圆角（用于小组件，如图标容器、徽章）
  static const double radiusSmall = 6.0;

  /// 8px - 中等圆角（主要圆角，用于按钮、输入框、卡片）
  static const double radiusMedium = 8.0;

  /// 12px - 大圆角（用于对话框、模态框）
  static const double radiusLarge = 12.0;

  /// 16px - 超大圆角（特殊情况）
  static const double radiusXl = 16.0;

  // ==================== 边框宽度 ====================

  /// 标准边框宽度 - 1px（Shadcn UI 标准细边框）
  static const double borderWidth = 1.0;

  /// 聚焦边框宽度 - 保持 1px（通过 ring 效果增强）
  static const double borderWidthFocused = 1.0;

  // ==================== 阴影配置 ====================

  /// 微妙阴影 - blur radius
  static const double shadowBlurSmall = 3.0;

  /// 中等阴影 - blur radius
  static const double shadowBlurMedium = 8.0;

  /// 大阴影 - blur radius
  static const double shadowBlurLarge = 20.0;

  /// 微妙阴影 - 垂直偏移
  static const double shadowOffsetSmall = 1.0;

  /// 中等阴影 - 垂直偏移
  static const double shadowOffsetMedium = 2.0;

  /// 大阴影 - 垂直偏移
  static const double shadowOffsetLarge = 4.0;

  /// 浅色模式阴影透明度 - 微妙
  static const double shadowOpacityLightSmall = 0.05;

  /// 浅色模式阴影透明度 - 中等
  static const double shadowOpacityLightMedium = 0.1;

  /// 深色模式阴影透明度 - 微妙
  static const double shadowOpacityDarkSmall = 0.2;

  /// 深色模式阴影透明度 - 中等
  static const double shadowOpacityDarkMedium = 0.4;

  // ==================== Ring 聚焦效果配置 ====================

  /// Ring 扩散半径（spreadRadius）
  static const double ringSpread = 3.0;

  /// Ring 透明度
  static const double ringOpacity = 0.15;

  // ==================== 图标尺寸 ====================

  /// 小图标 - 16px
  static const double iconSmall = 16.0;

  /// 中等图标 - 20px（最常用）
  static const double iconMedium = 20.0;

  /// 大图标 - 24px
  static const double iconLarge = 24.0;

  /// 超大图标 - 32px
  static const double iconXl = 32.0;

  /// 巨大图标 - 64px（用于空状态、装饰性图标）
  static const double iconHuge = 64.0;

  // ==================== 按钮内边距 ====================

  /// 按钮水平内边距
  static const double buttonPaddingH = 16.0;

  /// 按钮垂直内边距
  static const double buttonPaddingV = 12.0;

  // ==================== 输入框内边距 ====================

  /// 输入框水平内边距
  static const double inputPaddingH = 16.0;

  /// 输入框垂直内边距
  static const double inputPaddingV = 12.0;

  // ==================== 卡片内边距 ====================

  /// 卡片小内边距
  static const double cardPaddingSmall = 12.0;

  /// 卡片标准内边距
  static const double cardPadding = 16.0;

  /// 卡片大内边距
  static const double cardPaddingLarge = 20.0;

  /// 卡片超大内边距
  static const double cardPaddingXl = 24.0;
}
