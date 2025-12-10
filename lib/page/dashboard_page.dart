import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/widgets/charts/charts.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
import 'package:code_proxy/widgets/token_heatmap.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DashboardPage extends StatelessWidget {
  final HomeViewModel viewModel;

  const DashboardPage({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final chartData = viewModel.chartData.value;
      final dailyTokens = viewModel.dailyTokenStats.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: '控制面板',
            subtitle: '请求统计与数据分析',
            icon: LucideIcons.layoutGrid,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Token使用热度图（全年）
                  TokenHeatmap(dailyTokens: dailyTokens, weeks: 52),
                  const SizedBox(height: ShadcnSpacing.spacing24),

                  // 三个图表平均分布在一行（最近7天）
                  if (chartData != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: ShadcnSpacing.spacing16,
                      children: [
                        // 每日请求量趋势图
                        Expanded(
                          child: SizedBox(
                            height: 320,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(
                                  ShadcnSpacing.spacing16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '请求数量',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: ShadcnSpacing.spacing12,
                                    ),
                                    Expanded(
                                      child: DailyRequestsChart(
                                        dailyStats: chartData.dailyRequests,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 模型-日期Token使用柱状图
                        Expanded(
                          child: SizedBox(
                            height: 320,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(
                                  ShadcnSpacing.spacing16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '模型Token',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: ShadcnSpacing.spacing12,
                                    ),
                                    Expanded(
                                      child: ModelDateTokenBarChart(
                                        modelDateTokenStats:
                                            chartData.modelDateTokenUsage,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(ShadcnSpacing.spacing32),
                        child: Text(
                          '暂无数据，请先发送一些请求',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}
