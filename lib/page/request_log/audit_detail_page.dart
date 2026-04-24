import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:code_proxy/model/audit_detail_entity.dart';
import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/audit_detail_view_model.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

@RoutePage()
class AuditDetailPage extends StatefulWidget {
  final RequestLogEntity log;

  const AuditDetailPage({super.key, required this.log});

  @override
  State<AuditDetailPage> createState() => _AuditDetailPageState();
}

class _AuditDetailPageState extends State<AuditDetailPage> {
  final viewModel = GetIt.instance.get<AuditDetailViewModel>();

  @override
  void initState() {
    super.initState();
    viewModel.init(widget.log);
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(widget.log),
          Expanded(child: _buildContent(widget.log)),
        ],
      );
    });
  }

  Widget _buildHeader(RequestLogEntity log) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing24,
        vertical: ShadcnSpacing.spacing16,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ShadcnColors.zinc100,
            width: ShadcnSpacing.borderWidth,
          ),
        ),
      ),
      child: Row(
        children: [
          ShadIconButton.ghost(
            icon: Icon(LucideIcons.arrowLeft, size: 18),
            onPressed: () => context.router.maybePop(),
          ),
          const SizedBox(width: ShadcnSpacing.spacing12),
          Expanded(child: _buildTitle(log)),
          _buildStatusBadge(log),
        ],
      ),
    );
  }

  Widget _buildTitle(RequestLogEntity log) {
    final time = DateTime.fromMillisecondsSinceEpoch(
      log.timestamp,
    ).toString().substring(0, 19);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: ShadcnSpacing.spacing8,
          children: [
            Text(
              log.method,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: ShadcnColors.primary,
              ),
            ),
            Expanded(
              child: Text(
                log.path,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          spacing: ShadcnSpacing.spacing16,
          children: [
            Text(
              log.endpointName,
              style: TextStyle(
                color: ShadcnColors.lightMutedForeground,
                fontSize: 12,
              ),
            ),
            Text(
              time,
              style: TextStyle(
                color: ShadcnColors.lightMutedForeground,
                fontSize: 12,
              ),
            ),
            if (log.originalModel != null && log.originalModel!.isNotEmpty) ...[
              Text(
                '${log.originalModel} → ${log.model ?? "unknown"}',
                style: TextStyle(
                  color: ShadcnColors.lightMutedForeground,
                  fontSize: 12,
                ),
              ),
            ] else if (log.model != null) ...[
              Text(
                log.model!,
                style: TextStyle(
                  color: ShadcnColors.lightMutedForeground,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStatusBadge(RequestLogEntity log) {
    if (log.statusCode == 200) {
      return ShadBadge.secondary(child: Text('${log.statusCode}'));
    }
    return ShadBadge.destructive(child: Text('${log.statusCode}'));
  }

  Widget _buildContent(RequestLogEntity log) {
    if (viewModel.loading.value) {
      return const Center(child: CircularProgressIndicator());
    }

    if (viewModel.isOldFormat.value) {
      return _buildOldFormatError();
    }

    final detail = viewModel.auditDetail.value;
    if (detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.fileX,
              size: ShadcnSpacing.iconHuge,
              color: ShadcnColors.lightMutedForeground,
            ),
            const SizedBox(height: ShadcnSpacing.spacing16),
            Text(
              '审计数据不可用',
              style: TextStyle(
                color: ShadcnColors.lightMutedForeground,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: ShadcnSpacing.spacing8),
            Text(
              '该请求的审计文件已被清理或尚未生成',
              style: TextStyle(
                color: ShadcnColors.lightMutedForeground,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing24,
        vertical: ShadcnSpacing.spacing16,
      ),
      child: ShadTabs(
        value: 0,
        maintainState: false,
        tabs: [
          ShadTab(
            value: 0,
            expandContent: true,
            content: _buildRequestTab(detail),
            child: Text('请求'),
          ),
          ShadTab(
            value: 1,
            expandContent: true,
            content: _buildResponseTab(detail),
            child: Text('响应'),
          ),
        ],
      ),
    );
  }

  Widget _buildOldFormatError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: ShadcnSpacing.iconHuge,
            color: ShadcnColors.warning,
          ),
          const SizedBox(height: ShadcnSpacing.spacing16),
          const Text(
            '不支持的审计文件格式',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: ShadcnSpacing.spacing8),
          Text(
            '此审计记录使用了旧版格式，无法在应用内查看。',
            style: TextStyle(
              color: ShadcnColors.lightMutedForeground,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: ShadcnSpacing.spacing24),
          ShadButton.destructive(
            onPressed: () {
              showShadDialog(
                context: context,
                builder: (context) => ShadDialog.alert(
                  title: Text('确认删除'),
                  description: Text('确定要删除此旧版审计文件吗？此操作不可恢复。'),
                  actions: [
                    ShadButton.outline(
                      child: Text('取消'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    ShadButton.destructive(
                      child: Text('删除'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        viewModel.deleteOldFormatFile();
                      },
                    ),
                  ],
                ),
              );
            },
            child: Text('删除旧文件'),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTab(AuditDetailEntity detail) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: ShadcnSpacing.spacing8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('请求头'),
          const SizedBox(height: ShadcnSpacing.spacing8),
          _buildHeadersSection(
            detail.originalRequestHeaders,
            detail.forwardedRequestHeaders,
          ),
          const SizedBox(height: ShadcnSpacing.spacing24),
          _buildSectionTitle('请求体'),
          const SizedBox(height: ShadcnSpacing.spacing8),
          _buildBodySection(detail.requestBody),
        ],
      ),
    );
  }

  Widget _buildResponseTab(AuditDetailEntity detail) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: ShadcnSpacing.spacing8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('响应头'),
          const SizedBox(height: ShadcnSpacing.spacing8),
          _buildHeadersSection(
            detail.originalResponseHeaders,
            detail.forwardedResponseHeaders,
          ),
          const SizedBox(height: ShadcnSpacing.spacing24),
          _buildSectionTitle('响应体'),
          const SizedBox(height: ShadcnSpacing.spacing8),
          _buildBodySection(detail.responseBody),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );
  }

  Widget _buildHeadersSection(
    Map<String, String> originalHeaders,
    Map<String, String> forwardedHeaders,
  ) {
    final allKeys = <String>{...originalHeaders.keys, ...forwardedHeaders.keys};

    if (allKeys.isEmpty) {
      return Text(
        '无数据',
        style: TextStyle(color: ShadcnColors.lightMutedForeground),
      );
    }

    final hasDiff = _hasHeadersDiff(originalHeaders, forwardedHeaders);

    if (!hasDiff) {
      return _buildSimpleHeadersTable(originalHeaders);
    }

    return _buildDiffHeadersTable(allKeys, originalHeaders, forwardedHeaders);
  }

  bool _hasHeadersDiff(
    Map<String, String> original,
    Map<String, String> forwarded,
  ) {
    if (original.length != forwarded.length) return true;
    for (final key in original.keys) {
      if (original[key] != forwarded[key]) return true;
    }
    return false;
  }

  Widget _buildSimpleHeadersTable(Map<String, String> headers) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: ShadcnColors.zinc100),
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusSmall),
      ),
      child: Table(
        columnWidths: const {0: FixedColumnWidth(180), 1: FlexColumnWidth()},
        children: headers.entries.map((entry) {
          return TableRow(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: ShadcnColors.zinc100, width: 0.5),
              ),
            ),
            children: [
              _buildHeaderKeyCell(entry.key),
              _buildHeaderValueCell(entry.value),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDiffHeadersTable(
    Set<String> allKeys,
    Map<String, String> originalHeaders,
    Map<String, String> forwardedHeaders,
  ) {
    final sortedKeys = allKeys.toList()..sort();
    final diffKeys = <String>{};
    for (final key in sortedKeys) {
      if (originalHeaders[key] != forwardedHeaders[key]) {
        diffKeys.add(key);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: ShadcnSpacing.spacing16,
          children: [
            _buildDiffLegend(ShadcnColors.primary, '原始'),
            _buildDiffLegend(ShadcnColors.success, '转发'),
            _buildDiffLegend(ShadcnColors.warning, '差异'),
          ],
        ),
        const SizedBox(height: ShadcnSpacing.spacing8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: ShadcnColors.zinc100),
            borderRadius: BorderRadius.circular(ShadcnSpacing.radiusSmall),
          ),
          child: Table(
            columnWidths: const {
              0: FixedColumnWidth(180),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: ShadcnColors.zinc100,
                  border: Border(
                    bottom: BorderSide(color: ShadcnColors.zinc200, width: 0.5),
                  ),
                ),
                children: [
                  _buildTableHeaderCell('Key'),
                  _buildTableHeaderCell('原始值'),
                  _buildTableHeaderCell('转发值'),
                ],
              ),
              ...sortedKeys.map((key) {
                final isDiff = diffKeys.contains(key);
                return TableRow(
                  decoration: BoxDecoration(
                    color: isDiff
                        ? ShadcnColors.warning.withValues(alpha: 0.05)
                        : null,
                    border: Border(
                      bottom: BorderSide(
                        color: ShadcnColors.zinc100,
                        width: 0.5,
                      ),
                    ),
                  ),
                  children: [
                    _buildHeaderKeyCell(key, highlight: isDiff),
                    _buildHeaderValueCell(
                      originalHeaders[key] ?? '—',
                      highlight: isDiff,
                    ),
                    _buildHeaderValueCell(
                      forwardedHeaders[key] ?? '—',
                      highlight: isDiff,
                      isForwarded: true,
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiffLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: color, width: 1),
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing12,
        vertical: ShadcnSpacing.spacing8,
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  Widget _buildHeaderKeyCell(String key, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing12,
        vertical: ShadcnSpacing.spacing8,
      ),
      child: Text(
        key,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: highlight
              ? ShadcnColors.warning
              : ShadcnColors.lightForeground,
          fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildHeaderValueCell(
    String value, {
    bool highlight = false,
    bool isForwarded = false,
  }) {
    final color = highlight
        ? (isForwarded ? ShadcnColors.success : ShadcnColors.primary)
        : ShadcnColors.lightForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing12,
        vertical: ShadcnSpacing.spacing8,
      ),
      child: Text(
        value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: color,
          fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildBodySection(String body) {
    if (body.isEmpty) {
      return Text(
        '无数据',
        style: TextStyle(color: ShadcnColors.lightMutedForeground),
      );
    }

    String displayBody = body;
    try {
      final decoded = jsonDecode(body);
      displayBody = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      // Not JSON, display as-is (SSE stream, plain text, etc.)
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ShadcnColors.zinc950,
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusSmall),
      ),
      padding: const EdgeInsets.all(ShadcnSpacing.spacing16),
      child: SelectableText(
        displayBody,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: ShadcnColors.darkForeground,
        ),
      ),
    );
  }
}
