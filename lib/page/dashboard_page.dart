import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
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
      final serverState = viewModel.serverState.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Watch((context) {
            return PageHeader(
              title: '控制面板',
              subtitle:
                  '服务器运行中 - ${serverState.listenAddress}:${serverState.listenPort}',
              icon: LucideIcons.layoutDashboard,
            );
          }),
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
                  // 响应式统计卡片网格
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columnCount = _getColumnCount(context);
                      return GridView.count(
                        crossAxisCount: columnCount,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: ShadcnSpacing.spacing16,
                        crossAxisSpacing: ShadcnSpacing.spacing16,
                        childAspectRatio: 1.5,
                        children: [
                          StatCard(
                            label: '总请求',
                            value: serverState.totalRequests.toString(),
                            icon: LucideIcons.activity,
                            accentColor: ShadcnColors.info,
                          ),
                          StatCard(
                            label: '成功率',
                            value:
                                '${serverState.successRate.toStringAsFixed(1)}%',
                            icon: LucideIcons.circleCheck,
                            accentColor: ShadcnColors.success,
                          ),
                          StatCard(
                            label: '运行时间',
                            value: _formatUptime(serverState.uptimeSeconds),
                            icon: LucideIcons.clock,
                            accentColor: ShadcnColors.warning,
                          ),
                          StatCard(
                            label: '活跃连接',
                            value: serverState.activeConnections.toString(),
                            icon: LucideIcons.link,
                            accentColor: ShadcnColors.secondary,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  String _formatUptime(int seconds) {
    if (seconds < 60) return '$seconds秒';
    if (seconds < 3600) return '${seconds ~/ 60}分钟';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '$hours小时$minutes分';
  }

  /// 根据屏幕宽度获取统计卡片列数
  int _getColumnCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 800) return 2; // 小屏：2列
    if (width < 1200) return 3; // 中屏：3列
    return 4; // 大屏：4列
  }
}
