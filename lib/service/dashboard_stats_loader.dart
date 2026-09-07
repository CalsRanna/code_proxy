import 'dart:isolate';

import 'package:code_proxy/model/dashboard_overview_stats.dart';
import 'package:code_proxy/model/model_date_token_stat.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:sqlite3/sqlite3.dart';

/// Dashboard 全部聚合查询的结果，字段均为可跨 isolate 传输的纯数据。
class DashboardStatsResult {
  /// 概览卡片：消息数、token 总量、活跃天数、缓存命中率。
  final DashboardOverviewStats overview;

  /// 最近 15 天每日请求数（折线图）。
  final Map<String, int> dailyRequests;

  /// 全年每日请求数（热力图）。
  final Map<String, int> heatmapRequests;

  /// 最近 15 天按端点的 token 总量。
  final Map<String, int> endpointTokens;

  /// 最近 15 天按「日期 + 模型」的 token 用量（柱状图与每日费用）。
  final List<ModelDateTokenStat> recentModelTokens;

  /// 全时间按「日期 + 模型」的 token 用量（总费用）。
  final List<ModelDateTokenStat> allModelTokens;

  DashboardStatsResult({
    required this.overview,
    required this.dailyRequests,
    required this.heatmapRequests,
    required this.endpointTokens,
    required this.recentModelTokens,
    required this.allModelTokens,
  });
}

/// 在后台 isolate 中一次性执行 dashboard 的全部聚合查询。
///
/// laconic 的 sqlite 驱动在调用 isolate 上同步执行 SQL：5 万行以上的
/// 全年/全历史聚合会占住 UI isolate 数十上百毫秒，与渲染抢同一帧。
/// 这里改用独立 isolate 执行同一批 SQL（文本来自
/// [DashboardAggregationSql]，与主 isolate 口径天然一致），查询期间
/// UI 无感；SQL 参数与结果对象均为可跨 isolate 传输的纯数据。
class DashboardStatsLoader {
  /// [now] 仅供测试注入固定时间，生产调用不传。
  Future<DashboardStatsResult> load(String dbPath, {DateTime? now}) {
    return Isolate.run(() => _compute(dbPath, now: now));
  }
}

DashboardStatsResult _compute(String dbPath, {DateTime? now}) {
  final db = sqlite3.open(dbPath);
  try {
    final modifier = DashboardAggregationSql.localDateModifier();
    // 与调用方传入的 now 保持同一时刻，避免跨天边界时窗口不一致
    final referenceNow = now ?? DateTime.now();
    final endTimestamp = referenceNow.millisecondsSinceEpoch;

    // 折线图与每日费用的 15 天窗口
    final recentStart = referenceNow
        .subtract(const Duration(days: 15))
        .millisecondsSinceEpoch;
    // 热力图：今年 1 月 1 日到 12 月 31 日（含未来日期，由 UI 置灰）
    final yearStart = DateTime(referenceNow.year, 1, 1)
        .millisecondsSinceEpoch;
    final yearEnd = DateTime(referenceNow.year, 12, 31, 23, 59, 59, 999)
        .millisecondsSinceEpoch;

    final dailyRequests = _toIntMap(
      db.select(
        DashboardAggregationSql.dailyRequestStats(modifier),
        [recentStart, endTimestamp],
      ),
      dateKey: 'date',
      countKey: 'request_count',
    );
    final heatmapRequests = _toIntMap(
      db.select(
        DashboardAggregationSql.dailyRequestStats(modifier),
        [yearStart, yearEnd],
      ),
      dateKey: 'date',
      countKey: 'request_count',
    );
    final endpointTokens = _toIntMap(
      db.select(
        DashboardAggregationSql.endpointTokenStats(modifier),
        [recentStart, endTimestamp],
      ),
      dateKey: 'endpoint_name',
      countKey: 'total_tokens',
    );
    final recentModelTokens = _toModelTokenStats(
      db.select(
        DashboardAggregationSql.modelDateTokenStats(modifier),
        [recentStart, endTimestamp],
      ),
    );
    final allModelTokens = _toModelTokenStats(
      db.select(
        DashboardAggregationSql.modelDateTokenStats(modifier),
        [0, endTimestamp],
      ),
    );
    final overviewRows = db.select(
      DashboardAggregationSql.overviewStats(modifier),
      [],
    );
    final overviewRow = overviewRows.first;

    return DashboardStatsResult(
      overview: DashboardOverviewStats(
        messages: overviewRow['messages'] as int,
        totalTokens: overviewRow['total_tokens'] as int,
        activeDays: overviewRow['active_days'] as int,
        cacheHitRate: (overviewRow['cache_hit_rate'] as num).toDouble(),
      ),
      dailyRequests: dailyRequests,
      heatmapRequests: heatmapRequests,
      endpointTokens: endpointTokens,
      recentModelTokens: recentModelTokens,
      allModelTokens: allModelTokens,
    );
  } finally {
    db.dispose();
  }
}

Map<String, int> _toIntMap(
  ResultSet rows, {
  required String dateKey,
  required String countKey,
}) {
  final result = <String, int>{};
  for (final row in rows) {
    result[row[dateKey] as String] = row[countKey] as int;
  }
  return result;
}

List<ModelDateTokenStat> _toModelTokenStats(ResultSet rows) {
  return rows.map((row) {
    return ModelDateTokenStat(
      date: row['date'] as String,
      model: row['model'] as String,
      input: row['input'] as int,
      output: row['output'] as int,
      cacheCreation: row['cache_creation'] as int,
      cacheRead: row['cache_read'] as int,
    );
  }).toList();
}
