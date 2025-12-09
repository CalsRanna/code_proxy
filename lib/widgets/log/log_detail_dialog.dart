import 'dart:convert';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_color_helpers.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:flutter/material.dart';

/// 日志详情对话框
class LogDetailDialog extends StatelessWidget {
  final RequestLog log;

  const LogDetailDialog({super.key, required this.log});

  static void show(BuildContext context, RequestLog log) {
    showDialog(
      context: context,
      builder: (context) => LogDetailDialog(log: log),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusLarge),
      ),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogDetailHeader(log: log),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ShadcnSpacing.spacing20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LogDetailSection(
                      title: '基本信息',
                      icon: Icons.info_outline,
                      children: [
                        InfoRow(
                          label: '端点',
                          value: log.endpointName,
                          icon: Icons.dns_outlined,
                        ),
                        InfoRow(
                          label: '时间',
                          value: _formatFullTime(DateTime.fromMillisecondsSinceEpoch(log.timestamp)),
                          icon: Icons.access_time,
                        ),
                        InfoRow(
                          label: '状态码',
                          value: '${log.statusCode ?? 0}',
                          icon: Icons.code,
                        ),
                        InfoRow(
                          label: '响应时间',
                          value: '${log.responseTime ?? 0}ms',
                          icon: Icons.timer_outlined,
                        ),
                        InfoRow(
                          label: '模型',
                          value: log.model ?? 'unknown',
                          icon: Icons.psychology_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: ShadcnSpacing.spacing24),
                    LogDetailSection(
                      title: 'Token使用',
                      icon: Icons.data_usage_outlined,
                      children: [
                        InfoRow(
                          label: '输入Token',
                          value: '${log.inputTokens ?? 0}',
                        ),
                        InfoRow(
                          label: '输出Token',
                          value: '${log.outputTokens ?? 0}',
                        ),
                        InfoRow(
                          label: '总计',
                          value: '${(log.inputTokens ?? 0) + (log.outputTokens ?? 0)}',
                        ),
                      ],
                    ),
                    if (log.rawHeader != null) ...[
                      const SizedBox(height: ShadcnSpacing.spacing24),
                      LogDetailSection(
                        title: '原始请求头',
                        icon: Icons.http_outlined,
                        children: [
                          _buildCodeBlock(
                            context,
                            _formatJson(log.rawHeader!),
                          ),
                        ],
                      ),
                    ],
                    if (log.rawRequest != null) ...[
                      const SizedBox(height: ShadcnSpacing.spacing24),
                      LogDetailSection(
                        title: '原始请求',
                        icon: Icons.upload_outlined,
                        children: [
                          _buildCodeBlock(
                            context,
                            _formatJson(log.rawRequest!),
                          ),
                        ],
                      ),
                    ],
                    if (log.rawResponse != null) ...[
                      const SizedBox(height: ShadcnSpacing.spacing24),
                      LogDetailSection(
                        title: '原始响应',
                        icon: Icons.download_outlined,
                        children: [
                          _buildCodeBlock(
                            context,
                            _formatJson(log.rawResponse!),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, String content) {
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing12),
      decoration: BoxDecoration(
        color: ShadcnColors.muted(brightness),
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
        border: Border.all(
          color: ShadcnColors.border(brightness),
          width: ShadcnSpacing.borderWidth,
        ),
      ),
      child: SelectableText(
        content,
        style: const TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  String _formatJson(String json) {
    try {
      final decoded = jsonDecode(json);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (e) {
      return json;
    }
  }

  String _formatFullTime(DateTime timestamp) {
    return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-'
        '${timestamp.day.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }
}

/// 日志详情标题栏
class LogDetailHeader extends StatelessWidget {
  final RequestLog log;

  const LogDetailHeader({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final statusColors = ShadcnColorHelpers.forStatus(
      log.success ? StatusType.success : StatusType.error,
      brightness,
    );

    return Container(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing20),
      decoration: BoxDecoration(
        color: statusColors.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(ShadcnSpacing.radiusLarge),
          topRight: Radius.circular(ShadcnSpacing.radiusLarge),
        ),
      ),
      child: Row(
        children: [
          IconBadge(
            icon: log.success ? Icons.check_circle : Icons.error,
            color: statusColors.foreground,
            size: IconBadgeSize.medium,
          ),
          const SizedBox(width: ShadcnSpacing.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log.method} ${log.path}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  log.success ? '请求成功' : '请求失败',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColors.foreground,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// 日志详情信息段落
class LogDetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const LogDetailSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, icon: icon),
        const SizedBox(height: ShadcnSpacing.spacing12),
        ...children,
      ],
    );
  }
}
