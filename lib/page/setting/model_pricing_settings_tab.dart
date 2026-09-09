import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/setting_view_model.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

import 'model_pricing_detail_dialog.dart';

class ModelPricingSettingsTab extends StatelessWidget {
  final SettingViewModel viewModel;

  const ModelPricingSettingsTab({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final models = viewModel.pricingModels;
      final refreshing = viewModel.pricingRefreshing.value;
      final groupedModels = _groupPricingModels(models);
      return ListView(
        padding: const EdgeInsets.only(top: ShadcnSpacing.spacing8),
        children: [
          ListTile(
            title: const Text('刷新模型定价'),
            subtitle: Text(
              '${viewModel.pricingModelCount.value} 个模型 | 更新于 ${viewModel.pricingLastUpdated.value}',
            ),
            trailing: refreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.refreshCw),
            onTap: refreshing ? null : () => _refreshPricing(context),
          ),
          if (models.isEmpty)
            _buildPricingEmptyState(context)
          else
            ...groupedModels.entries.expand((entry) {
              return [
                _buildPricingGroupHeader(
                  context,
                  entry.key,
                  entry.value.length,
                ),
                ...entry.value.map(
                  (model) => ListTile(
                    title: Text(model.modelId),
                    subtitle: Text(
                      '输入 ${formatModelPrice(model.inputPrice)} | 输出 ${formatModelPrice(model.outputPrice)}',
                    ),
                    trailing: const Icon(LucideIcons.chevronRight),
                    onTap: () => showShadDialog<void>(
                      context: context,
                      builder: (_) => ModelPricingDetailDialog(model: model),
                    ),
                  ),
                ),
              ];
            }),
        ],
      );
    });
  }

  Widget _buildPricingGroupHeader(
    BuildContext context,
    String label,
    int count,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing16,
        vertical: ShadcnSpacing.spacing12,
      ),
      child: Row(
        spacing: ShadcnSpacing.spacing8,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: ShadcnColors.mutedForeground(Theme.of(context).brightness),
            ),
          ),
          ShadBadge.secondary(
            child: Text('$count', style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Map<String, List<ModelPricingEntity>> _groupPricingModels(
    List<ModelPricingEntity> models,
  ) {
    final grouped = <String, List<ModelPricingEntity>>{
      'Claude': [],
      'DeepSeek': [],
      'GLM': [],
      'Kimi': [],
      'MiniMax': [],
      '其他': [],
    };

    for (final model in models) {
      grouped[_pricingGroupForModel(model)]!.add(model);
    }

    grouped.removeWhere((_, value) => value.isEmpty);
    return grouped;
  }

  String _pricingGroupForModel(ModelPricingEntity model) {
    final normalized = model.modelId.toLowerCase();
    if (normalized.contains('claude')) return 'Claude';
    if (normalized.contains('deepseek')) return 'DeepSeek';
    if (normalized.contains('glm')) return 'GLM';
    if (normalized.contains('kimi')) return 'Kimi';
    if (normalized.contains('minimax')) return 'MiniMax';
    return '其他';
  }

  Widget _buildPricingEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing24),
      child: Center(
        child: Column(
          children: [
            Icon(
              LucideIcons.badgeDollarSign,
              size: 48,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: ShadcnSpacing.spacing16),
            Text('暂无模型定价数据', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: ShadcnSpacing.spacing8),
            Text(
              '点击上方刷新即可从 models.dev 拉取最新定价。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshPricing(BuildContext context) async {
    final message = await viewModel.refreshPricing();
    if (!context.mounted) return;
    if (message == null) {
      ShadSonner.of(
        context,
      ).show(const ShadToast(description: Text('模型定价已刷新')));
      return;
    }
    ShadSonner.of(context).show(ShadToast(description: Text(message)));
  }
}
