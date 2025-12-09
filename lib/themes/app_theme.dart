import 'package:flutter/material.dart';

class AppTheme {
  // 现代化配色方案
  static const _primaryColor = Color(0xFF6366F1); // 靛蓝
  static const _secondaryColor = Color(0xFF8B5CF6); // 紫色
  static const _accentColor = Color(0xFF06B6D4); // 青色

  // 状态颜色
  static const _successColor = Color(0xFF10B981);
  static const _warningColor = Color(0xFFF59E0B);
  static const _errorColor = Color(0xFFEF4444);
  static const _infoColor = Color(0xFF3B82F6);

  // 浅色主题
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primaryColor,
      brightness: Brightness.light,
      primary: _primaryColor,
      secondary: _secondaryColor,
      tertiary: _accentColor,
      error: _errorColor,
      surface: const Color(0xFFFAFAFC),
      surfaceContainerHighest: const Color(0xFFF1F5F9),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),

      // 卡片主题
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        color: Colors.white,
      ),

      // 应用栏主题
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF1E293B),
      ),

      // 按钮主题
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.5),
            width: 1.5,
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),

      // 分割线主题
      dividerTheme: DividerThemeData(
        color: Colors.black.withValues(alpha: 0.06),
        thickness: 1,
        space: 1,
      ),

      // 文字主题
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: Color(0xFF0F172A),
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: Color(0xFF0F172A),
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.25,
          color: Color(0xFF0F172A),
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: Color(0xFF1E293B),
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: Color(0xFF1E293B),
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.15,
          color: Color(0xFF334155),
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.15,
          color: Color(0xFF475569),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.25,
          color: Color(0xFF64748B),
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  // 深色主题
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primaryColor,
      brightness: Brightness.dark,
      primary: const Color(0xFF818CF8),
      secondary: const Color(0xFFA78BFA),
      tertiary: const Color(0xFF22D3EE),
      error: _errorColor,
      surface: const Color(0xFF1E293B),
      surfaceContainerHighest: const Color(0xFF334155),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0F172A),

      // 卡片主题
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        color: Color(0xFF1E293B),
      ),

      // 应用栏主题
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFFF1F5F9),
      ),

      // 按钮主题
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.5),
            width: 1.5,
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF334155),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF818CF8), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),

      // 分割线主题
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.1),
        thickness: 1,
        space: 1,
      ),

      // 文字主题
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: Color(0xFFF8FAFC),
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: Color(0xFFF8FAFC),
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.25,
          color: Color(0xFFF1F5F9),
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: Color(0xFFF1F5F9),
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: Color(0xFFE2E8F0),
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.15,
          color: Color(0xFFCBD5E1),
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.15,
          color: Color(0xFFA1B0C5),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.25,
          color: Color(0xFF94A3B8),
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
          color: Color(0xFFA1B0C5),
        ),
      ),
    );
  }

  // 状态颜色获取器
  static Color get successColor => _successColor;
  static Color get warningColor => _warningColor;
  static Color get errorColor => _errorColor;
  static Color get infoColor => _infoColor;
}
