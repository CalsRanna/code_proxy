import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class RequestLogDetailDialog extends StatelessWidget {
  final RequestLogEntity log;

  const RequestLogDetailDialog({super.key, required this.log});

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
            if (log.originalModel != null &&
                log.originalModel!.isNotEmpty)
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
            // 失败请求显示错误信息
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
