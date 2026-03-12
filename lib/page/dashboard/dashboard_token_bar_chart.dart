import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

/// 模型Token使用趋势堆叠柱状图（hover 展示缓存详情）
class DashboardTokenBarChart extends StatelessWidget {
  /// { date: { model: { total, cache_read, cache_creation } } }
  final Map<String, Map<String, Map<String, int>>> modelDateTokenStats;

  const DashboardTokenBarChart({super.key, required this.modelDateTokenStats});

  static String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = <_BarChartEntry>[];
        final models = <String>{};

        // 收集所有模型
        for (final dateData in modelDateTokenStats.values) {
          models.addAll(dateData.keys);
        }
        final modelList = models.toList()..sort();

        // 生成最近15天的日期列表
        final now = DateTime.now();
        for (int i = 14; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final dateKey =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          final formattedDate =
              '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
          final dateStats = modelDateTokenStats[dateKey] ?? {};
          final Map<String, double> totals = {};
          final Map<String, int> cacheReads = {};
          final Map<String, int> cacheCreations = {};
          for (final model in modelList) {
            final stats = dateStats[model];
            totals[model] = (stats?['total'] ?? 0).toDouble();
            cacheReads[model] = stats?['cache_read'] ?? 0;
            cacheCreations[model] = stats?['cache_creation'] ?? 0;
          }
          data.add(_BarChartEntry(
            date: formattedDate,
            totals: totals,
            cacheReads: cacheReads,
            cacheCreations: cacheCreations,
          ));
        }

        // ShadcnUI 风格配色
        final colors = [
          ShadcnColors.blue500,
          ShadcnColors.emerald500,
          ShadcnColors.amber500,
          ShadcnColors.violet500,
          ShadcnColors.rose500,
          ShadcnColors.cyan500,
          ShadcnColors.pink500,
          ShadcnColors.teal500,
          ShadcnColors.orange500,
          ShadcnColors.indigo500,
        ];

        return SfCartesianChart(
          primaryXAxis:
              const CategoryAxis(labelStyle: TextStyle(fontSize: 10)),
          primaryYAxis:
              const NumericAxis(labelStyle: TextStyle(fontSize: 10)),
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
              final model = modelList[seriesIndex];
              final color = colors[seriesIndex % colors.length];
              final total = (entry.totals[model] ?? 0).toInt();
              final cacheRead = entry.cacheReads[model] ?? 0;
              final cacheCreation = entry.cacheCreations[model] ?? 0;
              final cached = cacheRead + cacheCreation;
              final nonCache = (total - cached).clamp(0, total);

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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          model,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '未缓存: ${_formatNumber(nonCache)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
                    if (cacheRead > 0)
                      Text(
                        '缓存读取: ${_formatNumber(cacheRead)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: ShadcnColors.emerald400,
                        ),
                      ),
                    if (cacheCreation > 0)
                      Text(
                        '缓存创建: ${_formatNumber(cacheCreation)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: ShadcnColors.amber400,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          series: modelList.map((model) {
            final color = colors[modelList.indexOf(model) % colors.length];

            return StackedColumnSeries<_BarChartEntry, String>(
              dataSource: data,
              xValueMapper: (_BarChartEntry d, _) => d.date,
              yValueMapper: (_BarChartEntry d, _) => d.totals[model] ?? 0,
              name: model,
              color: color,
              dataLabelSettings: const DataLabelSettings(isVisible: false),
            );
          }).toList(),
        );
      },
    );
  }
}

class _BarChartEntry {
  final String date;
  final Map<String, double> totals;
  final Map<String, int> cacheReads;
  final Map<String, int> cacheCreations;

  _BarChartEntry({
    required this.date,
    required this.totals,
    required this.cacheReads,
    required this.cacheCreations,
  });
}
