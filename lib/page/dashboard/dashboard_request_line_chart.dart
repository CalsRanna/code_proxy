import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

/// 最近7天每日请求量趋势图
class DashboardRequestsChart extends StatelessWidget {
  final Map<String, int> dailyStats;

  const DashboardRequestsChart({super.key, required this.dailyStats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final data = <MapEntry<String, double>>[];

        // 生成最近7天的日期列表
        final now = DateTime.now();
        for (int i = 6; i >= 0; i--) {
          final date = now.subtract(Duration(days: i));
          final dateKey =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          final formattedDate =
              '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
          final value = dailyStats[dateKey] ?? 0;
          data.add(MapEntry(formattedDate, value.toDouble()));
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
            series: <CartesianSeries<MapEntry<String, double>, String>>[
              SplineSeries<MapEntry<String, double>, String>(
                dataSource: data,
                xValueMapper: (MapEntry<String, double> data, _) => data.key,
                yValueMapper: (MapEntry<String, double> data, _) => data.value,
                color: lineColor,
                width: 2,
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
