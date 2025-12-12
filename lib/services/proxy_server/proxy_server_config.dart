/// 代理配置模型
class ProxyServerConfig {
  /// 监听地址（127.0.0.1 或 0.0.0.0）
  final String address;

  /// 监听端口
  final int port;

  /// 最大重试次数
  final int maxRetries;

  const ProxyServerConfig({
    this.address = '127.0.0.1',
    this.port = 9000,
    this.maxRetries = 3,
  });

  @override
  String toString() {
    return 'ProxyConfig(address: $address, port: $port, maxRetries: $maxRetries)';
  }
}
