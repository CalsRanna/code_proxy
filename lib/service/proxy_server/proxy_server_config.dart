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

  /// 端点禁用时长(毫秒)
  final int disableDurationMs;

  const ProxyServerConfig({
    this.address = '127.0.0.1',
    this.port = 9000,
    this.maxRetries = 3,
    this.apiTimeoutMs = 10 * 60 * 1000, // 默认 10分钟
    this.disableDurationMs = 60 * 1000, // 默认 1分钟
  });
}
