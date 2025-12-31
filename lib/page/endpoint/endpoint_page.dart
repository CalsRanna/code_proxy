import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/page/endpoint/endpoint_card.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:code_proxy/widget/page_header.dart';
import 'package:code_proxy/page/endpoint/endpoint_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

class EndpointPage extends StatefulWidget {
  const EndpointPage({super.key});

  @override
  State<StatefulWidget> createState() => _EndpointPageState();
}

class _EndpointPageState extends State<EndpointPage> {
  final viewModel = GetIt.instance.get<EndpointViewModel>();

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final endpoints = viewModel.endpoints.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: '端点',
            subtitle: '${endpoints.length} 个端点',
            actions: [
              ShadButton(
                onPressed: () => _showAddEndpointDialog(context),
                leading: const Icon(LucideIcons.plus),
                child: const Text('添加端点'),
              ),
            ],
          ),
          Expanded(
            child: endpoints.isEmpty
                ? _buildEmptyState()
                : _buildEndpointsList(endpoints),
          ),
        ],
      );
    });
  }

  Widget _buildEmptyState() {
    return Center(child: Text('暂无数据'));
  }

  Widget _buildEndpointsList(List<EndpointEntity> endpoints) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing24,
        vertical: ShadcnSpacing.spacing16,
      ),
      itemCount: endpoints.length,
      itemBuilder: (context, index) {
        final endpoint = endpoints[index];
        return EndpointCard(
          key: ValueKey(endpoint.id),
          index: index,
          endpoint: endpoint,
          onEdit: () => _showEditEndpointDialog(context, endpoint),
          onDelete: () => _showDeleteDialog(context, endpoint),
          onToggleEnabled: (value) => viewModel.toggleEnabled(endpoint.id),
        );
      },
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) {
        // 返回不带阴影的装饰器
        return child;
      },
      onReorder: (oldIndex, newIndex) {
        viewModel.reorderEndpoints(oldIndex, newIndex);
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
