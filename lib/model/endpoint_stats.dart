/// 端点统计模型
class EndpointStats {
  /// 端点 ID
  final String endpointId;

  /// 总请求数
  final int totalRequests;

  /// 成功请求数
  final int successRequests;

  /// 失败请求数
  final int failedRequests;

  /// 成功率（0-100）
  final double successRate;

  /// 平均响应时间（毫秒）
  final double avgResponseTime;

  /// 最小响应时间（毫秒）
  final int minResponseTime;

  /// 最大响应时间（毫秒）
  final int maxResponseTime;

  /// 最近响应时间列表（用于计算移动平均）
  final List<int> recentResponseTimes;

  /// 最后请求时间戳
  final int? lastRequestAt;

  /// 最后成功时间戳
  final int? lastSuccessAt;

  /// 最后失败时间戳
  final int? lastFailureAt;

  const EndpointStats({
    required this.endpointId,
    this.totalRequests = 0,
    this.successRequests = 0,
    this.failedRequests = 0,
    this.successRate = 0.0,
    this.avgResponseTime = 0.0,
    this.minResponseTime = 0,
    this.maxResponseTime = 0,
    this.recentResponseTimes = const [],
    this.lastRequestAt,
    this.lastSuccessAt,
    this.lastFailureAt,
  });

  /// 从 JSON 反序列化
  factory EndpointStats.fromJson(Map<String, dynamic> json) {
    return EndpointStats(
      endpointId: json['endpointId'] as String,
      totalRequests: json['totalRequests'] as int? ?? 0,
      successRequests: json['successRequests'] as int? ?? 0,
      failedRequests: json['failedRequests'] as int? ?? 0,
      successRate: (json['successRate'] as num?)?.toDouble() ?? 0.0,
      avgResponseTime: (json['avgResponseTime'] as num?)?.toDouble() ?? 0.0,
      minResponseTime: json['minResponseTime'] as int? ?? 0,
      maxResponseTime: json['maxResponseTime'] as int? ?? 0,
      recentResponseTimes: (json['recentResponseTimes'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [],
      lastRequestAt: json['lastRequestAt'] as int?,
      lastSuccessAt: json['lastSuccessAt'] as int?,
      lastFailureAt: json['lastFailureAt'] as int?,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'endpointId': endpointId,
      'totalRequests': totalRequests,
      'successRequests': successRequests,
      'failedRequests': failedRequests,
      'successRate': successRate,
      'avgResponseTime': avgResponseTime,
      'minResponseTime': minResponseTime,
      'maxResponseTime': maxResponseTime,
      'recentResponseTimes': recentResponseTimes,
      'lastRequestAt': lastRequestAt,
      'lastSuccessAt': lastSuccessAt,
      'lastFailureAt': lastFailureAt,
    };
  }

  /// 更新统计信息（记录新的请求）
  EndpointStats updateWithRequest({
    required bool success,
    required int responseTime,
    required int maxWindowSize,
  }) {
    final newTotal = totalRequests + 1;
    final newSuccess = success ? successRequests + 1 : successRequests;
    final newFailed = success ? failedRequests : failedRequests + 1;
    final newSuccessRate = (newSuccess / newTotal) * 100;

    // 更新响应时间列表（保持窗口大小）
    final updatedTimes = List<int>.from(recentResponseTimes)..add(responseTime);
    if (updatedTimes.length > maxWindowSize) {
      updatedTimes.removeAt(0);
    }

    // 计算新的平均响应时间
    final newAvg = updatedTimes.reduce((a, b) => a + b) / updatedTimes.length;
    final newMin = minResponseTime == 0
        ? responseTime
        : responseTime < minResponseTime
            ? responseTime
            : minResponseTime;
    final newMax =
        responseTime > maxResponseTime ? responseTime : maxResponseTime;

    final now = DateTime.now().millisecondsSinceEpoch;

    return EndpointStats(
      endpointId: endpointId,
      totalRequests: newTotal,
      successRequests: newSuccess,
      failedRequests: newFailed,
      successRate: newSuccessRate,
      avgResponseTime: newAvg,
      minResponseTime: newMin,
      maxResponseTime: newMax,
      recentResponseTimes: updatedTimes,
      lastRequestAt: now,
      lastSuccessAt: success ? now : lastSuccessAt,
      lastFailureAt: success ? lastFailureAt : now,
    );
  }

  @override
  String toString() {
    return 'EndpointStats(endpointId: $endpointId, totalRequests: $totalRequests, successRate: ${successRate.toStringAsFixed(1)}%)';
  }
}
