import 'dart:convert';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    final brightness = Theme.of(context).brightness;

    return Dialog(
      elevation: 0,
      backgroundColor: ShadcnColors.card(brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
      ),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
          border: Border.all(
            color: ShadcnColors.border(brightness),
            width: ShadcnSpacing.borderWidth,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogDetailHeader(log: log),
            Divider(
              height: 1,
              thickness: 1,
              color: ShadcnColors.border(brightness),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LogDetailSection(
                      title: '基本信息',
                      icon: LucideIcons.info,
                      children: [
                        InfoRow(
                          label: '端点',
                          value: log.endpointName,
                          icon: LucideIcons.server,
                        ),
                        InfoRow(
                          label: '时间',
                          value: _formatFullTime(DateTime.fromMillisecondsSinceEpoch(log.timestamp)),
                          icon: LucideIcons.clock,
                        ),
                        InfoRow(
                          label: '状态码',
                          value: '${log.statusCode ?? 0}',
                          icon: LucideIcons.code,
                        ),
                        InfoRow(
                          label: '响应时间',
                          value: '${log.responseTime ?? 0}ms',
                          icon: LucideIcons.timer,
                        ),
                        InfoRow(
                          label: '模型',
                          value: log.model ?? 'unknown',
                          icon: LucideIcons.brain,
                        ),
                      ],
                    ),
                    const SizedBox(height: ShadcnSpacing.spacing24),
                    LogDetailSection(
                      title: 'Token使用',
                      icon: LucideIcons.activity,
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
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Padding(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing20),
      child: Row(
        children: [
          // 状态图标 - 极简设计
          Icon(
            log.success ? Icons.check_circle_rounded : Icons.error_rounded,
            color: log.success ? ShadcnColors.success : ShadcnColors.error,
            size: 20,
          ),
          const SizedBox(width: ShadcnSpacing.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log.method} ${log.path}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  log.success ? '请求成功' : '请求失败',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ShadcnColors.mutedForeground(brightness),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              foregroundColor: ShadcnColors.mutedForeground(brightness),
            ),
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
