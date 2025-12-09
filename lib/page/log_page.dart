import 'dart:convert';

import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/view_model/logs_view_model.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class LogPage extends StatelessWidget {
  final LogsViewModel viewModel;

  const LogPage({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final filteredLogs = viewModel.filteredLogs.value;
      final currentPage = viewModel.currentPage.value;
      final totalPages = viewModel.totalPages.value;
      final totalRecords = viewModel.totalRecords.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Text(
                  '请求日志',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  tooltip: '清空日志',
                  onPressed: () => _showClearDialog(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filteredLogs.isEmpty
                ? _buildEmptyState()
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(24),
                          itemCount: filteredLogs.length,
                          itemBuilder: (context, index) {
                            final log = filteredLogs[index];
                            return _buildLogItem(context, log);
                          },
                        ),
                      ),
                      _buildPagination(
                        context,
                        currentPage,
                        totalPages,
                        totalRecords,
                      ),
                    ],
                  ),
          ),
        ],
      );
    });
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.article_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂无日志',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(BuildContext context, RequestLog log) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _showLogDetail(context, log),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      _formatTime(log.timestamp),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 160,
                    child: Text(
                      log.endpointName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      log.model ?? 'unknown model',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.purple.shade700,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '${((log.responseTime ?? 0) / 1000).toStringAsFixed(2)}s',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: _getResponseTimeColor(log.responseTime!),
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '${log.inputTokens ?? 0} / ${log.outputTokens ?? 0}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getResponseTimeColor(int responseTime) {
    if (responseTime < 500) return Colors.green;
    if (responseTime < 2000) return Colors.orange;
    return Colors.red;
  }

  void _showLogDetail(BuildContext context, RequestLog log) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: log.success
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: log.success ? Colors.green : Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        log.success
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${log.method} ${log.path}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            log.success ? '请求成功' : '请求失败',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // 内容区
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailSection('基本信息', [
                        _buildDetailRow2(
                          '端点',
                          log.endpointName,
                          Icons.dns_outlined,
                        ),
                        _buildDetailRow2(
                          '时间',
                          _formatFullTime(log.timestamp),
                          Icons.access_time,
                        ),
                        if (log.statusCode != null)
                          _buildDetailRow2(
                            '状态码',
                            '${log.statusCode}',
                            Icons.code,
                          ),
                        if (log.responseTime != null)
                          _buildDetailRow2(
                            '响应时间',
                            '${log.responseTime}ms',
                            Icons.speed,
                          ),
                        if (log.model != null)
                          _buildDetailRow2(
                            '模型',
                            log.model!,
                            Icons.smart_toy_outlined,
                          ),
                        if (log.inputTokens != null)
                          _buildDetailRow2(
                            '输入 Tokens',
                            '${log.inputTokens}',
                            Icons.arrow_upward,
                          ),
                        if (log.outputTokens != null)
                          _buildDetailRow2(
                            '输出 Tokens',
                            '${log.outputTokens}',
                            Icons.arrow_downward,
                          ),
                      ]),
                      if (log.rawHeader != null &&
                          log.rawHeader!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildDetailSection('原始请求头', [
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 200),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                JsonEncoder.withIndent('  ').convert(
                                  JsonDecoder().convert(log.rawHeader!),
                                ),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade900,
                                  height: 1.6,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ],
                      if (log.rawRequest != null &&
                          log.rawRequest!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildDetailSection('原始请求', [
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 300),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                log.rawRequest!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade900,
                                  height: 1.6,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ],
                      if (log.rawResponse != null &&
                          log.rawResponse!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildDetailSection('原始响应', [
                          Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 300),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                log.rawResponse!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade900,
                                  height: 1.6,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow2(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return dt.toString().substring(0, 19);
  }

  String _formatFullTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  Widget _buildPagination(
    BuildContext context,
    int currentPage,
    int totalPages,
    int totalRecords,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧：显示记录数信息
          Text(
            '共 $totalRecords 条记录',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),

          // 中间：分页按钮
          Row(
            children: [
              // 首页按钮
              IconButton(
                icon: const Icon(Icons.first_page),
                iconSize: 20,
                onPressed: currentPage > 1 ? viewModel.firstPage : null,
                tooltip: '首页',
              ),
              const SizedBox(width: 8),

              // 上一页按钮
              IconButton(
                icon: const Icon(Icons.chevron_left),
                iconSize: 20,
                onPressed: currentPage > 1 ? viewModel.previousPage : null,
                tooltip: '上一页',
              ),
              const SizedBox(width: 16),

              // 页码信息
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  '$currentPage / $totalPages',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // 下一页按钮
              IconButton(
                icon: const Icon(Icons.chevron_right),
                iconSize: 20,
                onPressed:
                    currentPage < totalPages ? viewModel.nextPage : null,
                tooltip: '下一页',
              ),
              const SizedBox(width: 8),

              // 尾页按钮
              IconButton(
                icon: const Icon(Icons.last_page),
                iconSize: 20,
                onPressed: currentPage < totalPages ? viewModel.lastPage : null,
                tooltip: '尾页',
              ),
            ],
          ),

          // 右侧：每页数量选择
          Row(
            children: [
              Text(
                '每页',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: viewModel.pageSize.value,
                underline: Container(),
                items: const [
                  DropdownMenuItem(value: 20, child: Text('20')),
                  DropdownMenuItem(value: 50, child: Text('50')),
                  DropdownMenuItem(value: 100, child: Text('100')),
                  DropdownMenuItem(value: 200, child: Text('200')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    viewModel.setPageSize(value);
                  }
                },
              ),
              const SizedBox(width: 8),
              Text(
                '条',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await viewModel.clearLogs();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}
