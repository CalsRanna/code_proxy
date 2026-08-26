/// Shadcn UI 间距系统
/// 基于 4px 基础单元的设计系统
///
/// 只保留项目实际引用的值。此前这里还有圆角、阴影、图标尺寸、
/// 按钮/输入框/卡片内边距共 35 个常量，全部零引用 —— 这些维度实际
/// 由 shadcn_ui 组件库自身的主题负责，不需要在这里再定义一套。
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

  /// 24px - 大间距
  static const double spacing24 = 24.0;

  // ==================== 边框宽度 ====================

  /// 标准边框宽度 - 1px（Shadcn UI 标准细边框）
  static const double borderWidth = 1.0;
}
