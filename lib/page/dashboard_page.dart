import 'package:code_proxy/model/proxy_server_state.dart';
import 'package:code_proxy/view_model/home_view_model.dart';
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
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Text(
                  'Code Proxy'.toUpperCase(),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Watch((context) {
                  final isRunning = viewModel.isServerRunning.value;
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: isRunning
                              ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                              : const Color(0xFF10B981).withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      onPressed: () async {
                        try {
                          if (isRunning) {
                            await viewModel.stopServer();
                          } else {
                            await viewModel.startServer();
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text('操作失败: $e')));
                          }
                        }
                      },
                      icon: Icon(
                        isRunning
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(isRunning ? '停止服务器' : '启动服务器'),
                      style: FilledButton.styleFrom(
                        backgroundColor: isRunning
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
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
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ServerStatusCard(state: serverState),
                  const SizedBox(height: 16),
                  // Token使用热度图
                  Watch((context) {
                    final dailyTokens = viewModel.dailyTokenStats.value;
                    return TokenHeatmap(dailyTokens: dailyTokens, weeks: 52);
                  }),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: '总请求',
                          value: serverState.totalRequests.toString(),
                          icon: Icons.analytics_outlined,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          label: '成功率',
                          value:
                              '${serverState.successRate.toStringAsFixed(1)}%',
                          icon: Icons.check_circle_outline,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          label: '运行时间',
                          value: _formatUptime(serverState.uptimeSeconds),
                          icon: Icons.timer_outlined,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          label: '活跃连接',
                          value: serverState.activeConnections.toString(),
                          icon: Icons.link,
                          color: Colors.purple,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: state.running
              ? [
                  const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.1),
                  const Color(
                    0xFF059669,
                  ).withValues(alpha: isDark ? 0.15 : 0.05),
                ]
              : [
                  Colors.grey.withValues(alpha: isDark ? 0.2 : 0.1),
                  Colors.grey.withValues(alpha: isDark ? 0.15 : 0.05),
                ],
        ),
        border: Border.all(
          color: state.running
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: state.running
                ? const Color(0xFF10B981).withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: state.running
                      ? [const Color(0xFF10B981), const Color(0xFF059669)]
                      : [Colors.grey.shade400, Colors.grey.shade500],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: state.running
                        ? const Color(0xFF10B981).withValues(alpha: 0.4)
                        : Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                state.running ? Icons.check_circle : Icons.pause_circle,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.running ? '服务器运行中' : '服务器已停止',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (state.running && state.listenAddress != null)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${state.listenAddress}:${state.listenPort}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      '点击右上角按钮启动代理服务器',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: isDark ? 0.15 : 0.08),
            color.withValues(alpha: isDark ? 0.08 : 0.03),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.2 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const Spacer(),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
