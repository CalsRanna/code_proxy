import 'package:code_proxy/model/skill_entity.dart';
import 'package:code_proxy/page/skill/skill_card.dart';
import 'package:code_proxy/page/skill/skill_install_dialog.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/skill_view_model.dart';
import 'package:code_proxy/widget/page_header.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

class SkillPage extends StatefulWidget {
  const SkillPage({super.key});

  @override
  State<SkillPage> createState() => _SkillPageState();
}

class _SkillPageState extends State<SkillPage> {
  final viewModel = GetIt.instance.get<SkillViewModel>();

  @override
  Widget build(BuildContext context) {
    final refreshButton = Watch((context) {
      final isLoading = viewModel.isLoading.value;
      return ShadButton.ghost(
        onPressed: isLoading ? null : () => viewModel.initSignals(),
        child: isLoading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  const Text('刷新中...'),
                ],
              )
            : const Text('刷新'),
      );
    });

    final addButton = ShadButton(
      onPressed: () => _showInstallDialog(context),
      leading: const Icon(LucideIcons.plus),
      child: const Text('添加技能'),
    );

    final pageHeader = Watch((context) {
      return PageHeader(
        title: '技能',
        subtitle: '${viewModel.skills.value.length} 个技能',
        actions: [
          refreshButton,
          const SizedBox(width: ShadcnSpacing.spacing8),
          addButton,
        ],
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeader,
        Expanded(
          child: Watch((context) {
            if (viewModel.isLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }

            final skills = viewModel.skills.value;
            if (skills.isEmpty) {
              return _buildEmptyState();
            }

            return _buildSkillsList(skills.values.toList());
          }),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.sparkles,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无 Skills',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角按钮从 GitHub 添加 Skill',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '官方 Skills: github.com/anthropics/skills',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillsList(List<SkillEntity> skills) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing24,
        vertical: ShadcnSpacing.spacing8,
      ),
      itemCount: skills.length,
      itemBuilder: (context, index) {
        final skill = skills[index];
        return SkillCard(
          key: ValueKey(skill.id),
          skill: skill,
          onUninstall: () => _showUninstallDialog(context, skill),
        );
      },
    );
  }

  void _showInstallDialog(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (context) => SkillInstallDialog(viewModel: viewModel),
    );
  }

  void _showUninstallDialog(BuildContext context, SkillEntity skill) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('确认移除'),
        description: Padding(
          padding: const EdgeInsets.only(bottom: ShadcnSpacing.spacing8),
          child: Text('确定要移除 Skill "${skill.name}" 吗？此操作无法撤销。'),
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ShadButton(
            onPressed: () async {
              await viewModel.uninstallSkill(skill.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }
}
