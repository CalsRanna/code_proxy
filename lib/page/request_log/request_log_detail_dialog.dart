import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RequestLogDetailDialog extends StatelessWidget {
  final RequestLogEntity log;
  final VoidCallback? onAudit;

  const RequestLogDetailDialog({super.key, required this.log, this.onAudit});

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: Row(
        spacing: ShadcnSpacing.spacing16,
        children: [
          Text('${log.method} ${log.path}'),
          if (log.statusCode == 200)
            ShadBadge.secondary(child: Text(log.statusCode.toString())),
          if (log.statusCode != 200)
            ShadBadge.destructive(child: Text(log.statusCode.toString())),
          if (onAudit != null)
            ShadButton.link(
              onPressed: onAudit,
              size: ShadButtonSize.sm,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  Icon(LucideIcons.fileSearch, size: 14),
                  Text('审计'),
                ],
              ),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildListItem(
              icon: LucideIcons.shell,
              label: '端点',
              value: log.endpointName,
            ),
            _buildListItem(
              icon: LucideIcons.clock,
              label: '时间',
              value: DateTime.fromMillisecondsSinceEpoch(
                log.timestamp,
              ).toString(),
            ),
            _buildListItem(
              icon: LucideIcons.timer,
              label: '响应时间',
              value: '${log.responseTime ?? 0}ms',
            ),
            if (log.originalModel != null && log.originalModel!.isNotEmpty)
              _buildListItem(
                icon: LucideIcons.tag,
                label: '原始模型',
                value: log.originalModel!,
              ),
            _buildListItem(
              icon: LucideIcons.brain,
              label: '模型',
              value: log.model ?? 'unknown',
            ),
            if (log.statusCode == 200) ...[
              _buildTokenItem(log),
              _buildListItem(
                icon: LucideIcons.cloudDownload,
                label: '输出Token',
                value: '${log.outputTokens}',
              ),
            ],
            if (log.statusCode != 200)
              _buildListItem(
                icon: LucideIcons.circleAlert,
                label: '错误信息',
                maxLines: null,
                value: '${log.errorMessage}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenItem(RequestLogEntity log) {
    final input = log.inputTokens ?? 0;
    final cacheCreate = log.cacheCreationInputTokens ?? 0;
    final cacheRead = log.cacheReadInputTokens ?? 0;
    final total = input + cacheCreate + cacheRead;
    final hasCache = cacheCreate > 0 || cacheRead > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: ShadcnSpacing.spacing16,
        children: [
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: ShadcnSpacing.spacing4,
              children: [
                Icon(
                  LucideIcons.cloudUpload,
                  color: ShadcnColors.lightMutedForeground,
                  size: 16,
                ),
                const Text('输入Token'),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Text('$total'),
                if (hasCache) ...[
                  const SizedBox(width: 4),
                  ShadTooltip(
                    anchor: const ShadAnchor(
                      childAlignment: Alignment.centerLeft,
                      overlayAlignment: Alignment.centerRight,
                      offset: Offset(4, 0),
                    ),
                    builder: (context) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '未缓存: $input',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Text(
                          '缓存创建: $cacheCreate',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Text(
                          '缓存读取: $cacheRead',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    child: ShadGestureDetector(
                      child: Icon(
                        LucideIcons.info,
                        size: 14,
                        color: ShadcnColors.lightMutedForeground,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem({
    IconData? icon,
    required String label,
    int? maxLines = 1,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: ShadcnSpacing.spacing16,
        children: [
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: ShadcnSpacing.spacing4,
              children: [
                if (icon != null)
                  Icon(
                    icon,
                    color: ShadcnColors.lightMutedForeground,
                    size: 16,
                  ),
                Text(label),
              ],
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}