import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';

/// Shadcn UI 风格的应用主题
/// 采用中性灰色调、细边框、微妙阴影的现代设计语言
class AppTheme {
  static Color get errorColor => ShadcnColors.error;
  static Color get infoColor => ShadcnColors.info;

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.light(
      primary: ShadcnColors.primary,
      secondary: ShadcnColors.secondary,
      surface: ShadcnColors.lightBackground,
      onSurface: ShadcnColors.lightForeground,
      error: ShadcnColors.error,
      onError: Colors.white,
      surfaceContainerHighest: ShadcnColors.lightMuted,
      outline: ShadcnColors.lightBorder,
      outlineVariant: ShadcnColors.lightBorder,
      inverseSurface: ShadcnColors.lightForeground,
      onInverseSurface: ShadcnColors.lightBackground,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ShadcnColors.lightBackground,
      cardTheme: CardThemeData(
        elevation: 0,
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
      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: ShadcnColors.lightForeground,
        surfaceTintColor: Colors.transparent,
      ),
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
          overlayColor: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return ShadcnColors.primary.withValues(alpha: 0.1);
            }
            return Colors.transparent;
          }),
        ),
      ),
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
      dividerTheme: const DividerThemeData(
        color: ShadcnColors.lightBorder,
        thickness: ShadcnSpacing.borderWidth,
        space: ShadcnSpacing.borderWidth,
      ),
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
      textTheme: const TextTheme(
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
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: ShadcnColors.zinc600,
        ),
      ),
    );
  }

  static Color get successColor => ShadcnColors.success;
  static Color get warningColor => ShadcnColors.warning;
}
