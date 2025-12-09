import 'package:code_proxy/model/proxy_server_state.dart';
import 'package:code_proxy/themes/shadcn_colors.dart';
import 'package:code_proxy/themes/shadcn_spacing.dart';
import 'package:code_proxy/themes/shadcn_color_helpers.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
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
          // 标题栏
          Container(
            padding: const EdgeInsets.all(ShadcnSpacing.spacing24),
            child: Row(
              children: [
                Text(
                  'Code Proxy'.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Watch((context) {
                  final isRunning = viewModel.isServerRunning.value;
                  return FilledButton.icon(
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
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),
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
                  Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          label: '总请求',
                          value: serverState.totalRequests.toString(),
                          icon: Icons.analytics_outlined,
                          accentColor: ShadcnColors.info,
                        ),
                      ),
                      const SizedBox(width: ShadcnSpacing.spacing16),
                      Expanded(
                        child: StatCard(
                          label: '成功率',
                          value:
                              '${serverState.successRate.toStringAsFixed(1)}%',
                          icon: Icons.check_circle_outline,
                          accentColor: ShadcnColors.success,
                        ),
                      ),
                      const SizedBox(width: ShadcnSpacing.spacing16),
                      Expanded(
                        child: StatCard(
                          label: '运行时间',
                          value: _formatUptime(serverState.uptimeSeconds),
                          icon: Icons.timer_outlined,
                          accentColor: ShadcnColors.warning,
                        ),
                      ),
                      const SizedBox(width: ShadcnSpacing.spacing16),
                      Expanded(
                        child: StatCard(
                          label: '活跃连接',
                          value: serverState.activeConnections.toString(),
                          icon: Icons.link,
                          accentColor: ShadcnColors.secondary,
                        ),
                      ),
                    ],
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
