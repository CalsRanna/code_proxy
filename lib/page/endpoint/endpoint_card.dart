import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class EndpointCard extends StatefulWidget {
  final EndpointEntity endpoint;
  final void Function()? onDelete;
  final void Function()? onEdit;
  final void Function(bool)? onToggleEnabled;
  const EndpointCard({
    super.key,
    required this.endpoint,
    this.onEdit,
    this.onDelete,
    this.onToggleEnabled,
  });

  @override
  State<EndpointCard> createState() => _EndpointCardState();
}

class _EndpointCardState extends State<EndpointCard> {
  final controller = ShadPopoverController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.endpoint.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                if (widget.endpoint.anthropicBaseUrl != null &&
                    widget.endpoint.anthropicBaseUrl!.isNotEmpty)
                  Text(
                    widget.endpoint.anthropicBaseUrl!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ShadcnColors.mutedForeground(
                        Theme.of(context).brightness,
                      ),
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (widget.endpoint.note != null &&
                    widget.endpoint.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.endpoint.note!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: ShadcnSpacing.spacing16),
          ShadSwitch(
            value: widget.endpoint.enabled,
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
                    Icon(LucideIcons.pencil, size: 20),
                    SizedBox(width: 8),
                    Text('编辑'),
                  ],
                ),
              ),
              ShadContextMenuItem(
                onPressed: widget.onDelete,
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 20, color: Colors.red),
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
    );
  }
}
