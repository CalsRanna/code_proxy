import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/model_date_token_stat.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:signals/signals.dart';

class DashboardViewModel {
  final dailyHeatmapRequests = signal<Map<String, int>>({});
  final dailyRequests = signal<Map<String, int>>({});
  final endpointTokenUsage = signal<Map<String, int>>({});
  final modelDateTokenUsage =
      signal<Map<String, Map<String, Map<String, int>>>>({});
  final dailyCost = signal<Map<String, double>>({});
  final totalCost = signal<double>(0.0);

  Future<void> initSignals() async {
    _loadHeatmapData();
    _loadChartData();
  }

  Future<void> _loadChartData() async {
    try {
      final repository = RequestLogRepository(Database.instance);
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 15));

      final results = await Future.wait([
        repository.getDailyRequestStats(
          startTimestamp: startDate.millisecondsSinceEpoch,
          endTimestamp: endDate.millisecondsSinceEpoch,
        ),
        repository.getEndpointTokenStats(
          startTimestamp: startDate.millisecondsSinceEpoch,
          endTimestamp: endDate.millisecondsSinceEpoch,
        ),
        repository.getModelDateTokenStats(
          startTimestamp: startDate.millisecondsSinceEpoch,
          endTimestamp: endDate.millisecondsSinceEpoch,
        ),
      ]);

      dailyRequests.value = results[0] as Map<String, int>;
      endpointTokenUsage.value = results[1] as Map<String, int>;

      // 费用计算前必须先就绪定价数据：首次进 dashboard 时 HomeViewModel
      // 可能还没加载完，缺了这一步每日费用会静默全部算成 0。
      final pricingService = ModelPricingService.instance;
      if (pricingService.modelCount.value == 0) {
        await pricingService.load();
      }

      // 同一份聚合结果同时喂给柱状图和每日费用，不再各查一次库
      final windowStats = results[2] as List<ModelDateTokenStat>;
      modelDateTokenUsage.value = _toChartShape(windowStats);
      dailyCost.value = _toDailyCost(windowStats);

      await _loadTotalCost(repository);
    } catch (e) {
      LoggerUtil.instance.e('Failed to load dashboard chart data: $e');
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
    final pricingService = ModelPricingService.instance;
    final Map<String, double> costs = {};
    for (final stat in stats) {
      costs[stat.date] = (costs[stat.date] ?? 0) + _cost(pricingService, stat);
    }
    return costs;
  }

  /// 全时间总费用。
  ///
  /// 单独查一次而非从 15 天结果推算：区间不同，且反过来从全时间结果里切
  /// 15 天会把边界那天从「按时间戳部分统计」变成「整天统计」，与折线图的
  /// 请求数口径对不上。
  Future<void> _loadTotalCost(RequestLogRepository repository) async {
    final allStats = await repository.getModelDateTokenStats(
      startTimestamp: 0,
      endTimestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final pricingService = ModelPricingService.instance;
    var total = 0.0;
    for (final stat in allStats) {
      total += _cost(pricingService, stat);
    }
    totalCost.value = total;
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

  Future<void> _loadHeatmapData() async {
    try {
      final repository = RequestLogRepository(Database.instance);
      final now = DateTime.now();
      final startDate = DateTime(now.year, 1, 1);
      final endDate = DateTime(now.year, 12, 31, 23, 59, 59, 999);
      final stats = await repository.getDailyRequestStats(
        startTimestamp: startDate.millisecondsSinceEpoch,
        endTimestamp: endDate.millisecondsSinceEpoch,
      );
      dailyHeatmapRequests.value = stats;
    } catch (e) {
      LoggerUtil.instance.e('Failed to load heatmap data: $e');
    }
  }
}
