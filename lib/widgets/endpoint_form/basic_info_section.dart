import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/widgets/modern_text_field.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 基本信息section
class BasicInfoSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController noteController;
  final TextEditingController weightController;

  const BasicInfoSection({
    super.key,
    required this.nameController,
    required this.noteController,
    required this.weightController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '基本信息', icon: LucideIcons.info),
        const SizedBox(height: ShadcnSpacing.spacing12),
        Row(
          spacing: ShadcnSpacing.spacing16,
          children: [
            Expanded(
              child: ModernTextField(
                controller: nameController,
                label: '端点名称',
                hint: '例如：Anthropic Official',
                prefixIcon: LucideIcons.tag,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入端点名称';
                  }
                  return null;
                },
              ),
            ),
            Expanded(
              child: ModernTextField(
                controller: noteController,
                label: '备注',
                hint: '可选的备注信息',
                prefixIcon: LucideIcons.fileText,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
