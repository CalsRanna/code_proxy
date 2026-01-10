import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

/// 模型Token使用趋势堆叠柱状图
class DashboardTokenBarChart extends StatelessWidget {
  final Map<String, Map<String, int>> modelDateTokenStats;

  const DashboardTokenBarChart({super.key, required this.modelDateTokenStats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = <MapEntry<String, Map<String, double>>>[];
        final models = <String>{};

        // 获取所有模型
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
          final Map<String, double> yValues = {};
          final dateStats = modelDateTokenStats[dateKey] ?? {};
          for (final model in modelList) {
            yValues[model] = (dateStats[model] ?? 0).toDouble();
          }
          data.add(MapEntry(formattedDate, yValues));
        }

        // ShadcnUI风格的配色方案
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
          primaryXAxis: const CategoryAxis(labelStyle: TextStyle(fontSize: 10)),
          primaryYAxis: const NumericAxis(labelStyle: TextStyle(fontSize: 10)),
          plotAreaBorderWidth: 0,
          legend: const Legend(isVisible: false),
          tooltipBehavior: TooltipBehavior(
            enable: true,
            header: '',
            canShowMarker: false,
            format: 'series.name: point.y',
          ),
          series: modelList.map((model) {
            final color = colors[modelList.indexOf(model) % colors.length];

            return StackedColumnSeries<
              MapEntry<String, Map<String, double>>,
              String
            >(
              dataSource: data,
              xValueMapper: (MapEntry<String, Map<String, double>> data, _) =>
                  data.key,
              yValueMapper: (MapEntry<String, Map<String, double>> data, _) =>
                  data.value[model] ?? 0,
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
