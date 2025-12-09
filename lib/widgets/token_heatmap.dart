import 'package:flutter/material.dart';

/// GitHub风格的请求成功热度图
class TokenHeatmap extends StatelessWidget {
  /// 每日请求统计数据，key为日期字符串（YYYY-MM-DD），value为成功请求数
  final Map<String, int> dailyTokens;

  /// 显示的周数（默认52周，即一年）
  final int weeks;

  const TokenHeatmap({super.key, required this.dailyTokens, this.weeks = 52});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heatmapData = _generateHeatmapData();

    // 计算最大请求数，用于颜色映射
    final maxRequests = dailyTokens.values.isEmpty
        ? 1
        : dailyTokens.values.reduce((a, b) => a > b ? a : b);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(children: [const Spacer(), _buildLegend(context, isDark)]),
            const SizedBox(height: 16),
            // 热度图 - 使用LayoutBuilder动态计算格子大小
            LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                final weekdayLabelWidth = 40.0;
                final hGap = 8.0;

                // 计算每周的可用宽度
                final heatmapWidth =
                    availableWidth - weekdayLabelWidth - hGap - 2; //2px为border
                final cellWidth =
                    (heatmapWidth - (weeks - 1) * 2) / weeks; // 2px为间距
                final cellHeight = cellWidth; // 保持方形

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 月份标签
                    _buildMonthLabels(
                      heatmapData,
                      cellWidth,
                      weekdayLabelWidth + hGap,
                    ),
                    const SizedBox(height: 4),
                    // 热度方格
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 星期标签
                        _buildWeekdayLabels(context, cellHeight),
                        SizedBox(width: hGap),
                        // 热度方格网格
                        Expanded(
                          child: _buildHeatmapGrid(
                            context,
                            heatmapData,
                            maxRequests,
                            isDark,
                            cellWidth,
                            cellHeight,
                          ),
                        ),
                      ],
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
    final totalWeeks = weeks; // 使用成员变量
    final startDate = now.subtract(Duration(days: totalWeeks * 7));

    // 找到起始日期所在周的周日
    final firstSunday = startDate.subtract(
      Duration(days: (startDate.weekday % 7)),
    );

    final List<List<_DayData>> weeksList = [];
    List<_DayData> currentWeek = [];

    // 生成所有日期
    for (int i = 0; i < totalWeeks * 7; i++) {
      final date = firstSunday.add(Duration(days: i));
      final dateStr = _formatDate(date);
      final requests = dailyTokens[dateStr] ?? 0;
      final isToday =
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;

      currentWeek.add(
        _DayData(date: date, requests: requests, isToday: isToday),
      );

      // 每7天（一周）创建新列
      if ((i + 1) % 7 == 0) {
        weeksList.add(currentWeek);
        currentWeek = [];
      }
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

  /// 构建星期标签
  Widget _buildWeekdayLabels(BuildContext context, double cellHeight) {
    final weekdays = ['一', '三', '五'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(height: cellHeight), // 对齐第一行（周一）
        ...weekdays.map((day) {
          return Container(
            width: 40,
            height: cellHeight,
            alignment: Alignment.centerRight,
            margin: const EdgeInsets.only(bottom: 2),
            child: Text(
              day,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          );
        }),
      ],
    );
  }

  /// 构建热度图网格
  Widget _buildHeatmapGrid(
    BuildContext context,
    List<List<_DayData>> heatmapData,
    int maxRequests,
    bool isDark,
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
              isDark,
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
    bool isDark,
    double cellWidth,
    double cellHeight,
  ) {
    final color = _getColorForRequests(
      context,
      dayData.requests,
      maxRequests,
      isDark,
    );

    return Container(
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
    );
  }

  /// 根据请求数量获取颜色
  Color _getColorForRequests(
    BuildContext context,
    int requests,
    int maxRequests,
    bool isDark,
  ) {
    if (requests == 0) {
      // 无数据时显示浅灰色
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
  Widget _buildLegend(BuildContext context, bool isDark) {
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

  _DayData({required this.date, required this.requests, required this.isToday});
}
