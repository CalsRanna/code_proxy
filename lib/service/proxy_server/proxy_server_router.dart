import 'dart:async';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker_registry.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/util/logger_util.dart';

/// 端点路由器 - 统一通过断路器管理失败重试与故障转移
class ProxyServerRouter {
  final ProxyServerConfig _config;
  final ProxyServerCircuitBreakerRegistry _circuitBreakerRegistry;
  final void Function(EndpointEntity)? _onEndpointUnavailable;
  final void Function(EndpointEntity)? _onEndpointRestored;

  /// 所有启用的端点（由外部通过 setEndpoints 更新）
  List<EndpointEntity> _allEndpoints = [];

  /// 当前请求轮次中可用的端点（从 _allEndpoints 按断路器状态过滤）
  List<EndpointEntity> _endpoints = [];
  int _currentEndpointIndex = 0;
  int _currentAttempt = 0;

  ProxyServerRouter({
    required ProxyServerConfig config,
    required ProxyServerCircuitBreakerRegistry circuitBreakerRegistry,
    void Function(EndpointEntity)? onEndpointUnavailable,
    void Function(EndpointEntity)? onEndpointRestored,
  }) : _config = config,
       _circuitBreakerRegistry = circuitBreakerRegistry,
       _onEndpointUnavailable = onEndpointUnavailable,
       _onEndpointRestored = onEndpointRestored;

  /// 获取当前尝试次数
  int get currentAttempt => _currentAttempt;

  /// 获取当前端点
  EndpointEntity? get currentEndpoint {
    if (_currentEndpointIndex >= 0 &&
        _currentEndpointIndex < _endpoints.length) {
      return _endpoints[_currentEndpointIndex];
    }
    return null;
  }

  /// 获取端点列表（供调试使用）
  List<EndpointEntity> get endpoints => List.unmodifiable(_endpoints);

  /// 计算重试延迟时间（支持指数退避）
  /// attempt: 当前尝试次数（从1开始）
  int _calculateRetryDelay(int attempt) {
    if (attempt <= 1) return 0;
    var base = 1000;
    var max = 10 * 1000;
    // 指数退避：base * 2^(attempt-2)
    // attempt=2: 第一次重试，使用 base
    // attempt=3: 第二次重试，使用 base * 2
    // attempt=4: 第三次重试，使用 base * 4
    final delay = base * (1 << (attempt - 2));
    return delay.clamp(0, max);
  }

  /// 判断是否还有下一个端点或需要重试。
  ///
  /// [previousSucceeded] 表示上一次请求是否成功：
  /// - null: 首次进入，为当前请求选择第一个可用端点
  /// - true: 上一次成功，结束当前请求轮次
  /// - false: 上一次失败，统一按断路器机制决定重试或故障转移
  Future<bool> hasNext(bool? previousSucceeded) async {
    if (previousSucceeded == null) {
      _resetForNewRequest();
      return _endpoints.isNotEmpty;
    }

    if (previousSucceeded) {
      final endpoint = currentEndpoint;
      if (endpoint != null) {
        final breaker = _circuitBreakerRegistry.getBreaker(endpoint.id);
        final wasHalfOpen =
            breaker.state == ProxyServerCircuitBreakerState.halfOpen;
        breaker.recordSuccess();
        if (wasHalfOpen) {
          _onEndpointRestored?.call(endpoint);
        }
      }
      return false;
    }

    final endpoint = currentEndpoint;
    if (endpoint == null) {
      return false;
    }

    // 失败：统一按断路器机制处理，不再按具体状态码分流
    final breaker = _circuitBreakerRegistry.getBreaker(endpoint.id);
    breaker.recordFailure();
    _currentAttempt++;

    if (breaker.state == ProxyServerCircuitBreakerState.open) {
      LoggerUtil.instance.w(
        'Endpoint ${endpoint.name} circuit breaker opened '
        'after ${_currentAttempt - 1} failed attempts',
      );
      _onEndpointUnavailable?.call(endpoint);
      _moveToNextEndpoint();

      if (_currentEndpointIndex < _endpoints.length) {
        LoggerUtil.instance.i('Failing over to next endpoint');
        return true;
      }
      return false;
    }

    final delayMs = _calculateRetryDelay(_currentAttempt);
    LoggerUtil.instance.w(
      'Retrying endpoint ${endpoint.name} '
      '(attempt $_currentAttempt/${_config.circuitBreakerFailureThreshold})',
    );
    if (delayMs > 0) {
      LoggerUtil.instance.d('Waiting ${delayMs}ms before retry');
      await Future.delayed(Duration(milliseconds: delayMs));
    }
    return true;
  }

  /// 设置端点列表（由外部在端点变更时调用）
  void setEndpoints(List<EndpointEntity> endpoints) {
    _allEndpoints = endpoints.where((e) => e.enabled).toList();
    _resetForNewRequest();
  }

  /// 移动到下一个端点
  void _moveToNextEndpoint() {
    _currentEndpointIndex++;
    _currentAttempt = 1;

    // 跳过断路器 open 的端点（使用无副作用的 isAvailable）
    while (_currentEndpointIndex < _endpoints.length) {
      final nextEndpoint = _endpoints[_currentEndpointIndex];
      final breaker = _circuitBreakerRegistry.getBreaker(nextEndpoint.id);
      if (breaker.isAvailable) {
        break;
      }
      _currentEndpointIndex++;
    }
  }

  /// 重置路由状态（使用缓存的端点列表，按断路器状态过滤）
  void _resetForNewRequest() {
    _currentEndpointIndex = 0;
    _currentAttempt = 1;

    _endpoints = [];
    for (final e in _allEndpoints) {
      final breaker = _circuitBreakerRegistry.getBreaker(e.id);
      if (breaker.isAvailable) {
        _endpoints.add(e);
      }
    }
  }
}
