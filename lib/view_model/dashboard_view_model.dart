import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:signals/signals.dart';

class DashboardViewModel {
  final dailyTokenStats = signal<Map<String, int>>({});
  final dailyRequests = signal<Map<String, int>>({});
  final endpointTokenUsage = signal<Map<String, int>>({});
  final modelDateTokenUsage = signal<Map<String, Map<String, int>>>({});
  final dailyCacheStats = signal<Map<String, Map<String, int>>>({});
  final dailyCost = signal<Map<String, double>>({});
  final totalCost = signal<double>(0.0);
  final cacheSavings = signal<double>(0.0);

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
      repository.getDailyCacheStats(
        startTimestamp: startDate.millisecondsSinceEpoch,
        endTimestamp: endDate.millisecondsSinceEpoch,
      ),
    ]);

    dailyRequests.value = results[0] as Map<String, int>;
    endpointTokenUsage.value = results[1] as Map<String, int>;
    modelDateTokenUsage.value = results[2] as Map<String, Map<String, int>>;
    dailyCacheStats.value = results[3] as Map<String, Map<String, int>>;

    // 加载费用数据
    await _loadCostData(repository, startDate, endDate);
  }

  Future<void> _loadCostData(
    RequestLogRepository repository,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final pricingService = ModelPricingService.instance;
    final breakdown = await repository.getDailyModelTokenBreakdown(
      startTimestamp: startDate.millisecondsSinceEpoch,
      endTimestamp: endDate.millisecondsSinceEpoch,
    );

    final Map<String, double> costs = {};
    double total = 0;
    double savings = 0;

    for (final row in breakdown) {
      final date = row['date'] as String;
      final model = row['model'] as String;
      final input = row['input'] as int;
      final output = row['output'] as int;
      final cacheCreation = row['cache_creation'] as int;
      final cacheRead = row['cache_read'] as int;

      final cost = pricingService.calculateCost(
        model: model,
        inputTokens: input,
        outputTokens: output,
        cacheCreationTokens: cacheCreation,
        cacheReadTokens: cacheRead,
      );

      costs[date] = (costs[date] ?? 0) + cost;
      total += cost;

      savings += pricingService.calculateCacheSavings(
        model: model,
        cacheReadTokens: cacheRead,
      );
    }

    dailyCost.value = costs;
    totalCost.value = total;
    cacheSavings.value = savings;
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
