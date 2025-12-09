import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/widgets/modern_dropdown.dart';
import 'package:code_proxy/widgets/modern_text_field.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// API配置section
class ApiConfigSection extends StatelessWidget {
  final TextEditingController authTokenController;
  final TextEditingController baseUrlController;
  final String authMode;
  final ValueChanged<String?> onAuthModeChanged;
  final TextEditingController timeoutController;

  const ApiConfigSection({
    super.key,
    required this.authTokenController,
    required this.baseUrlController,
    required this.authMode,
    required this.onAuthModeChanged,
    required this.timeoutController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Claude API配置',
          icon: LucideIcons.key,
        ),
        const SizedBox(height: ShadcnSpacing.spacing12),
        ModernTextField(
          controller: authTokenController,
          label: 'API Key',
          hint: '输入您的API密钥',
          prefixIcon: LucideIcons.keyRound,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入API Key';
            }
            return null;
          },
        ),
        const SizedBox(height: ShadcnSpacing.spacing16),
        ModernTextField(
          controller: baseUrlController,
          label: 'Base URL',
          hint: '例如：https://api.anthropic.com',
          prefixIcon: LucideIcons.link,
        ),
        const SizedBox(height: ShadcnSpacing.spacing16),
        ModernDropdown<String>(
          value: authMode,
          label: '认证模式',
          items: const [
            DropdownMenuItem(
              value: 'standard',
              child: Text('标准模式（x-api-key）'),
            ),
            DropdownMenuItem(
              value: 'bearer_only',
              child: Text('Bearer Token模式'),
            ),
          ],
          onChanged: onAuthModeChanged,
          prefixIcon: LucideIcons.shield,
        ),
        const SizedBox(height: ShadcnSpacing.spacing16),
        ModernTextField(
          controller: timeoutController,
          label: '超时时间（毫秒）',
          hint: '600000',
          prefixIcon: LucideIcons.clock,
          validator: (value) {
            if (value != null && value.isNotEmpty) {
              if (int.tryParse(value) == null) {
                return '请输入有效的数字';
              }
            }
            return null;
          },
        ),
      ],
    );
  }
}
