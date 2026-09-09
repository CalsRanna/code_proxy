import 'package:code_proxy/page/dashboard/dashboard_tooltip.dart';
import 'package:code_proxy/theme/shadcn_colors.dart';
import 'package:code_proxy/theme/shadcn_spacing.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// GitHub 风格年度请求热力图，用单个 CustomPaint 绘制全部格子。
///
/// 此前每个格子都是一个带 ShadTooltip + GestureDetector 的 widget：全年
/// 约 370 个格子 × 4~5 层嵌套组件，每次数据刷新都要重建数千个 widget。
/// 改为一次 paint + 全局命中检测后，刷新开销从十几毫秒降到个位数。
class DashboardRequestHeatmap extends StatefulWidget {
  static const int _daysPerWeek = 7;
  static const double _cellSpacing = 2.0;
  static const double _cellMargin = 1.0;
  static const double _monthLabelHeight = 14.0;
  static const double _monthLabelFontSize = 10.0;
  static const double _borderRadius = 2.0;
  static const double _weekdayLabelWidth = 16.0;
  static const double _weekdayLabelFontSize = 10.0;

  final Map<String, int> chartData;

  const DashboardRequestHeatmap(this.chartData, {super.key});

  @override
  State<DashboardRequestHeatmap> createState() =>
      _DashboardRequestHeatmapState();
}

class _DashboardRequestHeatmapState extends State<DashboardRequestHeatmap> {
  /// 当前 hover 的格子坐标（周列 × 星期行），null 表示无 hover。
  int? _hoveredWeek;
  int? _hoveredDay;

  @override
  Widget build(BuildContext context) {
    final currentDate = DateTime.now();
    final heatmapData = _generateHeatmapData(currentDate);

    final maxRequests = widget.chartData.values.isEmpty
        ? 1
        : widget.chartData.values.reduce((a, b) => a > b ? a : b);

    return ShadCard(
      padding: EdgeInsets.all(ShadcnSpacing.spacing16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellSize = _calculateCellSize(
            constraints.maxWidth,
            heatmapData.length,
          );
          final totalWidth = _totalWidth(heatmapData.length, cellSize);
          final totalHeight = _totalHeight(cellSize);

          return SizedBox(
            width: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                MouseRegion(
                  onHover: (event) =>
                      _handleHover(event.localPosition, heatmapData, cellSize),
                  onExit: (_) => _clearHoverIfNeeded(),
                  child: SizedBox(
                    width: totalWidth,
                    height: totalHeight,
                    child: CustomPaint(
                      painter: _HeatmapPainter(
                        heatmapData: heatmapData,
                        chartData: widget.chartData,
                        cellSize: cellSize,
                        maxRequests: maxRequests,
                      ),
                    ),
                  ),
                ),
                if (_hoveredWeek != null && _hoveredDay != null)
                  _buildTooltip(heatmapData, cellSize),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建 hover 提示。
  ///
  /// 显示在格子上方并水平居中对齐；第一行格子空间不足时翻转到下方，
  /// 与 ShadTooltip 的默认行为一致。
  Widget _buildTooltip(List<List<_DayData>> heatmapData, double cellSize) {
    final week = _hoveredWeek!;
    final day = _hoveredDay!;
    final weekData = heatmapData[week];
    if (weekData.isEmpty) return const SizedBox.shrink();
    final dayData = weekData[day];
    if (dayData.isEmpty) return const SizedBox.shrink();

    final stride = cellSize + DashboardRequestHeatmap._cellSpacing;
    final cellLeft =
        DashboardRequestHeatmap._weekdayLabelWidth +
        ShadcnSpacing.spacing4 +
        week * stride +
        DashboardRequestHeatmap._cellMargin;
    final cellTop =
        _cellsTopOffset + day * stride + DashboardRequestHeatmap._cellMargin;

    // 与图表 tooltip 一致的样式：白色加粗标题行 + 紫色副行；
    // 日期不展示年份
    final shortDate =
        '${dayData.date.month.toString().padLeft(2, '0')}-'
        '${dayData.date.day.toString().padLeft(2, '0')}';

    // 第一行格子在上方放不下提示时翻转到下方
    final flip = day == 0;
    final tooltipTop = flip ? cellTop + cellSize + 4 : cellTop - 4;
    final translationY = flip ? 0.0 : -1.0;

    var tooltip = DashboardTooltip(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            shortDate,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (!dayData.isFuture) ...[
            const SizedBox(height: 3),
            Text(
              '${dayData.requests}次请求',
              style: const TextStyle(
                fontSize: 10,
                color: ShadcnColors.violet300,
              ),
            ),
          ],
        ],
      ),
    );

    return Positioned(
      left: cellLeft + cellSize / 2,
      top: tooltipTop,
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: Offset(-0.5, translationY),
          child: tooltip,
        ),
      ),
    );
  }

