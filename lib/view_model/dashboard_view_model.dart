import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:signals/signals.dart';

class DashboardViewModel {
  final dailyTokenStats = signal<Map<String, int>>({});
  final dailyRequests = signal<Map<String, int>>({});
  final endpointTokenUsage = signal<Map<String, int>>({});
  final modelDateTokenUsage = signal<Map<String, Map<String, int>>>({});

  Future<void> initSignals() async {
    _loadHeatmapData();
    _loadChartData();
  }

  Future<void> _loadChartData() async {
    final repository = RequestLogRepository(Database.instance);
    final endDate = DateTime.now();
    final startDate = endDate.subtract(const Duration(days: 7));

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
    modelDateTokenUsage.value = results[2] as Map<String, Map<String, int>>;
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
