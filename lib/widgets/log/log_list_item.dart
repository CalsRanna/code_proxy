import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_color_helpers.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:flutter/material.dart';

/// 日志列表项组件
class LogListItem extends StatelessWidget {
  final RequestLog log;
  final VoidCallback onTap;

  const LogListItem({super.key, required this.log, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    // 使用颜色辅助方法获取响应时间颜色
    final responseTimeColor = ShadcnColorHelpers.forResponseTime(
      log.responseTime ?? 0,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: ShadcnSpacing.spacing12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(ShadcnSpacing.spacing16),
          child: Row(
            children: [
              // 时间戳
              SizedBox(
                width: 160,
                child: Text(
                  _formatTime(
                    DateTime.fromMillisecondsSinceEpoch(log.timestamp),
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ShadcnColors.mutedForeground(brightness),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              // 端点名称
              SizedBox(
                width: 160,
                child: Text(
                  log.endpointName,
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 模型
              Expanded(
                child: Text(
                  log.model ?? 'unknown model',
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 状态码
              Container(
                decoration: ShapeDecoration(
                  shape: StadiumBorder(),
                  color: ShadcnColors.muted(brightness),
                ),
                margin: EdgeInsets.only(right: 16),
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  '${log.statusCode}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: log.statusCode == 200
                        ? ShadcnColors.success
                        : ShadcnColors.error,
                  ),
                ),
              ),
              // 响应时间
              SizedBox(
                width: 80,
                child: Text(
                  '${((log.responseTime ?? 0) / 1000).toStringAsFixed(2)}s',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: responseTimeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Token统计
              SizedBox(
                width: 80,
                child: Text(
                  '${log.inputTokens ?? 0} / ${log.outputTokens ?? 0}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ShadcnColors.mutedForeground(brightness),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    return timestamp.toString().substring(0, 19);
  }
}
