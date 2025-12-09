import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/widgets/modern_dropdown.dart';
import 'package:code_proxy/widgets/modern_text_field.dart';
import 'package:flutter/material.dart';

/// 基本信息section
class BasicInfoSection extends StatelessWidget {
  final TextEditingController nameController;
  final String category;
  final ValueChanged<String?> onCategoryChanged;
  final TextEditingController notesController;

  const BasicInfoSection({
    super.key,
    required this.nameController,
    required this.category,
    required this.onCategoryChanged,
    required this.notesController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: '基本信息',
          icon: Icons.info_outline,
        ),
        const SizedBox(height: ShadcnSpacing.spacing12),
        ModernTextField(
          controller: nameController,
          label: '端点名称',
          hint: '例如：Anthropic Official',
          prefixIcon: Icons.label_outline_rounded,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入端点名称';
            }
            return null;
          },
        ),
        const SizedBox(height: ShadcnSpacing.spacing16),
        ModernDropdown<String>(
          value: category,
          label: '分类',
          items: const [
            DropdownMenuItem(value: 'official', child: Text('官方API')),
            DropdownMenuItem(value: 'aggregator', child: Text('第三方聚合')),
            DropdownMenuItem(value: 'custom', child: Text('自定义')),
          ],
          onChanged: onCategoryChanged,
          prefixIcon: Icons.category_outlined,
        ),
        const SizedBox(height: ShadcnSpacing.spacing16),
        ModernTextField(
          controller: notesController,
          label: '备注',
          hint: '可选的备注信息',
          prefixIcon: Icons.edit_note,
          maxLines: 2,
        ),
      ],
    );
  }
}
