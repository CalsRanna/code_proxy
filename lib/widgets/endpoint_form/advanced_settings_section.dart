import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 高级设置section
class AdvancedSettingsSection extends StatelessWidget {
  final bool disableNonessentialTraffic;
  final ValueChanged<bool> onDisableNonessentialTrafficChanged;

  const AdvancedSettingsSection({
    super.key,
    required this.disableNonessentialTraffic,
    required this.onDisableNonessentialTrafficChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '高级选项',
          icon: LucideIcons.slidersHorizontal,
        ),
        const SizedBox(height: ShadcnSpacing.spacing12),
        CheckboxListTile(
          title: const Text('禁用非必要流量'),
          subtitle: const Text('减少对该端点的健康检查和测试请求'),
          value: disableNonessentialTraffic,
          onChanged: (value) {
            if (value != null) {
              onDisableNonessentialTrafficChanged(value);
            }
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}
