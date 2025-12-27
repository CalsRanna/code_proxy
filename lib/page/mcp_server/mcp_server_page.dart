import 'package:code_proxy/model/mcp_server_entity.dart';
import 'package:code_proxy/page/mcp_server/mcp_server_card.dart';
import 'package:code_proxy/page/mcp_server/mcp_server_form_dialog.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/mcp_server_view_model.dart';
import 'package:code_proxy/widget/page_header.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

class McpServerPage extends StatefulWidget {
  const McpServerPage({super.key});

  @override
  State<McpServerPage> createState() => _McpServerPageState();
}

class _McpServerPageState extends State<McpServerPage> {
  final viewModel = GetIt.instance.get<McpServerViewModel>();

  @override
  Widget build(BuildContext context) {
    final addButton = ShadButton(
      onPressed: () => _showAddServerDialog(context),
      leading: const Icon(LucideIcons.plus),
      child: const Text('添加服务器'),
    );

    final pageHeader = Watch((context) {
      return PageHeader(
        title: 'MCP 服务器',
        subtitle: '${viewModel.mcpServers.value.length} 个服务器',
        actions: [addButton],
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeader,
        Expanded(
          child: Watch((context) {
            if (viewModel.isLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }

            final servers = viewModel.mcpServers.value;
            if (servers.isEmpty) {
              return _buildEmptyState();
            }

            return _buildServersList(servers.values.toList());
          }),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.server,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无 MCP 服务器',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角按钮添加 MCP 服务器',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServersList(List<McpServerEntity> servers) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing24,
        vertical: ShadcnSpacing.spacing8,
      ),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        return McpServerCard(
          key: ValueKey(server.id),
          server: server,
          onEdit: () => _showEditServerDialog(context, server),
          onDelete: () => _showDeleteDialog(context, server),
          onToggleEnabled: (value) => viewModel.toggleEnabled(server.id, value),
        );
      },
    );
  }

  void _showAddServerDialog(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (context) => McpServerFormDialog(viewModel: viewModel),
    );
  }

  void _showDeleteDialog(BuildContext context, McpServerEntity server) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('确认删除'),
        description: Padding(
          padding: const EdgeInsets.only(bottom: ShadcnSpacing.spacing8),
          child: Text('确定要删除 MCP 服务器 "${server.name}" 吗？此操作无法撤销。'),
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ShadButton(
            onPressed: () async {
              await viewModel.removeServer(server.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showEditServerDialog(BuildContext context, McpServerEntity server) {
    showShadDialog(
      context: context,
      builder: (context) =>
          McpServerFormDialog(server: server, viewModel: viewModel),
    );
  }
}