  /// 根据鼠标位置计算 hover 的格子并更新状态。
  void _handleHover(
    Offset localPosition,
    List<List<_DayData>> heatmapData,
    double cellSize,
  ) {
    final stride = cellSize + DashboardRequestHeatmap._cellSpacing;
    final x =
        localPosition.dx -
        DashboardRequestHeatmap._weekdayLabelWidth -
        ShadcnSpacing.spacing4;
    final y = localPosition.dy - _cellsTopOffset;

    // 命中标签列/标签行或越界时视为无 hover
    if (x < 0 || y < 0) {
      _clearHoverIfNeeded();
      return;
    }
    final week = (x / stride).floor();
    final day = (y / stride).floor();
    if (week < 0 ||
        week >= heatmapData.length ||
        day < 0 ||
        day >= DashboardRequestHeatmap._daysPerWeek) {
      _clearHoverIfNeeded();
      return;
    }
    final weekData = heatmapData[week];
    if (weekData.isEmpty || weekData[day].isEmpty) {
      _clearHoverIfNeeded();
      return;
    }
    if (week != _hoveredWeek || day != _hoveredDay) {
      setState(() {
        _hoveredWeek = week;
        _hoveredDay = day;
      });
    }
  }

  void _clearHoverIfNeeded() {
    if (_hoveredWeek == null && _hoveredDay == null) return;
    setState(() {
      _hoveredWeek = null;
      _hoveredDay = null;
    });
  }

  /// 绘制区顶部偏移：月份标签行 + 与格子行的间距。
  static const double _cellsTopOffset =
      DashboardRequestHeatmap._monthLabelHeight + ShadcnSpacing.spacing4;

  /// 格子行起点 x：星期标签列 + 右侧间距。
  static const double _cellsLeftOffset =
      DashboardRequestHeatmap._weekdayLabelWidth + ShadcnSpacing.spacing4;

  double _totalWidth(int totalWeeks, double cellSize) {
    return totalWeeks * (cellSize + DashboardRequestHeatmap._cellSpacing) +
        _cellsLeftOffset;
  }

  double _totalHeight(double cellSize) {
    return _cellsTopOffset +
        DashboardRequestHeatmap._daysPerWeek *
            (cellSize + DashboardRequestHeatmap._cellSpacing);
  }

  /// 计算格子大小
  /// 每个格子有 margin: all(1)，所以每个格子实际占用 cellSize + _cellSpacing
  double _calculateCellSize(double availableWidth, int totalWeeks) {
    // 减去星期标签的宽度和间距
    final adjustedWidth = availableWidth - _cellsLeftOffset;
    return (adjustedWidth / totalWeeks) - DashboardRequestHeatmap._cellSpacing;
  }

  /// 计算包含指定日期的第一个周日
  DateTime _calculateFirstSunday(DateTime date) {
    final daysFromSunday = date.weekday % DashboardRequestHeatmap._daysPerWeek;
    return date.subtract(Duration(days: daysFromSunday));
  }

