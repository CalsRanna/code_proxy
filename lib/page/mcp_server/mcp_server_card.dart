import 'package:code_proxy/model/mcp_server_entity.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class McpServerCard extends StatefulWidget {
  final McpServerEntity server;
  final void Function()? onEdit;
  final void Function()? onDelete;
  final void Function(bool)? onToggleEnabled;

  const McpServerCard({
    super.key,
    required this.server,
    this.onEdit,
    this.onDelete,
    this.onToggleEnabled,
  });

  @override
  State<McpServerCard> createState() => _McpServerCardState();
}

class _McpServerCardState extends State<McpServerCard> {
  final controller = ShadPopoverController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isStdio = widget.server.config.type == McpTransportType.stdio;
    final configDescription = isStdio
        ? '${widget.server.config.command} ${(widget.server.config.args ?? []).join(' ')}'
        : widget.server.config.url ?? '';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: EdgeInsetsGeometry.symmetric(vertical: ShadcnSpacing.spacing8),
        child: ShadCard(
          padding: EdgeInsets.all(ShadcnSpacing.spacing16),
          child: Row(
            children: [
              Icon(
                isStdio ? LucideIcons.terminal : LucideIcons.globe,
                color: widget.server.enabled
                    ? null
                    : ShadcnColors.mutedForeground(
                        Theme.of(context).brightness,
                      ),
              ),
              const SizedBox(width: ShadcnSpacing.spacing16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      spacing: ShadcnSpacing.spacing8,
                      children: [
                        Text(
                          widget.server.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        ShadBadge.secondary(
                          child: Text(
                            widget.server.config.type.toJsonValue(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.server.id,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ShadcnColors.mutedForeground(
                          Theme.of(context).brightness,
                        ),
                      ),
                    ),
                    if (configDescription.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        configDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ShadcnColors.mutedForeground(
                            Theme.of(context).brightness,
                          ),
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: ShadcnSpacing.spacing16),
              ShadSwitch(
                value: widget.server.enabled,
                onChanged: widget.onToggleEnabled,
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
                    onPressed: widget.onEdit,
                    child: Row(
                      children: [
                        Icon(LucideIcons.pencil),
                        SizedBox(width: 8),
                        Text('编辑'),
                      ],
                    ),
                  ),
                  ShadContextMenuItem(
                    onPressed: widget.onDelete,
                    child: Row(
                      children: [
                        Icon(LucideIcons.trash2, color: Colors.red),
                        SizedBox(width: 8),
                        Text('删除', style: TextStyle(color: Colors.red)),
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
