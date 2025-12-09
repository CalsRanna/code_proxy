import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/widgets/modern_text_field.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 模型配置section
class ModelConfigSection extends StatelessWidget {
  final TextEditingController modelController;
  final TextEditingController smallFastModelController;
  final TextEditingController haikuModelController;
  final TextEditingController sonnetModelController;
  final TextEditingController opusModelController;

  const ModelConfigSection({
    super.key,
    required this.modelController,
    required this.smallFastModelController,
    required this.haikuModelController,
    required this.sonnetModelController,
    required this.opusModelController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: '模型配置',
          icon: LucideIcons.brain,
        ),
        const SizedBox(height: ShadcnSpacing.spacing12),
        ModernTextField(
          controller: modelController,
          label: '主模型',
          hint: '例如：claude-3-5-sonnet-20241022',
          prefixIcon: LucideIcons.rocket,
        ),
        const SizedBox(height: ShadcnSpacing.spacing16),
        ModernTextField(
          controller: smallFastModelController,
          label: '快速模型',
          hint: '例如：claude-3-5-haiku-20241022',
          prefixIcon: LucideIcons.zap,
        ),
        const SizedBox(height: ShadcnSpacing.spacing16),
        ModernTextField(
          controller: haikuModelController,
          label: 'Haiku模型',
          hint: '例如：claude-3-5-haiku-20241022',
          prefixIcon: LucideIcons.gauge,
        ),
        const SizedBox(height: ShadcnSpacing.spacing16),
        ModernTextField(
          controller: sonnetModelController,
          label: 'Sonnet模型',
          hint: '例如：claude-3-5-sonnet-20241022',
          prefixIcon: LucideIcons.bolt,
        ),
        const SizedBox(height: ShadcnSpacing.spacing16),
        ModernTextField(
          controller: opusModelController,
          label: 'Opus模型',
          hint: '例如：claude-opus-4-20250514',
          prefixIcon: LucideIcons.sparkles,
        ),
      ],
    );
  }
}
