import 'package:code_proxy/model/skill_entity.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SkillCard extends StatefulWidget {
  final SkillEntity skill;
  final void Function()? onUninstall;

  const SkillCard({
    super.key,
    required this.skill,
    this.onUninstall,
  });

  @override
  State<SkillCard> createState() => _SkillCardState();
}

class _SkillCardState extends State<SkillCard> {
  final controller = ShadPopoverController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: EdgeInsetsGeometry.symmetric(vertical: ShadcnSpacing.spacing8),
        child: ShadCard(
          padding: EdgeInsets.all(ShadcnSpacing.spacing16),
          child: Row(
            children: [
              Icon(LucideIcons.sparkles),
              const SizedBox(width: ShadcnSpacing.spacing16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.skill.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.skill.id,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ShadcnColors.mutedForeground(
                          Theme.of(context).brightness,
                        ),
                      ),
                    ),
                    if (widget.skill.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.skill.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ShadcnColors.mutedForeground(
                            Theme.of(context).brightness,
                          ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (widget.skill.sourceUrl != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.skill.sourceUrl!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ShadcnColors.mutedForeground(
                            Theme.of(context).brightness,
                          ),
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: ShadcnSpacing.spacing16),
              ShadContextMenu(
                anchor: ShadAnchor(
                  childAlignment: Alignment.topRight,
                  overlayAlignment: Alignment.bottomRight,
                ),
                controller: controller,
                items: [
                  ShadContextMenuItem(
                    onPressed: widget.onUninstall,
                    child: Row(
                      children: [
                        Icon(LucideIcons.trash2, color: Colors.red),
                        SizedBox(width: 8),
                        Text('移除', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                child: ShadIconButton.ghost(
                  icon: const Icon(LucideIcons.ellipsis),
                  onPressed: controller.toggle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
