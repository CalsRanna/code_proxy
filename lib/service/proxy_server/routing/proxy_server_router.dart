import 'dart:async';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_circuit_breaker.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_circuit_breaker_registry.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_error_classifier.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_retry_delay.dart';
import 'package:code_proxy/service/proxy_server/transport/proxy_server_request_cancellation.dart';
import 'package:code_proxy/util/logger_util.dart';

/// 通过共享断路器管理端点选择、失败重试与故障转移的路由器。
///
/// 调用方负责判定错误是否参与重试；路由器不按 HTTP 状态码分流。
class ProxyServerRouter {
  final ProxyServerConfig _config;
  final ProxyServerCircuitBreakerRegistry _circuitBreakerRegistry;
  final void Function(EndpointEntity)? _onEndpointUnavailable;
  final void Function(EndpointEntity)? _onEndpointRestored;

  /// 所有启用的端点（由外部通过 setEndpoints 更新）
  List<EndpointEntity> _allEndpoints = [];

  ProxyServerRouter({
    required ProxyServerConfig config,
    required ProxyServerCircuitBreakerRegistry circuitBreakerRegistry,
    void Function(EndpointEntity)? onEndpointUnavailable,
    void Function(EndpointEntity)? onEndpointRestored,
  }) : _config = config,
       _circuitBreakerRegistry = circuitBreakerRegistry,
       _onEndpointUnavailable = onEndpointUnavailable,
       _onEndpointRestored = onEndpointRestored;

  /// 是否有至少一个端点可用（断路器未打开）。
  bool get hasAvailableEndpoints => _buildAvailableEndpoints().isNotEmpty;

  bool get hasEnabledEndpoints => _allEndpoints.isNotEmpty;

  /// 为单个代理请求创建独立的路由会话。
  ///
  /// 当前端点和退避计数归属单个请求，断路器及失败计数仍按端点共享。
  ProxyServerRouteSession startRequest() {
    return ProxyServerRouteSession._(
      router: this,
      endpoints: _buildAvailableEndpoints(),
    );
  }

  /// 设置端点列表（由外部在端点变更时调用）
  void setEndpoints(List<EndpointEntity> endpoints) {
    _allEndpoints = endpoints.where((e) => e.enabled).toList();
  }

  List<EndpointEntity> _buildAvailableEndpoints() {
    final endpoints = <EndpointEntity>[];
    for (final endpoint in _allEndpoints) {
      final breaker = _circuitBreakerRegistry.getBreaker(endpoint.id);
      if (breaker.isAvailable) {
        endpoints.add(endpoint);
      }
    }
    return endpoints;
  }

  void _recordSuccess(EndpointEntity endpoint) {
    final breaker = _circuitBreakerRegistry.getBreaker(endpoint.id);
    final wasHalfOpen =
        breaker.state == ProxyServerCircuitBreakerState.halfOpen;
    breaker.recordSuccess();
    if (wasHalfOpen) {
      _onEndpointRestored?.call(endpoint);
    }
  }

  /// 记录一次失败（供流式响应中途中断等主循环之外的异步失败路径使用）。
  ///
  /// 与路由会话共享同一个端点断路器。
  void recordFailure(EndpointEntity endpoint) {
    final breaker = _circuitBreakerRegistry.getBreaker(endpoint.id);
    breaker.recordFailure();
    if (breaker.state == ProxyServerCircuitBreakerState.open) {
      LoggerUtil.instance.w(
        'Endpoint ${endpoint.name} circuit breaker opened (stream failure)',
      );
      _onEndpointUnavailable?.call(endpoint);
    }
  }
}

/// 单个请求的路由会话。
///
/// 每个请求独立维护 [currentEndpoint] 和退避计数，切换端点时重置退避。
/// 同一端点的熔断计数跨会话共享，因此某个请求只尝试少数几次时，
/// 端点就可能因其他并发请求的失败而熔断。
class ProxyServerRouteSession {
  final ProxyServerRouter _router;
  final List<EndpointEntity> _endpoints;

  int _currentEndpointIndex = 0;
  // 当前端点的普通尝试序号，从 1 开始；透明重试不递增。
  int _currentAttempt = 1;

  /// 每端点已用的透明重试次数(endpointId -> count)。
  /// 归属端点、本请求内一次性消耗,断路器打回同端点时不重置 → 防止重试放大。
  final Map<String, int> _transientRetriesUsed = {};
  static const int _maxTransientRetries = 2;

  ProxyServerRouteSession._({
    required ProxyServerRouter router,
    required List<EndpointEntity> endpoints,
  }) : _router = router,
       _endpoints = endpoints;

