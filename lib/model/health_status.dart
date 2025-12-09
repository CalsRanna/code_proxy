/// 健康状态枚举
enum HealthState {
  healthy,
  unhealthy,
  unknown,
}

/// 健康状态模型
class HealthStatus {
  /// 端点 ID
  final String endpointId;

  /// 健康状态
  final HealthState state;

  /// 连续失败次数
  final int consecutiveFailures;

  /// 最后检查时间戳
  final int? lastCheckedAt;

  /// 最后成功时间戳
  final int? lastSuccessAt;

  /// 最后失败时间戳
  final int? lastFailureAt;

  /// 最后错误信息
  final String? lastError;

  /// 自动恢复时间戳（毫秒）- 不健康状态将在此时间后自动恢复
  final int? autoRecoverAt;

  const HealthStatus({
    required this.endpointId,
    this.state = HealthState.unknown,
    this.consecutiveFailures = 0,
    this.lastCheckedAt,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastError,
    this.autoRecoverAt,
  });

  /// 从 JSON 反序列化
  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      endpointId: json['endpointId'] as String,
      state: _healthStateFromString(json['state'] as String?),
      consecutiveFailures: json['consecutiveFailures'] as int? ?? 0,
      lastCheckedAt: json['lastCheckedAt'] as int?,
      lastSuccessAt: json['lastSuccessAt'] as int?,
      lastFailureAt: json['lastFailureAt'] as int?,
      lastError: json['lastError'] as String?,
      autoRecoverAt: json['autoRecoverAt'] as int?,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'endpointId': endpointId,
      'state': state.name,
      'consecutiveFailures': consecutiveFailures,
      'lastCheckedAt': lastCheckedAt,
      'lastSuccessAt': lastSuccessAt,
      'lastFailureAt': lastFailureAt,
      'lastError': lastError,
      'autoRecoverAt': autoRecoverAt,
    };
  }

  /// 是否健康
  bool get isHealthy => state == HealthState.healthy;

  /// 记录成功
  HealthStatus recordSuccess() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return HealthStatus(
      endpointId: endpointId,
      state: HealthState.healthy,
      consecutiveFailures: 0,
      lastCheckedAt: now,
      lastSuccessAt: now,
      lastFailureAt: lastFailureAt,
      lastError: null,
      autoRecoverAt: null, // 清除自动恢复时间
    );
  }

  /// 记录失败
  /// 任何失败立即标记为不健康，并设置10分钟后自动恢复
  HealthStatus recordFailure(String error, int threshold) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final newFailures = consecutiveFailures + 1;

    // 立即标记为不健康（忽略阈值）
    const newState = HealthState.unhealthy;

    // 设置10分钟后自动恢复
    final recoverAt = now + (10 * 60 * 1000); // 10分钟 = 600000毫秒

    return HealthStatus(
      endpointId: endpointId,
      state: newState,
      consecutiveFailures: newFailures,
      lastCheckedAt: now,
      lastSuccessAt: lastSuccessAt,
      lastFailureAt: now,
      lastError: error,
      autoRecoverAt: recoverAt,
    );
  }

  @override
  String toString() {
    return 'HealthStatus(endpointId: $endpointId, state: ${state.name}, consecutiveFailures: $consecutiveFailures)';
  }

  /// 将字符串转换为 HealthState
  static HealthState _healthStateFromString(String? value) {
    switch (value) {
      case 'healthy':
        return HealthState.healthy;
      case 'unhealthy':
        return HealthState.unhealthy;
      default:
        return HealthState.unknown;
    }
  }
}
