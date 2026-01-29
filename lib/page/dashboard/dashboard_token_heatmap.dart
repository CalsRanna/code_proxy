import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DashboardTokenHeatmap extends StatelessWidget {
  static const int _daysPerWeek = 7;
  static const double _cellSpacing = 2.0;
  static const double _cellMargin = 1.0;
  static const double _monthLabelHeight = 14.0;
  static const double _monthLabelFontSize = 10.0;
  static const double _borderRadius = 2.0;
  static const double _weekdayLabelWidth = 16.0;
  static const double _weekdayLabelFontSize = 10.0;

  final Map<String, int> chartData;
  final DateTime? now;

  const DashboardTokenHeatmap(this.chartData, {super.key, this.now});

  @override
  Widget build(BuildContext context) {
    final currentDate = now ?? DateTime.now();
    final heatmapData = _generateHeatmapData(currentDate);

    final maxRequests = chartData.values.isEmpty
        ? 1
        : chartData.values.reduce((a, b) => a > b ? a : b);

    var layoutBuilder = LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = _calculateCellSize(
          constraints.maxWidth,
          heatmapData.length,
        );
        var children = [
          _buildMonthLabels(heatmapData, cellSize),
          _buildHeatmapGrid(heatmapData, maxRequests, cellSize),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: ShadcnSpacing.spacing4,
          children: children,
        );
      },
    );
    return ShadCard(
      padding: EdgeInsets.all(ShadcnSpacing.spacing16),
      child: layoutBuilder,
    );
  }

  Widget _buildDayCell(_DayData dayData, int maxRequests, double cellSize) {
    if (dayData.isEmpty) {
      // 空白格子也需要保持相同的 margin，确保对齐
      return Container(
        width: cellSize,
        height: cellSize,
        margin: const EdgeInsets.all(_cellMargin),
      );
    }

    final color = _getColorForRequests(dayData.requests, maxRequests);
    final dateStr = dayData.date.toString().substring(0, 10);
    final tooltipMessage = dayData.isFuture
        ? dateStr
        : '$dateStr\n${dayData.requests}次请求';

    var anchor = ShadAnchor(
      overlayAlignment: Alignment.topCenter,
      childAlignment: Alignment.bottomCenter,
    );
    var boxDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(_borderRadius),
      color: color,
    );
    var container = Container(
      decoration: boxDecoration,
      height: cellSize,
      margin: const EdgeInsets.all(_cellMargin),
      width: cellSize,
    );
    var textStyle = TextStyle(color: ShadcnColors.lightBackground);
    return ShadTooltip(
      anchor: anchor,
      builder: (context) => Text(tooltipMessage, style: textStyle),
      child: ShadGestureDetector(child: container),
    );
  }

  Widget _buildHeatmapGrid(
    List<List<_DayData>> heatmapData,
    int maxRequests,
    double cellSize,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 星期标签列
        _buildWeekdayLabels(cellSize),
        // 热力图格子
        for (final week in heatmapData)
          Column(
            children: [
              for (final dayData in week)
                _buildDayCell(dayData, maxRequests, cellSize),
            ],
          ),
      ],
    );
  }

  /// 构建星期标签列（只显示一、三、五）
  Widget _buildWeekdayLabels(double cellSize) {
    final cellHeight = cellSize + _cellSpacing;
    const weekdays = ['', '一', '', '三', '', '五', ''];

    return Container(
      width: _weekdayLabelWidth,
      margin: const EdgeInsets.only(right: ShadcnSpacing.spacing4),
      child: Column(
        children: [
          for (int i = 0; i < _daysPerWeek; i++)
            Container(
              height: cellHeight,
              alignment: Alignment.center,
              child: weekdays[i].isEmpty
                  ? null
                  : Text(
                      weekdays[i],
                      style: const TextStyle(
                        fontSize: _weekdayLabelFontSize,
                        color: ShadcnColors.zinc500,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildMonthLabels(List<List<_DayData>> heatmapData, double cellSize) {
    final labels = <Widget>[];
    String? lastMonth;
    double offset = _weekdayLabelWidth + ShadcnSpacing.spacing4; // 考虑星期标签的宽度和间距
    final cellWidth = cellSize + _cellSpacing;
    final currentYear = (now ?? DateTime.now()).year;

    for (final week in heatmapData) {
      if (week.isEmpty) {
        offset += cellWidth;
        continue;
      }

      final firstDateOfWeek = week.first.date;

      // 只显示当前年份的月份标签
      if (firstDateOfWeek.year == currentYear) {
        final monthStr = '${firstDateOfWeek.month}';

        if (monthStr != lastMonth) {
          labels.add(
            Positioned(
              left: offset,
              width: cellWidth,
              child: Center(
                child: Text(
                  monthStr,
                  style: const TextStyle(
                    fontSize: _monthLabelFontSize,
                    color: ShadcnColors.zinc500,
                  ),
                ),
              ),
            ),
          );
          lastMonth = monthStr;
        }
      } else {
        // 如果这周不是当前年份，重置 lastMonth，避免跨年时标签被跳过
        lastMonth = null;
      }

      offset += cellWidth;
    }

    final totalWidth =
        heatmapData.length * cellWidth +
        _weekdayLabelWidth +
        ShadcnSpacing.spacing4;

    return SizedBox(
      width: totalWidth,
      height: _monthLabelHeight,
      child: Stack(children: labels),
    );
  }

  /// 计算格子大小
  /// 每个格子有 margin: all(1)，所以每个格子实际占用 cellSize + _cellSpacing
  double _calculateCellSize(double availableWidth, int totalWeeks) {
    // 减去星期标签的宽度和间距
    final adjustedWidth =
        availableWidth - _weekdayLabelWidth - ShadcnSpacing.spacing4;
    return (adjustedWidth / totalWeeks) - _cellSpacing;
  }

  /// 计算包含指定日期的第一个周日
  DateTime _calculateFirstSunday(DateTime date) {
    final daysFromSunday = date.weekday % _daysPerWeek;
    return date.subtract(Duration(days: daysFromSunday));
  }

  /// 计算包含指定日期的最后一个周六
  DateTime _calculateLastSaturday(DateTime date) {
    final daysToSaturday = (6 - date.weekday % _daysPerWeek);
    return date.add(Duration(days: daysToSaturday));
  }

  /// 创建单个日期的数据
  _DayData _createDayData(DateTime date, int targetYear, DateTime currentDate) {
    // 不在目标年份的日期
    if (date.year != targetYear) {
      return _DayData.empty(date);
    }

    // 在目标年份的日期
    final dateStr = _formatDate(date);
    final requests = chartData[dateStr] ?? 0;
    final isToday = _isSameDay(date, currentDate);
    final isFuture = date.isAfter(currentDate);

    return _DayData(
      date: date,
      requests: requests,
      isToday: isToday,
      isFuture: isFuture,
    );
  }

  /// 补全一周的剩余天数
  void _fillRemainingWeek(List<_DayData> week) {
    while (week.length < _daysPerWeek) {
      final lastDate = week.last.date;
      final nextDate = lastDate.add(const Duration(days: 1));
      week.add(_DayData.empty(nextDate));
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 生成热力图数据
  List<List<_DayData>> _generateHeatmapData(DateTime currentDate) {
    final year = currentDate.year;
    final startDate = DateTime(year, 1, 1);
    final endDate = DateTime(year, 12, 31);

    final firstSunday = _calculateFirstSunday(startDate);
    final lastSaturday = _calculateLastSaturday(endDate);

    return _generateWeeksList(firstSunday, lastSaturday, year, currentDate);
  }

  /// 生成周列表
  List<List<_DayData>> _generateWeeksList(
    DateTime firstSunday,
    DateTime lastSaturday,
    int targetYear,
    DateTime currentDate,
  ) {
    final totalDays = lastSaturday.difference(firstSunday).inDays + 1;
    final weeksList = <List<_DayData>>[];
    var currentWeek = <_DayData>[];

    for (int i = 0; i < totalDays; i++) {
      final date = firstSunday.add(Duration(days: i));
      final dayData = _createDayData(date, targetYear, currentDate);

      currentWeek.add(dayData);

      if (currentWeek.length == _daysPerWeek) {
        weeksList.add(currentWeek);
        currentWeek = <_DayData>[];
      }
    }

    // 补全最后一周
    if (currentWeek.isNotEmpty) {
      _fillRemainingWeek(currentWeek);
      weeksList.add(currentWeek);
    }

    return weeksList;
  }

  Color _getColorForRequests(int requests, int maxRequests) {
    if (requests == 0) return ShadcnColors.zinc100;
    final intensity = (requests / maxRequests).clamp(0.0, 1.0);
    const baseColor = ShadcnColors.warning;
    if (intensity <= 0.25) {
      return baseColor.withValues(alpha: 0.25);
    } else if (intensity <= 0.5) {
      return baseColor.withValues(alpha: 0.5);
    } else if (intensity <= 0.75) {
      return baseColor.withValues(alpha: 0.75);
    } else {
      return baseColor;
    }
  }

  /// 判断两个日期是否为同一天
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}

class _DayData {
  final DateTime date;
  final int requests;
  final bool isToday;
  final bool isEmpty;
  final bool isFuture;

  const _DayData({
    required this.date,
    required this.requests,
    required this.isToday,
    this.isEmpty = false,
    this.isFuture = false,
  });

  /// 创建空白占位符（年初/年末）
  factory _DayData.empty(DateTime date) {
    return _DayData(date: date, requests: -1, isToday: false, isEmpty: true);
  }
}
