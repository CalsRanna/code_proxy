import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

/// 缓存命中率堆叠柱状图
class DashboardCacheChart extends StatelessWidget {
  final Map<String, Map<String, int>> dailyCacheStats;

  const DashboardCacheChart({super.key, required this.dailyCacheStats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = <_CacheChartData>[];
        int totalCacheRead = 0;
        int totalInput = 0;

        // 生成最近15天的日期列表
        final now = DateTime.now();
        for (int i = 14; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final dateKey =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          final formattedDate =
              '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
          final stats = dailyCacheStats[dateKey];
          final cacheRead = stats?['cache_read'] ?? 0;
          final cacheCreation = stats?['cache_creation'] ?? 0;
          final inputTotal = stats?['total_input'] ?? 0;
          final nonCache = (inputTotal - cacheRead - cacheCreation)
              .clamp(0, double.maxFinite)
              .toInt();

          totalCacheRead += cacheRead;
          totalInput += inputTotal;

          data.add(_CacheChartData(
            date: formattedDate,
            cacheRead: cacheRead.toDouble(),
            cacheCreation: cacheCreation.toDouble(),
            nonCache: nonCache.toDouble(),
          ));
        }

        final hitRate = totalInput > 0
            ? (totalCacheRead / totalInput * 100).toStringAsFixed(1)
            : '0.0';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '命中率 $hitRate%',
              style: TextStyle(
                fontSize: 12,
                color: ShadcnColors.emerald500,
                fontWeight: FontWeight.w500,
              ),
            ),
            Expanded(
              child: SfCartesianChart(
                primaryXAxis:
                    const CategoryAxis(labelStyle: TextStyle(fontSize: 10)),
                primaryYAxis:
                    const NumericAxis(labelStyle: TextStyle(fontSize: 10)),
                plotAreaBorderWidth: 0,
                legend: const Legend(isVisible: false),
                tooltipBehavior: TooltipBehavior(
                  enable: true,
                  header: '',
                  canShowMarker: false,
                  format: 'series.name: point.y',
                ),
                series: <CartesianSeries<_CacheChartData, String>>[
                  StackedColumnSeries<_CacheChartData, String>(
                    dataSource: data,
                    xValueMapper: (_CacheChartData d, _) => d.date,
                    yValueMapper: (_CacheChartData d, _) => d.cacheRead,
                    name: 'Cache Read',
                    color: ShadcnColors.emerald500,
                  ),
                  StackedColumnSeries<_CacheChartData, String>(
                    dataSource: data,
                    xValueMapper: (_CacheChartData d, _) => d.date,
                    yValueMapper: (_CacheChartData d, _) => d.cacheCreation,
                    name: 'Cache Creation',
                    color: ShadcnColors.amber500,
                  ),
                  StackedColumnSeries<_CacheChartData, String>(
                    dataSource: data,
                    xValueMapper: (_CacheChartData d, _) => d.date,
                    yValueMapper: (_CacheChartData d, _) => d.nonCache,
                    name: 'Non-Cache',
                    color: ShadcnColors.zinc300,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CacheChartData {
  final String date;
  final double cacheRead;
  final double cacheCreation;
  final double nonCache;

  _CacheChartData({
    required this.date,
    required this.cacheRead,
    required this.cacheCreation,
    required this.nonCache,
  });
}
