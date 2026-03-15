import 'dart:async';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker_registry.dart';
import 'package:code_proxy/util/logger_util.dart';

/// 响应处理结果
enum HandleResult {
  success, // 成功响应（2xx）
  clientError, // 客户端错误（4xx，不包括429）
  rateLimited, // 速率限制或余额不足（429）
  serverError, // 服务器错误（5xx）
  exception, // 网络异常
}

/// 端点路由器 - 状态机实现
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
  RouteState _state = RouteState.selectingEndpoint;

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

  /// 获取当前状态
  RouteState get state => _state;

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

  /// 判断是否还有下一个端点或需要重试
  /// previousResult: 上一次的响应结果，null表示第一次调用
  /// retryAfterMs: 429 响应中 Retry-After 解析出的等待时间（毫秒）
  Future<bool> hasNext(
    HandleResult? previousResult, {
    int? retryAfterMs,
  }) async {
    // 第一次调用
    if (previousResult == null) {
      _resetForNewRequest();
      return _endpoints.isNotEmpty;
    }

    // 根据上一次的结果决定下一步
    switch (previousResult) {
      case HandleResult.success:
        // 成功：记录断路器成功，清空失败计数
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

      case HandleResult.clientError:
        // 客户端错误，不需要继续
        return false;

      case HandleResult.rateLimited:
        // 429 速率限制/余额不足 → 强制打开断路器并故障转移
        final endpoint = currentEndpoint;
        if (endpoint != null) {
          LoggerUtil.instance.w(
            'Endpoint ${endpoint.name} returned 429, circuit breaker opened'
            '${retryAfterMs != null ? ' (retry after ${retryAfterMs}ms)' : ''}',
          );
          final breaker = _circuitBreakerRegistry.getBreaker(endpoint.id);
          breaker.forceOpen(customRecoveryTimeoutMs: retryAfterMs);
          _onEndpointUnavailable?.call(endpoint);
        }

        _moveToNextEndpoint();

        if (_currentEndpointIndex < _endpoints.length) {
          _state = RouteState.failingOver;
          LoggerUtil.instance.i('Failing over to next endpoint due to 429');
          return true;
        } else {
          // 所有端点都用尽
          _state = RouteState.failed;
          return false;
        }

      case HandleResult.serverError:
      case HandleResult.exception:
        final endpoint = currentEndpoint;
        if (endpoint == null) {
          _state = RouteState.failed;
          return false;
        }

        // 记录失败，由断路器判断端点是否仍可用
        final breaker = _circuitBreakerRegistry.getBreaker(endpoint.id);
        breaker.recordFailure();
        _currentAttempt++;

        if (breaker.state == ProxyServerCircuitBreakerState.open) {
          // 断路器打开，禁用端点并故障转移
          LoggerUtil.instance.w(
            'Endpoint ${endpoint.name} circuit breaker opened '
            'after $_currentAttempt attempts',
          );
          _onEndpointUnavailable?.call(endpoint);
          _moveToNextEndpoint();

          if (_currentEndpointIndex < _endpoints.length) {
            _state = RouteState.failingOver;
            LoggerUtil.instance.i('Failing over to next endpoint');
            return true;
          } else {
            _state = RouteState.failed;
            return false;
          }
        } else {
          // 断路器仍然关闭，指数退避后重试同一端点
          _state = RouteState.retryingEndpoint;
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
    }
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
    _state = RouteState.selectingEndpoint;

    // 从缓存的端点列表中按断路器状态过滤（使用无副作用的 isAvailable）
    _endpoints = [];
    for (final e in _allEndpoints) {
      final breaker = _circuitBreakerRegistry.getBreaker(e.id);
      if (breaker.isAvailable) {
        _endpoints.add(e);
      }
    }
  }
}

/// 路由状态枚举
enum RouteState {
  selectingEndpoint, // 选择端点
  retryingEndpoint, // 重试当前端点
  failingOver, // 故障转移到下一个端点
  failed, // 失败（所有端点都用尽）
}
