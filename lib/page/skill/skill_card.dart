import 'package:code_proxy/model/skill_entity.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class SkillCard extends StatefulWidget {
  final SkillEntity skill;
  final void Function()? onUninstall;

  const SkillCard({super.key, required this.skill, this.onUninstall});

  @override
  State<SkillCard> createState() => _SkillCardState();
}

class _SkillCardState extends State<SkillCard> {
  final controller = ShadPopoverController();
  final _buttonKey = GlobalKey();
  bool _showAbove = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      final position = box.localToGlobal(Offset.zero);
      final screenHeight = MediaQuery.of(context).size.height;
      final spaceBelow = screenHeight - position.dy - box.size.height;
      final needAbove = spaceBelow < 150;
      if (needAbove != _showAbove) {
        setState(() => _showAbove = needAbove);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.toggle();
        });
        return;
      }
    }
    controller.toggle();
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
                  childAlignment: _showAbove
                      ? Alignment.bottomRight
                      : Alignment.topRight,
                  overlayAlignment: _showAbove
                      ? Alignment.topRight
                      : Alignment.bottomRight,
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
                  key: _buttonKey,
                  icon: const Icon(LucideIcons.ellipsis),
                  onPressed: _toggleMenu,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
