import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RequestLogDetailDialog extends StatelessWidget {
  final RequestLog log;

  const RequestLogDetailDialog({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: Row(
        spacing: ShadcnSpacing.spacing16,
        children: [
          Text('${log.method} ${log.path}'),
          ShadBadge.secondary(child: Text(log.statusCode.toString())),
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
            _buildListItem(
              icon: LucideIcons.brain,
              label: '模型',
              value: log.model ?? 'unknown',
            ),
            _buildListItem(
              icon: LucideIcons.cloudUpload,
              label: '输入Token',
              value: '${log.inputTokens}',
            ),
            _buildListItem(
              icon: LucideIcons.cloudDownload,
              label: '输出Token',
              value: '${log.outputTokens}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem({
    IconData? icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: ShadcnSpacing.spacing16,
        children: [
          SizedBox(
            width: 100,
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
            child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
