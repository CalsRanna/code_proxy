import 'package:code_proxy/page/dashboard/dashboard_overview_cards.dart';
import 'package:code_proxy/page/dashboard/dashboard_request_line_chart.dart';
import 'package:code_proxy/page/dashboard/dashboard_token_bar_chart.dart';
import 'package:code_proxy/page/dashboard/dashboard_token_heatmap.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:code_proxy/view_model/dashboard_view_model.dart';
import 'package:code_proxy/widget/empty_state.dart';
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
    // 不套 SingleChildScrollView：统计卡片与热力图固定，图表行吃掉剩余
    // 空间并随窗口缩放，最小窗口（1080x720）下整页无滚动条。
    var column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: ShadcnSpacing.spacing24,
      children: [
        _buildOverviewCards(),
        _buildTokenHeatmap(),
        Expanded(child: _buildChartsRow()),
      ],
    );
    var padding = Padding(
      padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
      child: column,
    );
    var children = [_buildPageHeader(), Expanded(child: padding)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildChartsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: ShadcnSpacing.spacing16,
      children: [
        Expanded(child: _buildLineChart()),
        Expanded(child: _buildBarChart()),
      ],
    );
  }

  Widget _buildPageHeader() {
    return const PageHeader(title: 'CODE PROXY', subtitle: '代理状态与成本总览');
  }

  Widget _buildBarChart() {
    return Watch((_) {
      final modelDateTokenStats = viewModel.modelDateTokenUsage.value;
      Widget chart = const EmptyState();
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
      return ShadCard(padding: EdgeInsets.zero, child: padding);
    });
  }

  Widget _buildTokenHeatmap() {
    return Watch((_) {
      final dailyRequests = viewModel.dailyHeatmapRequests.value;
      return DashboardTokenHeatmap(dailyRequests);
    });
  }

  Widget _buildOverviewCards() {
    return Watch((_) {
      return DashboardOverviewCards(
        stats: viewModel.overviewStats.value,
        totalCost: viewModel.totalCost.value,
      );
    });
  }

  Widget _buildLineChart() {
    return Watch((_) {
      final dailyRequests = viewModel.dailyRequests.value;
      final costs = viewModel.dailyCost.value;
      Widget chart = const EmptyState();
      if (dailyRequests.isNotEmpty) {
        chart = DashboardRequestsChart(
          dailyStats: dailyRequests,
          dailyCost: costs,
        );
      }
      const textStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.bold);
      var children = <Widget>[
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
      return ShadCard(padding: EdgeInsets.zero, child: padding);
    });
  }
}
