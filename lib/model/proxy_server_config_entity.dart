/// 代理配置模型
class ProxyServerConfigEntity {
  /// 监听地址（127.0.0.1 或 0.0.0.0）
  final String address;

  /// 监听端口
  final int port;

  /// 最大重试次数
  final int maxRetries;

  /// 请求超时（秒）
  final int requestTimeout;

  /// 健康检查间隔（秒）
  final int healthCheckInterval;

  /// 健康检查超时（秒）
  final int healthCheckTimeout;

  /// 健康检查路径
  final String healthCheckPath;

  /// 连续失败阈值（标记为不健康）
  final int consecutiveFailureThreshold;

  /// 是否启用日志记录
  final bool enableLogging;

  /// 日志保留条数
  final int maxLogEntries;

  /// 响应时间统计窗口大小
  final int responseTimeWindowSize;

  const ProxyServerConfigEntity({
    this.address = '127.0.0.1',
    this.port = 7890,
    this.maxRetries = 3,
    this.requestTimeout = 300,
    this.healthCheckInterval = 30,
    this.healthCheckTimeout = 10,
    this.healthCheckPath = '/health',
    this.consecutiveFailureThreshold = 3,
    this.enableLogging = true,
    this.maxLogEntries = 1000,
    this.responseTimeWindowSize = 10,
  });

  /// 从 JSON 反序列化
  factory ProxyServerConfigEntity.fromJson(Map<String, dynamic> json) {
    return ProxyServerConfigEntity(
      address: json['listenAddress'] as String? ?? '127.0.0.1',
      port: json['listenPort'] as int? ?? 7890,
      maxRetries: json['maxRetries'] as int? ?? 3,
      requestTimeout: json['requestTimeout'] as int? ?? 300,
      healthCheckInterval: json['healthCheckInterval'] as int? ?? 30,
      healthCheckTimeout: json['healthCheckTimeout'] as int? ?? 10,
      healthCheckPath: json['healthCheckPath'] as String? ?? '/health',
      consecutiveFailureThreshold:
          json['consecutiveFailureThreshold'] as int? ?? 3,
      enableLogging: json['enableLogging'] as bool? ?? true,
      maxLogEntries: json['maxLogEntries'] as int? ?? 1000,
      responseTimeWindowSize: json['responseTimeWindowSize'] as int? ?? 10,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'listenAddress': address,
      'listenPort': port,
      'maxRetries': maxRetries,
      'requestTimeout': requestTimeout,
      'healthCheckInterval': healthCheckInterval,
      'healthCheckTimeout': healthCheckTimeout,
      'healthCheckPath': healthCheckPath,
      'consecutiveFailureThreshold': consecutiveFailureThreshold,
      'enableLogging': enableLogging,
      'maxLogEntries': maxLogEntries,
      'responseTimeWindowSize': responseTimeWindowSize,
    };
  }

  /// 复制并更新部分字段
  ProxyServerConfigEntity copyWith({
    String? listenAddress,
    int? listenPort,
    int? maxRetries,
    int? requestTimeout,
    int? healthCheckInterval,
    int? healthCheckTimeout,
    String? healthCheckPath,
    int? consecutiveFailureThreshold,
    bool? enableLogging,
    int? maxLogEntries,
    int? responseTimeWindowSize,
  }) {
    return ProxyServerConfigEntity(
      address: listenAddress ?? address,
      port: listenPort ?? port,
      maxRetries: maxRetries ?? this.maxRetries,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      healthCheckInterval: healthCheckInterval ?? this.healthCheckInterval,
      healthCheckTimeout: healthCheckTimeout ?? this.healthCheckTimeout,
      healthCheckPath: healthCheckPath ?? this.healthCheckPath,
      consecutiveFailureThreshold:
          consecutiveFailureThreshold ?? this.consecutiveFailureThreshold,
      enableLogging: enableLogging ?? this.enableLogging,
      maxLogEntries: maxLogEntries ?? this.maxLogEntries,
      responseTimeWindowSize:
          responseTimeWindowSize ?? this.responseTimeWindowSize,
    );
  }

  @override
  String toString() {
    return 'ProxyConfig(listenAddress: $address, listenPort: $port)';
  }
}