  EndpointEntity? get currentEndpoint {
    if (_currentEndpointIndex < _endpoints.length) {
      return _endpoints[_currentEndpointIndex];
    }
    return null;
  }

  /// 当前端点是否可对该错误做透明重试。
  ///
  /// 三个条件全部满足才允许:
  /// 1. 错误是 header 未达的瞬时传输错误;
  /// 2. 该端点透明重试预算未耗尽;
  /// 3. 该端点断路器仍为 closed —— 若已被其他并发请求打到 open,或处于
  ///    halfOpen 探测期,则不透明重试:并发信号比单请求的乐观假设更可信,
  ///    且 halfOpen 探测必须如实反映成败,不应被透明重试掩盖。
  bool shouldTransientRetry(EndpointEntity endpoint, Object error) {
    if (!ProxyServerErrorClassifier.isHeaderNotReceived(error)) return false;
    final used = _transientRetriesUsed[endpoint.id] ?? 0;
    if (used >= _maxTransientRetries) return false;
    final breaker = _router._circuitBreakerRegistry.getBreaker(endpoint.id);
    return breaker.evaluateState() == ProxyServerCircuitBreakerState.closed;
  }

  /// 记录一次透明重试消耗。
  void recordTransientRetry(EndpointEntity endpoint) {
    _transientRetriesUsed[endpoint.id] =
        (_transientRetriesUsed[endpoint.id] ?? 0) + 1;
  }

  /// 读取本请求在 [endpoint] 已用的透明重试次数，用于运行日志。
  int transientRetriesUsedFor(EndpointEntity endpoint) =>
      _transientRetriesUsed[endpoint.id] ?? 0;

  /// 显式记录当前端点成功，不推进会话。
  void recordSuccess() {
    _router._recordSuccess(currentEndpoint!);
  }

  /// 显式记录一次普通失败；透明重试和客户端取消不调用此方法。
  void recordFailure() {
    final endpoint = currentEndpoint!;
    final breaker = _router._circuitBreakerRegistry.getBreaker(endpoint.id);
    breaker.recordFailure();
    _currentAttempt++;
    if (breaker.state == ProxyServerCircuitBreakerState.open) {
      LoggerUtil.instance.w(
        'Endpoint ${endpoint.name} circuit breaker opened '
        'after ${_currentAttempt - 1} failed attempts',
      );
      _router._onEndpointUnavailable?.call(endpoint);
    }
  }

  /// 在已记录的普通失败后，等待重试或切换到备用端点。
  ///
  /// 仅重试当前端点时采用全抖动退避及 [retryAfter]；此方法不记录成败。
  Future<bool> advanceAfterAttempt({
    ProxyServerRequestCancellation? cancellation,
    String? retryAfter,
  }) async {
    cancellation?.throwIfCancelled();
    final endpoint = currentEndpoint;
    if (endpoint == null) return false;
    final breaker = _router._circuitBreakerRegistry.getBreaker(endpoint.id);

    if (breaker.state == ProxyServerCircuitBreakerState.open) {
      _moveToNextEndpoint();

      if (_currentEndpointIndex < _endpoints.length) {
        LoggerUtil.instance.i('Failing over to next endpoint');
        return true;
      }
      return false;
    }

    final delayMs = calculateProxyRetryDelayMs(
      _currentAttempt,
      retryAfter: retryAfter,
    );
    LoggerUtil.instance.w(
      'Retrying endpoint ${endpoint.name} '
      '(attempt $_currentAttempt/${_router._config.circuitBreakerFailureThreshold})',
    );
    if (delayMs > 0) {
      LoggerUtil.instance.d('Waiting ${delayMs}ms before retry');
      final delay = Duration(milliseconds: delayMs);
      if (cancellation == null) {
        await Future.delayed(delay);
      } else {
        await cancellation.wait(delay);
      }
    }
    // 已知并发边界：等待后尚未复查断路器；其他请求在等待期间打开它时，
    // 本次已排队的重试仍会发出。失败记录数因此可能超过共享熔断阈值。
    return true;
  }

  void _moveToNextEndpoint() {
    _currentEndpointIndex++;
    _currentAttempt = 1;

    // 跳过当前已处于 open 的端点。这里重新读取断路器状态，避免会话快照中的
    // 端点因为其他并发请求刚被打开后仍被继续选中。
    while (_currentEndpointIndex < _endpoints.length) {
      final nextEndpoint = _endpoints[_currentEndpointIndex];
      final breaker = _router._circuitBreakerRegistry.getBreaker(
        nextEndpoint.id,
      );
      if (breaker.isAvailable) {
        break;
      }
      _currentEndpointIndex++;
    }
  }
}
