import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 端点卡片（网格单元）。
///
/// 纵向三段式：标题行（名称、优先级）、徽章行、底行（地址与启用开关）。
/// 拖拽排序由外层 ReorderableBuilder 承担，整张卡片都可以拖动；
/// 编辑、克隆、删除等操作收在整卡右键菜单里。
class EndpointCard extends StatelessWidget {
  final EndpointEntity endpoint;
  final bool isForbidden;
  final void Function()? onDelete;
  final void Function()? onEdit;
  final void Function()? onClone;
  final void Function()? onResetCircuitBreaker;
  final void Function(bool)? onToggleEnabled;
  final int index;
  const EndpointCard({
    super.key,
    required this.endpoint,
    this.isForbidden = false,
    this.onEdit,
    this.onDelete,
    this.onClone,
    this.onResetCircuitBreaker,
    this.onToggleEnabled,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ShadcnColors.mutedForeground(theme.brightness);
    final endpoint = this.endpoint;

    // 右键菜单直接挂在整张卡片上，菜单出现在鼠标位置，
    // 不需要再手动判断向上还是向下弹出。
    return ShadContextMenuRegion(
      items: [
        ShadContextMenuItem(
          onPressed: onEdit,
          child: Row(
            children: [
              Icon(LucideIcons.pencil),
              SizedBox(width: 8),
              Text('编辑'),
            ],
          ),
        ),
        ShadContextMenuItem(
          onPressed: onClone,
          child: Row(
            children: [Icon(LucideIcons.copy), SizedBox(width: 8), Text('克隆')],
          ),
        ),
        ShadContextMenuItem(
          onPressed: onDelete,
          child: Row(
            children: [
              Icon(LucideIcons.trash2, color: Colors.red),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
        if (isForbidden)
          ShadContextMenuItem(
            onPressed: onResetCircuitBreaker,
            child: Row(
              children: [
                Icon(LucideIcons.circlePower),
                SizedBox(width: 8),
                Text('恢复'),
              ],
            ),
          ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: ShadCard(
          padding: const EdgeInsets.all(ShadcnSpacing.spacing16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      endpoint.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: ShadcnSpacing.spacing8),
                  Text(
                    '#${index + 1}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
              const SizedBox(height: ShadcnSpacing.spacing8),
              Row(
                spacing: ShadcnSpacing.spacing8,
                children: [
                  if (endpoint.note != null && endpoint.note!.isNotEmpty)
                    Flexible(child: _badge(context, endpoint.note!)),
                  if (endpoint.apiFormat != EndpointApiFormat.anthropic)
                    _badge(context, _apiFormatLabel(endpoint.apiFormat)),
                  if (isForbidden) _badge(context, '断路中'),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: endpoint.baseUrl == null || endpoint.baseUrl!.isEmpty
                        ? const SizedBox.shrink()
                        : ShadTooltip(
                            builder: (context) => Text(endpoint.baseUrl!),
                            child: Text(
                              endpoint.baseUrl!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: ShadcnSpacing.spacing8),
                  ShadSwitch(
                    value: endpoint.enabled,
                    onChanged: onToggleEnabled,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String text) {
    return ShadBadge.secondary(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// 协议格式徽章文案，与端点表单里的选项文案保持一致。
String _apiFormatLabel(EndpointApiFormat format) {
  switch (format) {
    case EndpointApiFormat.anthropic:
      return 'Anthropic';
    case EndpointApiFormat.openaiChat:
      return 'Chat Completions';
    case EndpointApiFormat.openaiResponses:
      return 'Responses';
  }
}
