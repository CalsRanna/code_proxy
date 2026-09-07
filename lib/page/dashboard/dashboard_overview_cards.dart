import 'package:code_proxy/model/dashboard_overview_stats.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';

/// 概览统计卡片行：消息数、Token 总量、活跃天数、缓存命中率、合计花费。
///
/// 样式对齐浅色底圆角卡片：小号灰色标签 + 粗体大数字。
class DashboardOverviewCards extends StatelessWidget {
  final DashboardOverviewStats stats;

  /// 全时间总费用（美元）；与页头副标题同源，0 时显示 $0.00。
  final double totalCost;

  const DashboardOverviewCards({
    super.key,
    required this.stats,
    this.totalCost = 0.0,
  });

  static const double _labelFontSize = 12;
  static const double _valueFontSize = 20;
  static const double _borderRadius = 10;

  /// 数字缩写与千分位：
  /// - ≥10 亿：X.XXB
  /// - ≥100 万：X.XXM
  /// - 其余：千分位逗号（47,202 比 47.2K 可读性更高）
  ///
  /// B/M 最多保留两位小数，尾随零去掉（3.36B / 5.25M / 5M），
  /// 避免 3.4B 这种把 0.04B 丢掉的损失。
  static String _formatNumber(int n) {
    if (n >= 1000000000) return _compact(n / 1000000000, 'B');
    if (n >= 1000000) return _compact(n / 1000000, 'M');
    return _withThousandsSeparator(n);
  }

  /// 数值最多保留两位小数并附加单位，尾随零去掉（3.36B / 5M / 94.6%）。
  static String _compact(double value, String unit) {
    var text = value.toStringAsFixed(2);
    if (text.endsWith('.00')) {
      text = text.substring(0, text.length - 3);
    } else if (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    return '$text$unit';
  }

  static String _withThousandsSeparator(int n) {
    final digits = n.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// 金额格式化：$1,518.46
  static String _formatMoney(double amount) {
    final fixed = amount.toStringAsFixed(2);
    final parts = fixed.split('.');
    return '\$${_withThousandsSeparator(int.parse(parts[0]))}.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final cardColor = brightness == Brightness.light
        ? ShadcnColors.zinc100
        : ShadcnColors.zinc900;
    final labelColor = ShadcnColors.mutedForeground(brightness);
    final valueColor = brightness == Brightness.light
        ? ShadcnColors.zinc950
        : ShadcnColors.lightBackground;

    var children = [
      _buildStatCard(
        label: '活跃天数',
        value: _formatNumber(stats.activeDays),
        cardColor: cardColor,
        labelColor: labelColor,
        valueColor: valueColor,
      ),
      _buildStatCard(
        label: '消息',
        value: _formatNumber(stats.messages),
        cardColor: cardColor,
        labelColor: labelColor,
        valueColor: valueColor,
      ),
      _buildStatCard(
        label: 'Token 总量',
        value: _formatNumber(stats.totalTokens),
        cardColor: cardColor,
        labelColor: labelColor,
        valueColor: valueColor,
      ),
      _buildStatCard(
        label: '缓存命中率',
        value: _compact(stats.cacheHitRate * 100, '%'),
        cardColor: cardColor,
        labelColor: labelColor,
        valueColor: valueColor,
      ),
      _buildStatCard(
        label: '合计花费',
        value: _formatMoney(totalCost),
        cardColor: cardColor,
        labelColor: labelColor,
        valueColor: valueColor,
      ),
    ];
    return Row(
      spacing: ShadcnSpacing.spacing16,
      children: [for (final card in children) Expanded(child: card)],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color cardColor,
    required Color labelColor,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ShadcnSpacing.spacing16,
        vertical: ShadcnSpacing.spacing8,
      ),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(_borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: _labelFontSize, color: labelColor),
          ),
          const SizedBox(height: ShadcnSpacing.spacing4),
          Text(
            value,
            style: TextStyle(
              fontSize: _valueFontSize,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
