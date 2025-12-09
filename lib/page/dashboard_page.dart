import 'package:code_proxy/model/proxy_server_state.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/themes/shadcn_color_helpers.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
import 'package:code_proxy/widgets/common/page_header.dart';
import 'package:code_proxy/widgets/common/shadcn_components.dart';
import 'package:code_proxy/widgets/token_heatmap.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

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
            final isRunning = viewModel.isServerRunning.value;
            return PageHeader(
              title: '控制面板',
              subtitle: isRunning && serverState.listenAddress != null
                  ? '服务器运行中 - ${serverState.listenAddress}:${serverState.listenPort}'
                  : '服务器已停止',
              icon: Icons.dashboard_outlined,
              actions: [
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      if (isRunning) {
                        await viewModel.stopServer();
                      } else {
                        await viewModel.startServer();
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('操作失败: $e')),
                        );
                      }
                    }
                  },
                  icon: Icon(
                    isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(isRunning ? '停止服务器' : '启动服务器'),
                  style: FilledButton.styleFrom(
                    backgroundColor: isRunning
                        ? ShadcnColors.error
                        : ShadcnColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: ShadcnSpacing.buttonPaddingH,
                      vertical: ShadcnSpacing.buttonPaddingV,
                    ),
                  ),
                ),
              ],
            );
          }),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ServerStatusCard(state: serverState),
                  const SizedBox(height: ShadcnSpacing.spacing16),
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
                            icon: Icons.analytics_outlined,
                            accentColor: ShadcnColors.info,
                          ),
                          StatCard(
                            label: '成功率',
                            value:
                                '${serverState.successRate.toStringAsFixed(1)}%',
                            icon: Icons.check_circle_outline,
                            accentColor: ShadcnColors.success,
                          ),
                          StatCard(
                            label: '运行时间',
                            value: _formatUptime(serverState.uptimeSeconds),
                            icon: Icons.timer_outlined,
                            accentColor: ShadcnColors.warning,
                          ),
                          StatCard(
                            label: '活跃连接',
                            value: serverState.activeConnections.toString(),
                            icon: Icons.link,
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

class _ServerStatusCard extends StatelessWidget {
  final ProxyServerState state;

  const _ServerStatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isRunning = state.running;

    // 使用StatusType确定颜色
    final statusColors = ShadcnColorHelpers.forStatus(
      isRunning ? StatusType.success : StatusType.neutral,
      brightness,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusLarge),
        color: statusColors.background,
        border: Border.all(
          color: statusColors.border,
          width: ShadcnSpacing.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: brightness == Brightness.dark
                  ? ShadcnSpacing.shadowOpacityDarkSmall
                  : ShadcnSpacing.shadowOpacityLightSmall,
            ),
            blurRadius: ShadcnSpacing.shadowBlurSmall,
            offset: Offset(0, ShadcnSpacing.shadowOffsetSmall),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
        child: Row(
          children: [
            // 使用新建的IconBadge组件
            IconBadge(
              icon: isRunning ? Icons.check_circle : Icons.pause_circle,
              color: statusColors.foreground,
              size: IconBadgeSize.large,
            ),
            const SizedBox(width: ShadcnSpacing.spacing24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isRunning ? '服务器运行中' : '服务器已停止',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  if (isRunning && state.listenAddress != null)
                    StatusBadge(
                      label: '${state.listenAddress}:${state.listenPort}',
                      type: StatusType.info,
                    )
                  else
                    Text(
                      '点击右上角按钮启动代理服务器',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ShadcnColors.mutedForeground(brightness),
                          ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
