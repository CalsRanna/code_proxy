/// 代理配置模型
class ProxyServerConfig {
  /// 监听地址(127.0.0.1 或 0.0.0.0)
  final String address;

  /// 监听端口
  final int port;

  /// 最大重试次数
  final int maxRetries;

  /// API 超时时间(毫秒)
  final int apiTimeoutMs;

  /// 默认临时禁用时长(毫秒)
  final int defaultTempDisableDurationMs;

  /// 指数退避基数(毫秒)
  final int exponentialBackoffBaseMs;

  /// 指数退避最大延迟(毫秒)
  final int exponentialBackoffMaxMs;

  const ProxyServerConfig({
    this.address = '127.0.0.1',
    this.port = 9000,
    this.maxRetries = 3,
    this.apiTimeoutMs = 600000, // 默认 10分钟
    this.defaultTempDisableDurationMs = 10 * 60 * 1000, // 10分钟
    this.exponentialBackoffBaseMs = 1000, // 1秒
    this.exponentialBackoffMaxMs = 10000, // 10秒
  });

  @override
  String toString() {
    return 'ProxyConfig(address: $address, port: $port, maxRetries: $maxRetries, '
        'apiTimeoutMs: $apiTimeoutMs, '
        'defaultTempDisableDurationMs: $defaultTempDisableDurationMs, ';
  }
}
