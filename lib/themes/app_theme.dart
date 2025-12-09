import 'package:flutter/material.dart';
import 'shadcn_colors.dart';
import 'shadcn_spacing.dart';

/// Shadcn UI 风格的应用主题
/// 采用中性灰色调、细边框、微妙阴影的现代设计语言
class AppTheme {
  // ==================== 浅色主题 ====================
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.light(
      // 主色调 - 保持可自定义
      primary: ShadcnColors.primary,
      secondary: ShadcnColors.secondary,

      // Shadcn UI 标准颜色
      surface: ShadcnColors.lightBackground,
      onSurface: ShadcnColors.lightForeground,

      // 错误色
      error: ShadcnColors.error,
      onError: Colors.white,

      // 容器色
      surfaceContainerHighest: ShadcnColors.lightMuted,

      // 轮廓色
      outline: ShadcnColors.lightBorder,
      outlineVariant: ShadcnColors.lightBorder,

      // 反色
      inverseSurface: ShadcnColors.lightForeground,
      onInverseSurface: ShadcnColors.lightBackground,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ShadcnColors.lightBackground,

      // ==================== 卡片主题 ====================
      cardTheme: CardThemeData(
        elevation: 0, // Shadcn 使用边框和微妙阴影，不用 elevation
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          side: BorderSide(
            color: ShadcnColors.lightBorder,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
        color: ShadcnColors.lightCard,
        shadowColor: Colors.black,
        surfaceTintColor: Colors.transparent,
      ),

      // ==================== 应用栏主题 ====================
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: ShadcnColors.lightForeground,
        surfaceTintColor: Colors.transparent,
      ),

      // ==================== 填充按钮主题 ====================
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: ShadcnSpacing.buttonPaddingH,
            vertical: ShadcnSpacing.buttonPaddingV,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          // Ring 聚焦效果
          overlayColor: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return ShadcnColors.primary.withValues(alpha: 0.1);
            }
            return Colors.transparent;
          }),
        ),
      ),

      // ==================== 轮廓按钮主题 ====================
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: ShadcnSpacing.buttonPaddingH,
            vertical: ShadcnSpacing.buttonPaddingV,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          ),
          side: BorderSide(
            color: ShadcnColors.lightBorder,
            width: ShadcnSpacing.borderWidth,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          foregroundColor: WidgetStateColor.resolveWith((states) {
            return ShadcnColors.lightForeground;
          }),
          // Ring 聚焦效果
          overlayColor: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return ShadcnColors.primary.withValues(alpha: 0.1);
            }
            return Colors.transparent;
          }),
        ),
      ),

      // ==================== 文本按钮主题 ====================
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: ShadcnSpacing.buttonPaddingH,
            vertical: ShadcnSpacing.buttonPaddingV,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          foregroundColor: WidgetStateColor.resolveWith((states) {
            return ShadcnColors.primary;
          }),
        ),
      ),

      // ==================== 输入框主题 ====================
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ShadcnColors.lightBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ShadcnSpacing.inputPaddingH,
          vertical: ShadcnSpacing.inputPaddingV,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          borderSide: BorderSide(
            color: ShadcnColors.lightInput,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          borderSide: BorderSide(
            color: ShadcnColors.lightInput,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          borderSide: BorderSide(
            color: ShadcnColors.primary,
            width: ShadcnSpacing.borderWidthFocused,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          borderSide: BorderSide(
            color: ShadcnColors.error,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          borderSide: BorderSide(
            color: ShadcnColors.error,
            width: ShadcnSpacing.borderWidthFocused,
          ),
        ),
        hintStyle: TextStyle(
          color: ShadcnColors.lightMutedForeground,
          fontSize: 14,
        ),
        labelStyle: TextStyle(
          color: ShadcnColors.lightMutedForeground,
          fontSize: 14,
        ),
      ),

      // ==================== 分割线主题 ====================
      dividerTheme: const DividerThemeData(
        color: ShadcnColors.lightBorder,
        thickness: ShadcnSpacing.borderWidth,
        space: ShadcnSpacing.borderWidth,
      ),

      // ==================== 对话框主题 ====================
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: ShadcnColors.lightCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusLarge),
          side: BorderSide(
            color: ShadcnColors.lightBorder,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
      ),

      // ==================== 文字主题 ====================
      textTheme: const TextTheme(
        // 大标题
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: ShadcnColors.lightForeground,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: ShadcnColors.lightForeground,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.25,
          color: ShadcnColors.lightForeground,
        ),

        // 标题
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: ShadcnColors.lightForeground,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: ShadcnColors.lightForeground,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: ShadcnColors.zinc600,
        ),

        // 正文
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: ShadcnColors.zinc600,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: ShadcnColors.lightMutedForeground,
        ),

        // 标签
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: ShadcnColors.zinc600,
        ),
      ),
    );
  }

  // ==================== 暗色主题 ====================
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.dark(
      // 主色调
      primary: ShadcnColors.primary,
      secondary: ShadcnColors.secondary,

      // Shadcn UI 标准颜色
      surface: ShadcnColors.darkBackground,
      onSurface: ShadcnColors.darkForeground,

      // 错误色
      error: ShadcnColors.error,
      onError: Colors.white,

      // 容器色
      surfaceContainerHighest: ShadcnColors.darkMuted,

      // 轮廓色
      outline: ShadcnColors.darkBorder,
      outlineVariant: ShadcnColors.darkBorder,

      // 反色
      inverseSurface: ShadcnColors.darkForeground,
      onInverseSurface: ShadcnColors.darkBackground,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ShadcnColors.darkBackground,

      // ==================== 卡片主题 ====================
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          side: BorderSide(
            color: ShadcnColors.darkBorder,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
        color: ShadcnColors.darkCard,
        shadowColor: Colors.black,
        surfaceTintColor: Colors.transparent,
      ),

      // ==================== 应用栏主题 ====================
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: ShadcnColors.darkForeground,
        surfaceTintColor: Colors.transparent,
      ),

      // ==================== 填充按钮主题 ====================
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: ShadcnSpacing.buttonPaddingH,
            vertical: ShadcnSpacing.buttonPaddingV,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          overlayColor: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return ShadcnColors.primary.withValues(alpha: 0.1);
            }
            return Colors.transparent;
          }),
        ),
      ),

      // ==================== 轮廓按钮主题 ====================
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: ShadcnSpacing.buttonPaddingH,
            vertical: ShadcnSpacing.buttonPaddingV,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          ),
          side: BorderSide(
            color: ShadcnColors.darkBorder,
            width: ShadcnSpacing.borderWidth,
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          foregroundColor: WidgetStateColor.resolveWith((states) {
            return ShadcnColors.darkForeground;
          }),
          overlayColor: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return ShadcnColors.primary.withValues(alpha: 0.1);
            }
            return Colors.transparent;
          }),
        ),
      ),

      // ==================== 文本按钮主题 ====================
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: ShadcnSpacing.buttonPaddingH,
            vertical: ShadcnSpacing.buttonPaddingV,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          foregroundColor: WidgetStateColor.resolveWith((states) {
            return ShadcnColors.primary;
          }),
        ),
      ),

      // ==================== 输入框主题 ====================
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ShadcnColors.darkBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ShadcnSpacing.inputPaddingH,
          vertical: ShadcnSpacing.inputPaddingV,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          borderSide: BorderSide(
            color: ShadcnColors.darkInput,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          borderSide: BorderSide(
            color: ShadcnColors.darkInput,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          borderSide: BorderSide(
            color: ShadcnColors.primary,
            width: ShadcnSpacing.borderWidthFocused,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          borderSide: BorderSide(
            color: ShadcnColors.error,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          borderSide: BorderSide(
            color: ShadcnColors.error,
            width: ShadcnSpacing.borderWidthFocused,
          ),
        ),
        hintStyle: TextStyle(
          color: ShadcnColors.darkMutedForeground,
          fontSize: 14,
        ),
        labelStyle: TextStyle(
          color: ShadcnColors.darkMutedForeground,
          fontSize: 14,
        ),
      ),

      // ==================== 分割线主题 ====================
      dividerTheme: const DividerThemeData(
        color: ShadcnColors.darkBorder,
        thickness: ShadcnSpacing.borderWidth,
        space: ShadcnSpacing.borderWidth,
      ),

      // ==================== 对话框主题 ====================
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: ShadcnColors.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusLarge),
          side: BorderSide(
            color: ShadcnColors.darkBorder,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
      ),

      // ==================== 文字主题 ====================
      textTheme: const TextTheme(
        // 大标题
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: ShadcnColors.darkForeground,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: ShadcnColors.darkForeground,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.25,
          color: ShadcnColors.darkForeground,
        ),

        // 标题
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: ShadcnColors.darkForeground,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: ShadcnColors.darkForeground,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: ShadcnColors.zinc400,
        ),

        // 正文
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: ShadcnColors.zinc400,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: ShadcnColors.darkMutedForeground,
        ),

        // 标签
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: ShadcnColors.zinc400,
        ),
      ),
    );
  }

  // ==================== 状态颜色获取器 ====================
  static Color get successColor => ShadcnColors.success;
  static Color get warningColor => ShadcnColors.warning;
  static Color get errorColor => ShadcnColors.error;
  static Color get infoColor => ShadcnColors.info;
}
