import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';
import '../di.dart';
import '../view_model/settings_view_model.dart';
import '../themes/shadcn_spacing.dart';

class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsViewModel = getIt<SettingsViewModel>();

    return Watch((context) {
      final brightness = Theme.of(context).brightness;

      return ShadIconButton.ghost(
        onPressed: () => settingsViewModel.toggleTheme(),
        icon: _buildIcon(brightness),
      );
    });
  }

  Widget _buildIcon(Brightness brightness) {
    return Icon(
      brightness == Brightness.dark ? LucideIcons.moon : LucideIcons.sun,
      size: ShadcnSpacing.iconMedium,
    );
  }
}
