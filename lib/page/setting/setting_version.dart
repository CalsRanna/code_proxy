import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class SettingVersion extends StatelessWidget {
  final SettingViewModel viewModel;

  const SettingVersion({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing16),
        child: Center(
          child: Text(
            'Code Proxy ${viewModel.version.value}',
            style: TextStyle(fontSize: 12, color: ShadcnColors.zinc400),
          ),
        ),
      );
    });
  }
}
