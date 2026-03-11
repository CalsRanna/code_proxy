import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

/// 费用趋势面积图
class DashboardCostChart extends StatelessWidget {
  final Map<String, double> dailyCost;
  final double totalCost;
  final double cacheSavings;

  const DashboardCostChart({
    super.key,
    required this.dailyCost,
    required this.totalCost,
    required this.cacheSavings,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = <MapEntry<String, double>>[];

        // 生成最近15天的日期列表
        final now = DateTime.now();
        int days = 0;
        for (int i = 14; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final dateKey =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          final formattedDate =
              '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
          final cost = dailyCost[dateKey] ?? 0;
          data.add(MapEntry(formattedDate, cost));
          if (cost > 0) days++;
        }

        final avgCost = days > 0 ? totalCost / days : 0.0;

        final lineColor = ShadcnColors.violet500;
        final gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.3),
            lineColor.withValues(alpha: 0.05),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: ShadcnSpacing.spacing16,
              children: [
                _buildMetric('\$${totalCost.toStringAsFixed(4)}', '总费用'),
                _buildMetric('\$${avgCost.toStringAsFixed(4)}', '日均'),
                _buildMetric('\$${cacheSavings.toStringAsFixed(4)}', '缓存节省'),
              ],
            ),
            Expanded(
              child: SfCartesianChart(
                primaryXAxis: const CategoryAxis(
                  labelStyle: TextStyle(fontSize: 10),
                ),
                primaryYAxis: const NumericAxis(
                  labelStyle: TextStyle(fontSize: 10),
                  numberFormat: null,
                ),
                plotAreaBorderWidth: 0,
                legend: const Legend(isVisible: false),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  header: '',
                  canShowMarker: false,
                  format: '\$point.y',
                ),
                series: <CartesianSeries<MapEntry<String, double>, String>>[
                  SplineAreaSeries<MapEntry<String, double>, String>(
                    dataSource: data,
                    splineType: SplineType.monotonic,
                    xValueMapper: (MapEntry<String, double> data, _) =>
                        data.key,
                    yValueMapper: (MapEntry<String, double> data, _) =>
                        data.value,
                    gradient: gradient,
                    borderColor: lineColor,
                    borderWidth: 2,
                    markerSettings: MarkerSettings(
                      isVisible: true,
                      color: ShadcnColors.background(Brightness.light),
                      borderColor: lineColor,
                      borderWidth: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetric(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: ShadcnColors.zinc400),
        ),
      ],
    );
  }
}
