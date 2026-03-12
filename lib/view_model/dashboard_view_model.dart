import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:signals/signals.dart';

class DashboardViewModel {
  final dailyTokenStats = signal<Map<String, int>>({});
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
    modelDateTokenUsage.value =
        results[2] as Map<String, Map<String, Map<String, int>>>;

    // 加载费用数据（图表用15天，总费用查全部）
    await _loadCostData(repository, startDate, endDate);
  }

  Future<void> _loadCostData(
    RequestLogRepository repository,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final pricingService = ModelPricingService.instance;

    // 确保定价数据已加载（首次进 dashboard 时可能 HomeViewModel 还没加载完）
    if (pricingService.modelCount.value == 0) {
      await pricingService.load();
    }

    // 15天内的每日费用（给图表 tooltip 用）
    final breakdown = await repository.getDailyModelTokenBreakdown(
      startTimestamp: startDate.millisecondsSinceEpoch,
      endTimestamp: endDate.millisecondsSinceEpoch,
    );

    final Map<String, double> costs = {};
    for (final row in breakdown) {
      final date = row['date'] as String;
      final cost = _calculateRowCost(pricingService, row);
      costs[date] = (costs[date] ?? 0) + cost;
    }
    dailyCost.value = costs;

    // 全部时间的总费用
    final allBreakdown = await repository.getDailyModelTokenBreakdown(
      startTimestamp: 0,
      endTimestamp: DateTime.now().millisecondsSinceEpoch,
    );

    double total = 0;
    for (final row in allBreakdown) {
      total += _calculateRowCost(pricingService, row);
    }
    totalCost.value = total;
  }

  double _calculateRowCost(
    ModelPricingService pricingService,
    Map<String, dynamic> row,
  ) {
    return pricingService.calculateCost(
      model: row['model'] as String,
      inputTokens: row['input'] as int,
      outputTokens: row['output'] as int,
      cacheCreationTokens: row['cache_creation'] as int,
      cacheReadTokens: row['cache_read'] as int,
    );
  }

  Future<void> _loadHeatmapData() async {
    final repository = RequestLogRepository(Database.instance);
    final now = DateTime.now();
    final startDate = DateTime(now.year, 1, 1);
    final endDate = DateTime(now.year, 12, 31, 23, 59, 59, 999);
    final stats = await repository.getDailySuccessRequestStats(
      startTimestamp: startDate.millisecondsSinceEpoch,
      endTimestamp: endDate.millisecondsSinceEpoch,
    );
    dailyTokenStats.value = stats;
  }
}
