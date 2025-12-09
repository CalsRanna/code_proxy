/// 代理服务器状态模型
class ProxyServerState {
  /// 是否运行中
  final bool running;

  /// 监听地址
  final String? listenAddress;

  /// 监听端口
  final int? listenPort;

  /// 启动时间戳
  final int? startedAt;

  /// 运行时间（秒）
  final int uptimeSeconds;

  /// 总请求数
  final int totalRequests;

  /// 成功请求数
  final int successRequests;

  /// 失败请求数
  final int failedRequests;

  /// 成功率（0-100）
  final double successRate;

  /// 活跃连接数
  final int activeConnections;

  /// 当前选中端点 ID
  final String? currentEndpointId;

  /// 最后请求时间戳
  final int? lastRequestAt;

  /// 最后错误信息
  final String? lastError;

  const ProxyServerState({
    this.running = false,
    this.listenAddress,
    this.listenPort,
    this.startedAt,
    this.uptimeSeconds = 0,
    this.totalRequests = 0,
    this.successRequests = 0,
    this.failedRequests = 0,
    this.successRate = 0.0,
    this.activeConnections = 0,
    this.currentEndpointId,
    this.lastRequestAt,
    this.lastError,
  });

  /// 从 JSON 反序列化
  factory ProxyServerState.fromJson(Map<String, dynamic> json) {
    return ProxyServerState(
      running: json['running'] as bool? ?? false,
      listenAddress: json['listenAddress'] as String?,
      listenPort: json['listenPort'] as int?,
      startedAt: json['startedAt'] as int?,
      uptimeSeconds: json['uptimeSeconds'] as int? ?? 0,
      totalRequests: json['totalRequests'] as int? ?? 0,
      successRequests: json['successRequests'] as int? ?? 0,
      failedRequests: json['failedRequests'] as int? ?? 0,
      successRate: (json['successRate'] as num?)?.toDouble() ?? 0.0,
      activeConnections: json['activeConnections'] as int? ?? 0,
      currentEndpointId: json['currentEndpointId'] as String?,
      lastRequestAt: json['lastRequestAt'] as int?,
      lastError: json['lastError'] as String?,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'running': running,
      'listenAddress': listenAddress,
      'listenPort': listenPort,
      'startedAt': startedAt,
      'uptimeSeconds': uptimeSeconds,
      'totalRequests': totalRequests,
      'successRequests': successRequests,
      'failedRequests': failedRequests,
      'successRate': successRate,
      'activeConnections': activeConnections,
      'currentEndpointId': currentEndpointId,
      'lastRequestAt': lastRequestAt,
      'lastError': lastError,
    };
  }

  /// 复制并更新部分字段
  ProxyServerState copyWith({
    bool? running,
    String? listenAddress,
    int? listenPort,
    int? startedAt,
    int? uptimeSeconds,
    int? totalRequests,
    int? successRequests,
    int? failedRequests,
    double? successRate,
    int? activeConnections,
    String? currentEndpointId,
    int? lastRequestAt,
    String? lastError,
  }) {
    return ProxyServerState(
      running: running ?? this.running,
      listenAddress: listenAddress ?? this.listenAddress,
      listenPort: listenPort ?? this.listenPort,
      startedAt: startedAt ?? this.startedAt,
      uptimeSeconds: uptimeSeconds ?? this.uptimeSeconds,
      totalRequests: totalRequests ?? this.totalRequests,
      successRequests: successRequests ?? this.successRequests,
      failedRequests: failedRequests ?? this.failedRequests,
      successRate: successRate ?? this.successRate,
      activeConnections: activeConnections ?? this.activeConnections,
      currentEndpointId: currentEndpointId ?? this.currentEndpointId,
      lastRequestAt: lastRequestAt ?? this.lastRequestAt,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  String toString() {
    return 'ProxyServerState(running: $running, totalRequests: $totalRequests, successRate: ${successRate.toStringAsFixed(1)}%)';
  }
}
