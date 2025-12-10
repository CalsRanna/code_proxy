import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:flutter/material.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';

/// 最近7天每日请求量趋势图
class DailyRequestsChart extends StatelessWidget {
  final Map<String, int> dailyStats;

  const DailyRequestsChart({super.key, required this.dailyStats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = <ChartData>[];

        // 生成最近7天的日期列表
        final now = DateTime.now();
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final dateKey =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          final formattedDate =
              '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
          final value = dailyStats[dateKey] ?? 0;
          data.add(ChartData(x: formattedDate, y: value.toDouble()));
        }

        // ShadcnUI风格的配色
        final lineColor = ShadcnColors.primary;
        final markerColor = ShadcnColors.background(Brightness.light);

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: SfCartesianChart(
            primaryXAxis: const CategoryAxis(
              labelStyle: TextStyle(fontSize: 10),
            ),
            primaryYAxis: const NumericAxis(
              labelStyle: TextStyle(fontSize: 10),
            ),
            plotAreaBorderWidth: 0,
            legend: const Legend(isVisible: false),
            tooltipBehavior: TooltipBehavior(
              enable: true,
              header: '',
              canShowMarker: false,
            ),
            series: <CartesianSeries<ChartData, String>>[
              SplineSeries<ChartData, String>(
                dataSource: data,
                xValueMapper: (ChartData data, _) => data.x,
                yValueMapper: (ChartData data, _) => data.y,
                color: lineColor,
                width: 3,
                markerSettings: MarkerSettings(
                  isVisible: true,
                  color: markerColor,
                  borderColor: lineColor,
                  borderWidth: 2,
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

/// 端点Token使用分布饼图
class EndpointTokenPieChart extends StatelessWidget {
  final Map<String, int> endpointTokenStats;

  const EndpointTokenPieChart({super.key, required this.endpointTokenStats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = <PieData>[];

        final entries = endpointTokenStats.entries.toList();
        final total = endpointTokenStats.values.fold<int>(0, (a, b) => a + b);

        entries.asMap().forEach((index, entry) {
          final percentage = total > 0 ? (entry.value / total * 100) : 0.0;
          data.add(
            PieData(
              x: entry.key,
              y: entry.value.toDouble(),
              text: '${percentage.toStringAsFixed(1)}%',
            ),
          );
        });

        // ShadcnUI风格的配色方案
        final colors = [
          ShadcnColors.primary, // 蓝色
          ShadcnColors.success, // 绿色
          ShadcnColors.warning, // 橙色
          ShadcnColors.secondary, // 紫色
          ShadcnColors.error, // 红色
          const Color(0xFF06B6D4), // 青色
          const Color(0xFFEC4899), // 粉色
          const Color(0xFF8B5CF6), // 紫罗兰色
          const Color(0xFF14B8A6), // 青绿色
          const Color(0xFFF97316), // 橙红色
        ];

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: SfCircularChart(
            legend: const Legend(
              isVisible: true,
              position: LegendPosition.bottom,
              overflowMode: LegendItemOverflowMode.scroll,
              textStyle: TextStyle(fontSize: 10),
            ),
            tooltipBehavior: TooltipBehavior(
              enable: true,
              header: '',
              canShowMarker: false,
            ),
            series: <CircularSeries<PieData, String>>[
              PieSeries<PieData, String>(
                dataSource: data,
                xValueMapper: (PieData data, _) => data.x,
                yValueMapper: (PieData data, _) => data.y,
                pointColorMapper: (PieData data, int index) =>
                    colors[index % colors.length],
                dataLabelSettings: const DataLabelSettings(
                  isVisible: true,
                  textStyle: TextStyle(fontSize: 10),
                ),
                radius: '70%',
                explode: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 模型Token使用趋势堆叠柱状图
class ModelDateTokenBarChart extends StatelessWidget {
  final Map<String, Map<String, int>> modelDateTokenStats;

  const ModelDateTokenBarChart({super.key, required this.modelDateTokenStats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = <StackedColumnData>[];
        final models = <String>{};

        // 获取所有模型
        for (final dateData in modelDateTokenStats.values) {
          models.addAll(dateData.keys);
        }
        final modelList = models.toList()..sort();

        // 生成最近7天的日期列表
        final now = DateTime.now();
        for (int i = 6; i >= 0; i--) {
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
          data.add(StackedColumnData(x: formattedDate, yValues: yValues));
        }

        // ShadcnUI风格的配色方案
        final colors = [
          ShadcnColors.primary, // 蓝色
          ShadcnColors.success, // 绿色
          ShadcnColors.warning, // 橙色
          ShadcnColors.secondary, // 紫色
          ShadcnColors.error, // 红色
          const Color(0xFF06B6D4), // 青色
          const Color(0xFFEC4899), // 粉色
          const Color(0xFF8B5CF6), // 紫罗兰色
          const Color(0xFF14B8A6), // 青绿色
          const Color(0xFFF97316), // 橙红色
        ];

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: SfCartesianChart(
            primaryXAxis: const CategoryAxis(
              labelStyle: TextStyle(fontSize: 10),
            ),
            primaryYAxis: const NumericAxis(
              labelStyle: TextStyle(fontSize: 10),
            ),
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

              return StackedColumnSeries<StackedColumnData, String>(
                dataSource: data,
                xValueMapper: (StackedColumnData data, _) => data.x,
                yValueMapper: (StackedColumnData data, _) =>
                    data.yValues[model] ?? 0,
                name: model,
                color: color,
                dataLabelSettings: const DataLabelSettings(isVisible: false),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

/// LineChart 数据模型
class ChartData {
  final String x;
  final double y;

  ChartData({required this.x, required this.y});
}

/// PieChart 数据模型
class PieData {
  final String x;
  final double y;
  final String? text;

  PieData({required this.x, required this.y, this.text});
}

/// StackedColumnChart 数据模型
class StackedColumnData {
  final String x;
  final Map<String, double> yValues;

  StackedColumnData({required this.x, required this.yValues});
}
