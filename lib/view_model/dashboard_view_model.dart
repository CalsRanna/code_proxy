import 'dart:async';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/dashboard_overview_stats.dart';
import 'package:code_proxy/model/model_date_token_stat.dart';
import 'package:code_proxy/service/dashboard_stats_loader.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:signals/signals.dart';

class DashboardViewModel {
  DashboardViewModel({
    required Database database,
    required DashboardStatsLoader statsLoader,
    required ModelPricingService pricing,
    required Stream<void> logChanges,
  }) : _database = database,
       _statsLoader = statsLoader,
       _pricing = pricing {
    _subscription = logChanges.listen((_) => markDirty());
  }

  final Database _database;
  final DashboardStatsLoader _statsLoader;
  final ModelPricingService _pricing;
  late final StreamSubscription<void> _subscription;

  void dispose() => _subscription.cancel();

  final dailyHeatmapRequests = signal<Map<String, int>>({});
  final dailyRequests = signal<Map<String, int>>({});
  final modelDateTokenUsage =
      signal<Map<String, Map<String, Map<String, int>>>>({});
  final dailyCost = signal<Map<String, double>>({});
  final totalCost = signal<double>(0.0);
  final overviewStats = signal<DashboardOverviewStats>(
    const DashboardOverviewStats(messages: 0, totalTokens: 0, activeDays: 0),
  );

  /// 数据新鲜度窗口。
  ///
  /// 每次切入概览页都会触发 initSignals()。聚合查询已移到后台 isolate
  /// （见 DashboardStatsLoader）不再阻塞 UI，但每次切入都重跑一遍聚合
  /// 并重建整页图表仍是浪费。统计只会在代理产生新请求时变化，因此用
  /// 「新鲜度 + dirty」双条件：无新请求的频繁切换直接复用上次结果，
  /// 零查询、零重建。
  static const _freshThreshold = Duration(seconds: 60);

  DateTime? _lastLoadedAt;
  bool _dirty = false;
  bool _loading = false;

  /// 代理每完成一次请求后调用，标记下次进入概览页时重新聚合。
  void markDirty() {
    _dirty = true;
  }

  Future<void> initSignals() async {
    if (_loading) return;
    final lastLoadedAt = _lastLoadedAt;
    final isFresh =
        lastLoadedAt != null &&
        DateTime.now().difference(lastLoadedAt) < _freshThreshold;
    if (!_dirty && isFresh) return;

    _loading = true;
    try {
      _loadStats();
      // 查询发起即视为已刷新：加载失败会在下次超窗（或 markDirty）后重试
      _lastLoadedAt = DateTime.now();
      _dirty = false;
    } finally {
      _loading = false;
    }
  }

  Future<void> _loadStats() async {
    try {
      // 聚合查询在后台 isolate 执行（见 DashboardStatsLoader），
      // 5 万行以上的全年/全历史聚合不再阻塞 UI isolate。
      final stats = await _statsLoader.load(_database.path);

      // 费用计算前必须先就绪定价数据：首次进 dashboard 时 HomeViewModel
      // 可能还没加载完，缺了这一步每日费用会静默全部算成 0。
      final pricingService = _pricing;
      if (pricingService.modelCount.value == 0) {
        await pricingService.load();
      }

      dailyHeatmapRequests.value = stats.heatmapRequests;
      dailyRequests.value = stats.dailyRequests;

      // 同一份聚合结果同时喂给柱状图和每日费用，不再各查一次库
      modelDateTokenUsage.value = _toChartShape(stats.recentModelTokens);
      dailyCost.value = _toDailyCost(stats.recentModelTokens);
      totalCost.value = _totalCost(stats.allModelTokens);
      overviewStats.value = stats.overview;
    } catch (e) {
      LoggerUtil.instance.e('Failed to load dashboard stats: $e');
    }
  }

  /// 柱状图需要按 date → model 索引查表，这里把扁平聚合结果转成嵌套形状。
  ///
  /// 过滤掉零用量的组合：图表只画有数据的模型，全零条目会凭空多出一个图例。
  Map<String, Map<String, Map<String, int>>> _toChartShape(
    List<ModelDateTokenStat> stats,
  ) {
    final Map<String, Map<String, Map<String, int>>> shaped = {};
    for (final stat in stats) {
      if (stat.total <= 0) continue;
      shaped.putIfAbsent(stat.date, () => {});
      shaped[stat.date]![stat.model] = {
        'total': stat.total,
        'input': stat.input,
        'output': stat.output,
        'cache_read': stat.cacheRead,
        'cache_creation': stat.cacheCreation,
      };
    }
    return shaped;
  }

  Map<String, double> _toDailyCost(List<ModelDateTokenStat> stats) {
    final pricingService = _pricing;
    final Map<String, double> costs = {};
    for (final stat in stats) {
      costs[stat.date] = (costs[stat.date] ?? 0) + _cost(pricingService, stat);
    }
    return costs;
  }

  /// 全时间总费用。
  ///
  /// 与 [dailyCost] 共用后台 isolate 返回的全时间聚合结果：区间不同，
  /// 从 15 天结果反推会把边界那天从「按时间戳部分统计」变成「整天统计」，
  /// 与折线图的请求数口径对不上。
  double _totalCost(List<ModelDateTokenStat> allStats) {
    final pricingService = _pricing;
    var total = 0.0;
    for (final stat in allStats) {
      total += _cost(pricingService, stat);
    }
    return total;
  }

  double _cost(ModelPricingService pricingService, ModelDateTokenStat stat) {
    return pricingService.calculateCost(
      model: stat.model,
      inputTokens: stat.input,
      outputTokens: stat.output,
      cacheCreationTokens: stat.cacheCreation,
      cacheReadTokens: stat.cacheRead,
    );
  }
}
