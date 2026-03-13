/// 代理配置模型
class ProxyServerConfig {
  /// 监听地址(127.0.0.1 或 0.0.0.0)
  final String address;

  /// 监听端口
  final int port;

  /// API 超时时间(毫秒)
  final int apiTimeoutMs;

  /// 断路器失败阈值（滑动窗口内失败次数达到此值后打开断路器）
  final int circuitBreakerFailureThreshold;

  /// 断路器恢复超时（Open 状态持续时间，毫秒）
  final int circuitBreakerRecoveryTimeoutMs;

  /// 断路器滑动窗口大小（毫秒）
  final int circuitBreakerSlidingWindowMs;

  const ProxyServerConfig({
    this.address = '127.0.0.1',
    this.port = 9000,
    this.apiTimeoutMs = 10 * 60 * 1000,
    this.circuitBreakerFailureThreshold = 5,
    this.circuitBreakerRecoveryTimeoutMs = 60 * 1000,
    this.circuitBreakerSlidingWindowMs = 120 * 1000,
  });
}
