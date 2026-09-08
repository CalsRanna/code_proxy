/// 代理配置模型
class ProxyServerConfig {
  /// 监听地址(127.0.0.1 或 0.0.0.0)
  final String address;

  /// 监听端口
  final int port;

  /// 每次上游尝试的连接、响应头等待及响应体空闲超时，单位为毫秒。
  ///
  /// 各阶段分别计时，不限制整条重试链路或持续有数据的 SSE 的总时长。
  final int apiTimeoutMs;

  /// Whether upstream 4xx responses join the normal retry and failover policy.
  ///
  /// Defaults to false. Enabling this does not change timeouts, logging, or
  /// cancellation behavior, and does not replay interrupted SSE responses.
  final bool retryAllErrorsEnabled;

  /// 同一端点共享的连续失败阈值，达到后打开断路器。
  ///
  /// 跨请求、跨模型累计，不是每个请求独立的重试次数。
  final int circuitBreakerFailureThreshold;

  /// 断路器打开后允许半开探测前的等待时间，单位为毫秒。
  ///
  /// 到期后允许请求探测，成功则恢复，失败则重新打开断路器。
  /// 此值不是普通重试的退避间隔。
  final int circuitBreakerRecoveryTimeoutMs;

  const ProxyServerConfig({
    this.address = '127.0.0.1',
    this.port = 9000,
    this.apiTimeoutMs = 10 * 60 * 1000,
    this.retryAllErrorsEnabled = false,
    this.circuitBreakerFailureThreshold = 5,
    this.circuitBreakerRecoveryTimeoutMs = 60 * 1000,
  });
}
