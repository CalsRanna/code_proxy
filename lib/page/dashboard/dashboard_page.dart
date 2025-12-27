import 'package:code_proxy/page/dashboard/dashboard_request_line_chart.dart';
import 'package:code_proxy/page/dashboard/dashboard_token_bar_chart.dart';
import 'package:code_proxy/page/dashboard/dashboard_token_heatmap.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/widget/page_header.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:signals/signals_flutter.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final viewModel = GetIt.instance.get<DashboardViewModel>();

  @override
  Widget build(BuildContext context) {
    var rowChildren = [
      Expanded(child: _buildLineChart()),
      Expanded(child: _buildBarChart()),
    ];
    var row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: ShadcnSpacing.spacing16,
      children: rowChildren,
    );
    var column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: ShadcnSpacing.spacing24,
      children: [_buildTokenHeatmap(), row],
    );
    var singleChildScrollView = SingleChildScrollView(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
      child: column,
    );
    var pageHeader = const PageHeader(title: '控制面板', subtitle: '请求统计与数据分析');
    var children = [pageHeader, Expanded(child: singleChildScrollView)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildBarChart() {
    return Watch((_) {
      final modelDateTokenStats = viewModel.modelDateTokenUsage.value;
      Widget chart = const Center(child: Text('暂无数据'));
      if (modelDateTokenStats.isNotEmpty) {
        chart = DashboardTokenBarChart(
          modelDateTokenStats: modelDateTokenStats,
        );
      }
      const textStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.bold);
      var children = [
        const Text('模型Token', style: textStyle),
        Expanded(child: chart),
      ];
      var column = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: ShadcnSpacing.spacing12,
        children: children,
      );
      var padding = Padding(
        padding: const EdgeInsets.all(ShadcnSpacing.spacing16),
        child: column,
      );
      return SizedBox(
        height: 320,
        child: ShadCard(padding: EdgeInsets.zero, child: padding),
      );
    });
  }

  Widget _buildTokenHeatmap() {
    return Watch((_) {
      final dailyTokens = viewModel.dailyTokenStats.value;
      return DashboardTokenHeatmap(dailyTokens);
    });
  }

  Widget _buildLineChart() {
    return Watch((_) {
      final dailyRequests = viewModel.dailyRequests.value;
      Widget chart = const Center(child: Text('暂无数据'));
      if (dailyRequests.isNotEmpty) {
        chart = DashboardRequestsChart(dailyStats: dailyRequests);
      }
      const textStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.bold);
      var children = [
        const Text('请求数量', style: textStyle),
        Expanded(child: chart),
      ];
      var column = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: ShadcnSpacing.spacing12,
        children: children,
      );
      var padding = Padding(
        padding: const EdgeInsets.all(ShadcnSpacing.spacing16),
        child: column,
      );
      return SizedBox(
        height: 320,
        child: ShadCard(padding: EdgeInsets.zero, child: padding),
      );
    });
  }
}
