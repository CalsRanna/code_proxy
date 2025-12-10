import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: '控制面板',
            subtitle: 'Token 使用统计',
            icon: LucideIcons.layoutGrid,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Token使用热度图
                  Watch((context) {
                    final dailyTokens = viewModel.dailyTokenStats.value;
                    return TokenHeatmap(dailyTokens: dailyTokens, weeks: 52);
                  }),
                  const SizedBox(height: ShadcnSpacing.spacing16),
                  // TODO: 使用 fl_chart 添加更有意义的统计图表
                  // 可以包括：
                  // - 每日请求量趋势图
                  // - 端点响应时间分布
                  // - 成功率趋势
                  // - Token 使用量分析
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}
