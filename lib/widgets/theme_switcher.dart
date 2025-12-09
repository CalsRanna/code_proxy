import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../di.dart';
import '../view_model/settings_view_model.dart';
import '../themes/shadcn_spacing.dart';

/// Shadcn UI 风格的主题切换器
/// 支持在亮色、暗色和跟随系统之间切换
class ThemeSwitcher extends StatelessWidget {
  /// 是否显示为紧凑模式（仅图标）
  final bool compact;

  /// 是否显示标签文字
  final bool showLabel;

  const ThemeSwitcher({
    super.key,
    this.compact = true,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    // 从 DI 获取 SettingsViewModel 工厂，创建实例用于主题切换
    final settingsViewModel = getIt<SettingsViewModel>();
    final theme = Theme.of(context);

    return Watch((context) {
      final brightness = Theme.of(context).brightness;
      final currentTheme = SettingsViewModel.currentTheme.value;

      return Tooltip(
        message: '当前主题: ${_getThemeDisplayName(currentTheme)}\n点击切换主题',
        child: InkWell(
          onTap: () => settingsViewModel.toggleTheme(),
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          child: Container(
            padding: EdgeInsets.all(compact ? 8 : 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.dividerColor,
                width: ShadcnSpacing.borderWidth,
              ),
              borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
            ),
            child: showLabel
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildIcon(brightness),
                      const SizedBox(width: 8),
                      Text(
                        _getThemeDisplayName(currentTheme),
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  )
                : _buildIcon(brightness),
          ),
        ),
      );
    });
  }

  Widget _buildIcon(Brightness brightness) {
    // 根据当前实际主题显示图标（不是模式，而是实际生效的主题）
    return Icon(
      brightness == Brightness.dark ? LucideIcons.moon : LucideIcons.sun,
      size: ShadcnSpacing.iconMedium,
    );
  }

  String _getThemeDisplayName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '暗色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }
}
