/// 代理配置模型
class ProxyServerConfig {
  /// 监听地址（127.0.0.1 或 0.0.0.0）
  final String address;

  /// 监听端口
  final int port;

  /// 最大重试次数
  final int maxRetries;

  /// 默认临时禁用时长（毫秒）
  final int defaultTempDisableDurationMs;

  /// 重试等待时间（毫秒）
  final int retryDelayMs;

  /// 是否启用重试等待
  final bool enableRetryDelay;

  const ProxyServerConfig({
    this.address = '127.0.0.1',
    this.port = 9000,
    this.maxRetries = 3,
    this.defaultTempDisableDurationMs = 10 * 60 * 1000, // 10分钟
    this.retryDelayMs = 1000, // 1秒
    this.enableRetryDelay = true,
  });

  @override
  String toString() {
    return 'ProxyConfig(address: $address, port: $port, maxRetries: $maxRetries, '
           'defaultTempDisableDurationMs: $defaultTempDisableDurationMs, '
           'retryDelayMs: $retryDelayMs, enableRetryDelay: $enableRetryDelay)';
  }
}
