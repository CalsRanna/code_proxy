import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/view_model/endpoints_view_model.dart';
import 'package:code_proxy/widgets/endpoint_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class EndpointPage extends StatelessWidget {
  final EndpointsViewModel viewModel;

  const EndpointPage({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final endpoints = viewModel.endpoints.value;
      final isLoading = viewModel.isLoading.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Text(
                  '端点管理',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showAddEndpointDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('添加端点'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : endpoints.isEmpty
                ? _buildEmptyState()
                : _buildEndpointsList(context, endpoints),
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
          Icon(Icons.dns_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂无端点',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointsList(BuildContext context, List<Endpoint> endpoints) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: endpoints.length,
      itemBuilder: (context, index) {
        final endpoint = endpoints[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            title: Text(
              endpoint.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(endpoint.url),
                const SizedBox(height: 2),
                Text(
                  '分类: ${_getCategoryLabel(endpoint.category)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: endpoint.enabled,
                  onChanged: (_) => viewModel.toggleEnabled(endpoint.id),
                ),
                const SizedBox(width: 8),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('编辑'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
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
          ),
        );
      },
    );
  }

  void _showAddEndpointDialog(BuildContext context) {
    _showEndpointDialog(context, null);
  }

  void _showEditEndpointDialog(BuildContext context, Endpoint endpoint) {
    _showEndpointDialog(context, endpoint);
  }

  void _showEndpointDialog(BuildContext context, Endpoint? endpoint) {
    showDialog(
      context: context,
      builder: (context) =>
          EndpointFormDialog(endpoint: endpoint, viewModel: viewModel),
    );
  }

  void _showDeleteDialog(BuildContext context, Endpoint endpoint) {
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

  String _getCategoryLabel(String category) {
    switch (category) {
      case 'official':
        return '官方';
      case 'aggregator':
        return '聚合器';
      case 'custom':
        return '自定义';
      default:
        return category;
    }
  }
}
