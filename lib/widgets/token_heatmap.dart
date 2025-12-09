import 'package:flutter/material.dart';
import '../themes/shadcn_colors.dart';
import '../themes/shadcn_spacing.dart';

/// GitHub风格的请求成功热度图（Shadcn UI 风格）
class TokenHeatmap extends StatelessWidget {
  /// 每日请求统计数据，key为日期字符串（YYYY-MM-DD），value为成功请求数
  final Map<String, int> dailyTokens;

  /// 显示的周数（默认52周，即一年）
  final int weeks;

  const TokenHeatmap({super.key, required this.dailyTokens, this.weeks = 52});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final heatmapData = _generateHeatmapData();

    // 计算最大请求数，用于颜色映射
    final maxRequests = dailyTokens.values.isEmpty
        ? 1
        : dailyTokens.values.reduce((a, b) => a > b ? a : b);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ShadcnSpacing.radiusMedium),
        color: ShadcnColors.muted(brightness),
        border: Border.all(
          color: ShadcnColors.border(brightness),
          width: ShadcnSpacing.borderWidth,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ShadcnSpacing.spacing20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(children: [const Spacer(), _buildLegend(context, brightness)]),
            const SizedBox(height: 16),
            // 热度图 - 根据容器宽度自动计算格子大小
            LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;

                // 计算实际周数
                final actualWeeks = heatmapData.length;

                // 根据周数和可用宽度计算每个格子的大小
                // 每个格子有 margin: all(1)，所以每个格子实际占用 cellWidth + 2px
                // 总宽度 = actualWeeks * (cellWidth + 2)
                // cellWidth = availableWidth / actualWeeks - 2
                final cellWidth = (availableWidth / actualWeeks) - 2;
                final cellHeight = cellWidth; // 保持方形

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 月份标签
                    _buildMonthLabels(
                      heatmapData,
                      cellWidth,
                      0,
                    ),
                    const SizedBox(height: 4),
                    // 热度方格
                    _buildHeatmapGrid(
                      context,
                      heatmapData,
                      maxRequests,
                      brightness,
                      cellWidth,
                      cellHeight,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 生成热度图数据（按周分组）
  List<List<_DayData>> _generateHeatmapData() {
    final now = DateTime.now();
    // 从今年1月1日开始
    final startDate = DateTime(now.year, 1, 1);
    // 到今年12月31日结束
    final endDate = DateTime(now.year, 12, 31);

    // 找到1月1日所在周的周日（作为起始点）
    final firstSunday = startDate.subtract(
      Duration(days: (startDate.weekday % 7)),
    );

    // 找到12月31日所在周的周六（作为结束点）
    final lastSaturday = endDate.add(
      Duration(days: (6 - endDate.weekday % 7)),
    );

    // 计算总天数
    final totalDays = lastSaturday.difference(firstSunday).inDays + 1;
    final totalWeeks = (totalDays / 7).ceil();

    final List<List<_DayData>> weeksList = [];
    List<_DayData> currentWeek = [];

    // 生成所有日期
    for (int i = 0; i < totalWeeks * 7; i++) {
      final date = firstSunday.add(Duration(days: i));

      // 跳过今年1月1日之前的日期（用空白填充）
      if (date.year < now.year) {
        currentWeek.add(
          _DayData(date: date, requests: -1, isToday: false, isEmpty: true),
        );
        if (currentWeek.length == 7) {
          weeksList.add(currentWeek);
          currentWeek = [];
        }
        continue;
      }

      // 跳过12月31日之后的日期（用空白填充）
      if (date.year > now.year) {
        currentWeek.add(
          _DayData(date: date, requests: -1, isToday: false, isEmpty: true),
        );
        if (currentWeek.length == 7) {
          weeksList.add(currentWeek);
          currentWeek = [];
        }
        continue;
      }

      final dateStr = _formatDate(date);
      final requests = dailyTokens[dateStr] ?? 0;
      final isToday =
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
      // 未来日期标记为空但不是完全透明
      final isFuture = date.isAfter(now);

      currentWeek.add(
        _DayData(
          date: date,
          requests: requests,
          isToday: isToday,
          isEmpty: false,
          isFuture: isFuture,
        ),
      );

      // 每7天（一周）创建新列
      if (currentWeek.length == 7) {
        weeksList.add(currentWeek);
        currentWeek = [];
      }
    }

    // 添加最后未满的一周（理论上不会出现，因为我们已经对齐到周六）
    if (currentWeek.isNotEmpty) {
      while (currentWeek.length < 7) {
        final lastDate = currentWeek.last.date;
        final nextDate = lastDate.add(const Duration(days: 1));
        currentWeek.add(
          _DayData(date: nextDate, requests: -1, isToday: false, isEmpty: true),
        );
      }
      weeksList.add(currentWeek);
    }

    return weeksList;
  }

  /// 格式化日期为 YYYY-MM-DD
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 构建月份标签
  Widget _buildMonthLabels(
    List<List<_DayData>> heatmapData,
    double cellWidth,
    double leftMargin,
  ) {
    final List<Widget> labels = [];
    String? lastMonth;
    double offset = 0;

    for (int i = 0; i < heatmapData.length; i++) {
      final week = heatmapData[i];
      if (week.isEmpty) continue;

      final date = week.first.date;
      final monthStr = '${date.month}月';

      // 只在月份变化时显示标签
      if (monthStr != lastMonth) {
        labels.add(
          Positioned(
            left: offset,
            child: Text(
              monthStr,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        );
        lastMonth = monthStr;
      }

      offset += cellWidth + 2; // cellWidth + 2px间距
    }

    // 计算总宽度
    final totalWidth = heatmapData.length * (cellWidth + 2);

    return Container(
      height: 14,
      margin: EdgeInsets.only(left: leftMargin),
      child: SizedBox(
        width: totalWidth,
        height: 14,
        child: Stack(children: labels),
      ),
    );
  }

  /// 构建热度图网格
  Widget _buildHeatmapGrid(
    BuildContext context,
    List<List<_DayData>> heatmapData,
    int maxRequests,
    Brightness brightness,
    double cellWidth,
    double cellHeight,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: heatmapData.map((week) {
        return Column(
          children: week.map((dayData) {
            return _buildDayCell(
              context,
              dayData,
              maxRequests,
              brightness,
              cellWidth,
              cellHeight,
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  /// 构建单个日期方格
  Widget _buildDayCell(
    BuildContext context,
    _DayData dayData,
    int maxRequests,
    Brightness brightness,
    double cellWidth,
    double cellHeight,
  ) {
    // 如果是空白日期（年初/年末的占位），返回透明占位符
    if (dayData.isEmpty) {
      return Container(
        width: cellWidth,
        height: cellHeight,
        margin: const EdgeInsets.all(1),
      );
    }

    final color = _getColorForRequests(
      context,
      dayData.requests,
      maxRequests,
      brightness,
      isFuture: dayData.isFuture,
    );

    return Tooltip(
      message: dayData.isFuture
          ? '${_formatDate(dayData.date)}\n未来日期'
          : '${_formatDate(dayData.date)}\n${dayData.requests} 个请求',
      child: Container(
        width: cellWidth,
        height: cellHeight,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          border: dayData.isToday
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                )
              : null,
        ),
      ),
    );
  }

  /// 根据请求数量获取颜色
  Color _getColorForRequests(
    BuildContext context,
    int requests,
    int maxRequests,
    Brightness brightness, {
    bool isFuture = false,
  }) {
    final isDark = brightness == Brightness.dark;

    // 未来日期和无数据都显示相同的浅灰色
    if (isFuture || requests == 0) {
      return isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    }

    // 计算颜色强度（0-1）
    final intensity = (requests / maxRequests).clamp(0.0, 1.0);

    // 使用绿色系，类似GitHub
    final baseColor = isDark
        ? const Color(0xFF39D353)
        : const Color(0xFF216E39);

    // 4个等级的颜色
    if (intensity <= 0.25) {
      return baseColor.withValues(alpha: isDark ? 0.3 : 0.3);
    } else if (intensity <= 0.5) {
      return baseColor.withValues(alpha: isDark ? 0.5 : 0.5);
    } else if (intensity <= 0.75) {
      return baseColor.withValues(alpha: isDark ? 0.75 : 0.75);
    } else {
      return baseColor;
    }
  }

  /// 构建图例
  Widget _buildLegend(BuildContext context, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF39D353)
        : const Color(0xFF216E39);
    final emptyColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('少', style: TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(width: 4),
        _buildLegendCell(emptyColor),
        _buildLegendCell(baseColor.withValues(alpha: isDark ? 0.3 : 0.3)),
        _buildLegendCell(baseColor.withValues(alpha: isDark ? 0.5 : 0.5)),
        _buildLegendCell(baseColor.withValues(alpha: isDark ? 0.75 : 0.75)),
        _buildLegendCell(baseColor),
        const SizedBox(width: 4),
        const Text('多', style: TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  /// 构建图例方格
  Widget _buildLegendCell(Color color) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// 单日数据
class _DayData {
  final DateTime date;
  final int requests;
  final bool isToday;
  final bool isEmpty; // 是否为空白占位符（年初/年末）
  final bool isFuture; // 是否为未来日期

  _DayData({
    required this.date,
    required this.requests,
    required this.isToday,
    this.isEmpty = false,
    this.isFuture = false,
  });
}
