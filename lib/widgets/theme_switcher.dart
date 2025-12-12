import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsViewModel = GetIt.instance.get<SettingViewModel>();

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
