import 'package:code_proxy/model/model_pricing_entity.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ModelPricingDetailDialog extends StatelessWidget {
  final ModelPricingEntity model;

  const ModelPricingDetailDialog({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    return ShadDialog(
      title: Text(model.modelId, maxLines: 1, overflow: TextOverflow.ellipsis),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPricingDetailRow(
              icon: LucideIcons.arrowDownToLine,
              label: '输入价格',
              value: formatModelPrice(model.inputPrice),
            ),
            _buildPricingDetailRow(
              icon: LucideIcons.arrowUpFromLine,
              label: '输出价格',
              value: formatModelPrice(model.outputPrice),
            ),
            _buildPricingDetailRow(
              icon: LucideIcons.databaseZap,
              label: '缓存写入价格',
              value: formatModelPrice(model.cacheWritePrice),
            ),
            _buildPricingDetailRow(
              icon: LucideIcons.databaseBackup,
              label: '缓存读取价格',
              value: formatModelPrice(model.cacheReadPrice),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShadcnSpacing.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: ShadcnSpacing.spacing16,
        children: [
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: ShadcnSpacing.spacing4,
              children: [
                Icon(icon, color: ShadcnColors.lightMutedForeground, size: 16),
                Text(label),
              ],
            ),
          ),
          Expanded(
            child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

String formatModelPrice(double price) {
  if (price == 0) return '-';
  var text = price.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return '\$$text / MTok';
}