  /// 计算包含指定日期的最后一个周六
  DateTime _calculateLastSaturday(DateTime date) {
    final daysToSaturday =
        (6 - date.weekday % DashboardRequestHeatmap._daysPerWeek);
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
    final requests = widget.chartData[dateStr] ?? 0;
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
    while (week.length < DashboardRequestHeatmap._daysPerWeek) {
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

      if (currentWeek.length == DashboardRequestHeatmap._daysPerWeek) {
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

  /// 判断两个日期是否为同一天
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}

/// 一次 paint 完成全部格子 / 星期 / 月份标签的绘制。
class _HeatmapPainter extends CustomPainter {
  final List<List<_DayData>> heatmapData;
  final Map<String, int> chartData;
  final double cellSize;
  final int maxRequests;

  _HeatmapPainter({
    required this.heatmapData,
    required this.chartData,
    required this.cellSize,
    required this.maxRequests,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stride = cellSize + DashboardRequestHeatmap._cellSpacing;
    final cellsTop = _DashboardRequestHeatmapState._cellsTopOffset;
    final cellsLeft = _DashboardRequestHeatmapState._cellsLeftOffset;

    _paintWeekdayLabels(canvas, cellsTop, stride);
    _paintCells(canvas, cellsTop, cellsLeft, stride);
    _paintMonthLabels(canvas, cellsLeft, stride);
  }

  void _paintWeekdayLabels(Canvas canvas, double cellsTop, double stride) {
    const weekdays = ['', '一', '', '三', '', '五', ''];
    for (int i = 0; i < weekdays.length; i++) {
      final label = weekdays[i];
      if (label.isEmpty) continue;
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: DashboardRequestHeatmap._weekdayLabelFontSize,
            color: ShadcnColors.zinc500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // 与格子行同高，垂直居中
      final y = cellsTop + i * stride + (stride - textPainter.height) / 2;
      textPainter.paint(
        canvas,
        Offset(
          (DashboardRequestHeatmap._weekdayLabelWidth - textPainter.width) / 2,
          y,
        ),
      );
    }
  }

  void _paintCells(
    Canvas canvas,
    double cellsTop,
    double cellsLeft,
    double stride,
  ) {
    final margin = DashboardRequestHeatmap._cellMargin;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int week = 0; week < heatmapData.length; week++) {
      final weekData = heatmapData[week];
      for (int day = 0; day < weekData.length; day++) {
        final dayData = weekData[day];
        if (dayData.isEmpty) continue;
        paint.color = _colorFor(dayData.requests);
        final rect = Rect.fromLTWH(
          cellsLeft + week * stride + margin,
          cellsTop + day * stride + margin,
          cellSize,
          cellSize,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect,
            const Radius.circular(DashboardRequestHeatmap._borderRadius),
          ),
          paint,
        );
      }
    }
  }

  void _paintMonthLabels(Canvas canvas, double cellsLeft, double stride) {
    final currentYear = DateTime.now().year;
    int? lastMonth;
    double offset = cellsLeft;

    for (final week in heatmapData) {
      if (week.isEmpty) {
        offset += stride;
        continue;
      }
      final firstDateOfWeek = week.first.date;
      if (firstDateOfWeek.year == currentYear) {
        final month = firstDateOfWeek.month;
        if (month != lastMonth) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: '$month',
              style: const TextStyle(
                fontSize: DashboardRequestHeatmap._monthLabelFontSize,
                color: ShadcnColors.zinc500,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          // 与前实现一致：标签水平居中对齐到周列，垂直居中于标签行
          textPainter.paint(
            canvas,
            Offset(
              offset + (stride - textPainter.width) / 2,
              (DashboardRequestHeatmap._monthLabelHeight - textPainter.height) /
                  2,
            ),
          );
          lastMonth = month;
        }
      } else {
        // 跨年时重置，避免下一年标签被跳过
        lastMonth = null;
      }
      offset += stride;
    }
  }

  Color _colorFor(int requests) {
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

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) {
    return oldDelegate.chartData != chartData ||
        oldDelegate.cellSize != cellSize ||
        oldDelegate.maxRequests != maxRequests;
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
