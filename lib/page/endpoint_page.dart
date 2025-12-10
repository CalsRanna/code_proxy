import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_color_helpers.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/widgets/endpoint_form/endpoint_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

class EndpointPage extends StatelessWidget {
  final EndpointsViewModel viewModel;

  const EndpointPage({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final filteredEndpoints = viewModel.filteredEndpoints.value;
      final isLoading = viewModel.isLoading.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '端点管理',
            subtitle: '${filteredEndpoints.length} 个端点',
            icon: LucideIcons.server,
            actions: [
              ShadButton(
                onPressed: () => _showAddEndpointDialog(context),
                leading: const Icon(LucideIcons.plus),
                child: const Text('添加端点'),
              ),
            ],
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredEndpoints.isEmpty
                ? _buildEmptyState(context)
                : _buildEndpointsList(context, filteredEndpoints),
          ),
        ],
      );
    });
  }

  Widget _buildEmptyState(BuildContext context) {
    final hasSearch = viewModel.searchQuery.value.isNotEmpty;
    return EmptyState(
      icon: hasSearch ? LucideIcons.searchX : LucideIcons.server,
      message: hasSearch ? '未找到匹配的端点' : '暂无端点配置',
      actionLabel: hasSearch ? null : '添加端点',
      onAction: hasSearch ? null : () => _showAddEndpointDialog(context),
    );
  }

  Widget _buildEndpointsList(
    BuildContext context,
    List<EndpointEntity> endpoints,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
      itemCount: endpoints.length,
      itemBuilder: (context, index) {
        final endpoint = endpoints[index];
        return ShadCard(
          child: Row(
            children: [
              // 左侧：图标徽章
              IconBadge(
                icon: LucideIcons.server,
                color: endpoint.enabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
                size: IconBadgeSize.large,
              ),
              const SizedBox(width: ShadcnSpacing.spacing16),

              // 中间：信息列
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          endpoint.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: ShadcnSpacing.spacing8),
                        if (endpoint.weight > 1)
                          StatusBadge(
                            label: '权重: ${endpoint.weight}',
                            type: StatusType.info,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      endpoint.anthropicBaseUrl ?? '未配置',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ShadcnColors.mutedForeground(
                          Theme.of(context).brightness,
                        ),
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (endpoint.note != null && endpoint.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        endpoint.note!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // 右侧：开关和菜单
              const SizedBox(width: ShadcnSpacing.spacing16),
              ShadSwitch(
                value: endpoint.enabled,
                onChanged: (_) => viewModel.toggleEnabled(endpoint.id),
              ),
              PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(LucideIcons.pencil, size: 20),
                        SizedBox(width: 8),
                        Text('编辑'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(LucideIcons.trash2, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('删除', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditEndpointDialog(context, endpoint);
                  } else if (value == 'delete') {
                    _showDeleteDialog(context, endpoint);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddEndpointDialog(BuildContext context) {
    _showEndpointDialog(context, null);
  }

  void _showEditEndpointDialog(BuildContext context, EndpointEntity endpoint) {
    _showEndpointDialog(context, endpoint);
  }

  void _showEndpointDialog(BuildContext context, EndpointEntity? endpoint) {
    showShadDialog(
      context: context,
      builder: (context) =>
          EndpointFormDialog(endpoint: endpoint, viewModel: viewModel),
    );
  }

  void _showDeleteDialog(BuildContext context, EndpointEntity endpoint) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除端点"${endpoint.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await viewModel.deleteEndpoint(endpoint.id);
              if (context.mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
