import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/page/endpoint/endpoint_card.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/endpoint_view_model.dart';
import 'package:code_proxy/widget/empty_state.dart';
import 'package:code_proxy/widget/page_header.dart';
import 'package:code_proxy/page/endpoint/endpoint_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
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

  /// 排序包需要通过 GridView 的 GlobalKey 做拖拽到边缘时的自动滚动。
  final _gridKey = GlobalKey();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final endpoints = viewModel.endpoints.value;
      // 读取 forbiddenEndpointIds 以订阅断路器状态变化
      viewModel.forbiddenEndpointIds.value;
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
                : _buildEndpointsGrid(endpoints),
          ),
        ],
      );
    });
  }

  Widget _buildEmptyState() {
    return const EmptyState();
  }

  /// 端点网格：列数随窗口宽度自适应，卡片顺序即故障转移优先级。
  ///
  /// Flutter SDK 没有内置可排序网格，这里用 flutter_reorderable_grid_view
  /// 在 GridView 上补拖拽排序。onReorder 回调给出的是一整个重排函数，
  /// 而不是 onReorderItem(oldIndex, newIndex) 那样的两个下标。
  Widget _buildEndpointsGrid(List<EndpointEntity> endpoints) {
    return ReorderableBuilder<EndpointEntity>.builder(
      scrollController: _scrollController,
      itemCount: endpoints.length,
      // 桌面端按住即可拖动；默认值需要长按 500ms，不符合鼠标操作习惯。
      longPressDelay: Duration.zero,
      onReorder: (reorderedListFunction) {
        viewModel.reorderEndpointsByOrder(reorderedListFunction(endpoints));
      },
      childBuilder: (itemBuilder) {
        return GridView.builder(
          key: _gridKey,
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(
            horizontal: ShadcnSpacing.spacing24,
            vertical: ShadcnSpacing.spacing16,
          ),
          itemCount: endpoints.length,
          // 固定行高，卡片不会被列宽比例拉变形；420 宽在最小窗口
          //（1080 宽，内容区约 960）下正好三列。
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 420,
            mainAxisExtent: 160,
            crossAxisSpacing: ShadcnSpacing.spacing16,
            mainAxisSpacing: ShadcnSpacing.spacing16,
          ),
          itemBuilder: (context, index) {
            final endpoint = endpoints[index];
            return itemBuilder(_buildCard(endpoint, index), index);
          },
        );
      },
    );
  }

  Widget _buildCard(EndpointEntity endpoint, int index) {
    return EndpointCard(
      key: ValueKey(endpoint.id),
      index: index,
      endpoint: endpoint,
      isForbidden: viewModel.forbiddenEndpointIds.contains(endpoint.id),
      onEdit: () => _showEditEndpointDialog(context, endpoint),
      onClone: () => _showCloneEndpointDialog(context, endpoint),
      onDelete: () => _showDeleteDialog(context, endpoint),
      onResetCircuitBreaker: () => viewModel.resetCircuitBreaker(endpoint.id),
      onToggleEnabled: (value) => viewModel.toggleEnabled(endpoint.id),
    );
  }

  void _showAddEndpointDialog(BuildContext context) {
    _showEndpointDialog(context, null);
  }

  void _showEditEndpointDialog(BuildContext context, EndpointEntity endpoint) {
    _showEndpointDialog(context, endpoint);
  }

  void _showCloneEndpointDialog(BuildContext context, EndpointEntity endpoint) {
    // 创建一个克隆的端点实体，id为空字符串表示新建，名称添加"副本"后缀
    final clonedEndpoint = endpoint.clone(name: '${endpoint.name} (副本)');
    _showEndpointDialog(context, clonedEndpoint);
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
