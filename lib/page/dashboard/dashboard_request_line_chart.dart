import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

/// 最近15天每日请求量趋势图（hover 展示费用详情）
class DashboardRequestsChart extends StatelessWidget {
  final Map<String, int> dailyStats;
  final Map<String, double> dailyCost;

  const DashboardRequestsChart({
    super.key,
    required this.dailyStats,
    this.dailyCost = const {},
  });

  static String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = <_RequestChartEntry>[];

        // 生成最近15天的日期列表
        final now = DateTime.now();
        for (int i = 14; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final dateKey =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          final formattedDate =
              '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
          final requests = dailyStats[dateKey] ?? 0;
          final cost = dailyCost[dateKey] ?? 0;
          data.add(_RequestChartEntry(
            date: formattedDate,
            requests: requests.toDouble(),
            cost: cost,
          ));
        }

        // ShadcnUI风格的配色
        final lineColor = ShadcnColors.primary;
        final markerColor = ShadcnColors.background(Brightness.light);

        // 渐变填充
        final gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.3),
            lineColor.withValues(alpha: 0.05),
          ],
        );

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: SfCartesianChart(
            primaryXAxis: const CategoryAxis(
              labelStyle: TextStyle(fontSize: 10),
            ),
            primaryYAxis: NumericAxis(
              labelStyle: const TextStyle(fontSize: 10),
              axisLabelFormatter: (AxisLabelRenderDetails details) {
                return ChartAxisLabel(
                  _formatNumber(details.value.toInt()),
                  const TextStyle(fontSize: 10),
                );
              },
            ),
            plotAreaBorderWidth: 0,
            legend: const Legend(isVisible: false),
            tooltipBehavior: TooltipBehavior(
              enable: true,
              builder: (dynamic rawData, dynamic point, dynamic series,
                  int pointIndex, int seriesIndex) {
                if (pointIndex < 0 || pointIndex >= data.length) {
                  return const SizedBox.shrink();
                }
                final entry = data[pointIndex];
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '请求: ${entry.requests.toInt()}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (entry.cost > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          '费用: \$${entry.cost.toStringAsFixed(4)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: ShadcnColors.violet300,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            series: <CartesianSeries<_RequestChartEntry, String>>[
              SplineAreaSeries<_RequestChartEntry, String>(
                dataSource: data,
                splineType: SplineType.monotonic,
                xValueMapper: (_RequestChartEntry d, _) => d.date,
                yValueMapper: (_RequestChartEntry d, _) => d.requests,
                gradient: gradient,
                borderColor: lineColor,
                borderWidth: 2,
                markerSettings: MarkerSettings(
                  isVisible: true,
                  color: markerColor,
                  borderColor: lineColor,
                  borderWidth: 1,
                ),
                dataLabelSettings: const DataLabelSettings(isVisible: false),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RequestChartEntry {
  final String date;
  final double requests;
  final double cost;

  _RequestChartEntry({
    required this.date,
    required this.requests,
    required this.cost,
  });
}
