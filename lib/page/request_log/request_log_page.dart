import 'package:auto_route/auto_route.dart';
import 'package:code_proxy/page/request_log/request_log_detail_dialog.dart';
import 'package:code_proxy/page/request_log/request_log_pagination.dart';
import 'package:code_proxy/router/router.gr.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/request_log_view_model.dart';
import 'package:code_proxy/widget/page_header.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

class RequestLogPage extends StatefulWidget {
  const RequestLogPage({super.key});

  @override
  State<RequestLogPage> createState() => _RequestLogPageState();
}

class _RequestLogPageState extends State<RequestLogPage> {
  final viewModel = GetIt.instance.get<RequestLogViewModel>();
  final _filterController = ShadPopoverController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var body = Watch((context) {
      final logs = viewModel.logs.value;
      return logs.isEmpty ? _buildEmpty() : _buildTable();
    });
    var pageHeader = Watch((context) {
      final total = viewModel.total.value;
      return PageHeader(title: '请求', subtitle: '$total 条请求记录');
    });
    var children = [pageHeader, Expanded(child: body)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildEmpty() {
    return Center(child: Text('暂无数据'));
  }

  Widget _buildPagination() {
    final currentPage = viewModel.currentPage.value;
    final total = viewModel.total.value;
    final pageSize = viewModel.pageSize.value;
    return RequestLogPagination(
      currentPage: currentPage,
      total: total,
      pageSize: pageSize,
      onPageChanged: viewModel.paginate,
      onPageSizeChanged: viewModel.setPageSize,
    );
  }

  Widget _buildStatusCodeHeader() {
    final filter = viewModel.statusCodeFilter.value;
    final brightness = Theme.of(context).brightness;
    final isActive = filter != null;

    return ShadContextMenu(
      anchor: ShadAnchor(
        childAlignment: Alignment.topLeft,
        overlayAlignment: Alignment.bottomLeft,
      ),
      controller: _filterController,
      items: [
        ShadContextMenuItem(
          onPressed: () {
            viewModel.setStatusCodeFilter(null);
            _filterController.hide();
          },
          child: Row(
            spacing: 8,
            children: [
              SizedBox(
                width: 16,
                child: filter == null
                    ? Icon(LucideIcons.check, size: 14)
                    : null,
              ),
              Text('全部'),
            ],
          ),
        ),
        ShadContextMenuItem(
          onPressed: () {
            viewModel.setStatusCodeFilter(200);
            _filterController.hide();
          },
          child: Row(
            spacing: 8,
            children: [
              SizedBox(
                width: 16,
                child: filter == 200 ? Icon(LucideIcons.check, size: 14) : null,
              ),
              Text('成功'),
            ],
          ),
        ),
        ShadContextMenuItem(
          onPressed: () {
            viewModel.setStatusCodeFilter(-1);
            _filterController.hide();
          },
          child: Row(
            spacing: 8,
            children: [
              SizedBox(
                width: 16,
                child: filter == -1 ? Icon(LucideIcons.check, size: 14) : null,
              ),
              Text('失败'),
            ],
          ),
        ),
      ],
      child: GestureDetector(
        onTap: _filterController.toggle,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Text(
                '状态码',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: isActive ? ShadcnColors.primary : null,
                ),
              ),
              Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: isActive
                    ? ShadcnColors.primary
                    : ShadcnColors.mutedForeground(brightness),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    final logs = viewModel.logs.value;
    var layoutBuilder = LayoutBuilder(
      builder: (context, constraints) {
        return ShadTable(
          builder: (context, index) {
            var log = logs[index.row];
            var time = DateTime.fromMillisecondsSinceEpoch(log.timestamp);
            var statusCode = log.statusCode;
            var tokenText = '${log.inputTokens} / ${log.outputTokens}';
            Widget child;
            switch (index.column) {
              case 0:
                child = Text(
                  time.toString().substring(0, 19),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
                break;
              case 1:
                child = Text(
                  log.endpointName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
                break;
              case 2:
                child = Text(
                  log.model ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
                break;
              case 3:
                child = statusCode == 200
                    ? ShadBadge.secondary(
                        child: Text(statusCode.toString()))
                    : ShadBadge.destructive(
                        child: Text(statusCode.toString()));
                break;
              case 4:
                child = Text(
                  '${((log.responseTime ?? 0) / 1000).toStringAsFixed(2)}s',
                );
                break;
              case 5:
                child = Text(
                  statusCode != 200 ? '-' : tokenText,
                );
                break;
              default:
                child = const SizedBox.shrink();
            }
            return ShadTableCell(alignment: Alignment.centerLeft, child: child);
          },
          columnCount: 6,
          columnSpanExtent: (column) {
            final totalFixedWidth = 180 + 160 + 100 + 120 + 120;
            final availableWidth = constraints.maxWidth;
            final remainingWidth = (availableWidth - totalFixedWidth).clamp(
              120.0,
              double.infinity,
            );

            return switch (column) {
              0 => FixedSpanExtent(180),
              1 => FixedSpanExtent(160),
              2 => FixedSpanExtent(remainingWidth),
              3 => FixedSpanExtent(100),
              4 => FixedSpanExtent(120),
              5 => FixedSpanExtent(120),
              _ => null,
            };
          },
          header: (context, column) {
            if (column == 3) {
              return ShadTableCell.header(child: _buildStatusCodeHeader());
            }
            var text = switch (column) {
              0 => '请求时间',
              1 => '端点',
              2 => '模型',
              4 => '响应时间',
              5 => 'Token',
              _ => '',
            };
            var textStyle = const TextStyle(fontWeight: FontWeight.w500);
            return ShadTableCell.header(child: Text(text, style: textStyle));
          },
          onRowTap: (row) {
            if (row == 0) return;
            final log = logs[row - 1];
            showShadDialog(
              context: context,
              builder: (context) => RequestLogDetailDialog(
                log: log,
                onAudit: () {
                  context.router.push(
                    AuditDetailRoute(log: log),
                  );
                },
              ),
            );
          },
          pinnedRowCount: 1,
          rowCount: logs.length,
        );
      },
    );
    var padding = Padding(
      padding: const EdgeInsets.symmetric(horizontal: ShadcnSpacing.spacing24),
      child: layoutBuilder,
    );
    var children = [Expanded(child: padding), _buildPagination()];
    return Column(children: children);
  }
}