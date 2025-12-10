import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/page/endpoint/endpoint_card.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/page/endpoint/endpoint_form_dialog.dart';
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
            icon: LucideIcons.shell,
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
      icon: hasSearch ? LucideIcons.searchX : LucideIcons.shell,
      message: hasSearch ? '未找到匹配的端点' : '暂无端点配置',
      actionLabel: hasSearch ? null : '添加端点',
      onAction: hasSearch ? null : () => _showAddEndpointDialog(context),
    );
  }

  Widget _buildEndpointsList(
    BuildContext context,
    List<EndpointEntity> endpoints,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
      itemCount: endpoints.length,
      itemBuilder: (context, index) {
        final endpoint = endpoints[index];
        return EndpointCard(
          endpoint: endpoint,
          onEdit: () => _showEditEndpointDialog(context, endpoint),
          onDelete: () => _showDeleteDialog(context, endpoint),
          onToggleEnabled: (value) => viewModel.toggleEnabled(endpoint.id),
        );
      },
      separatorBuilder: (context, index) => const SizedBox(height: 16),
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
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('确认删除'),
        description: Padding(
          padding: const EdgeInsets.only(bottom: ShadcnSpacing.spacing8),
          child: Text('确定要删除端点${endpoint.name}吗？此操作无法撤销。'),
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ShadButton(
            onPressed: () async {
              await viewModel.deleteEndpoint(endpoint.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
