import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;

/// 客户端错误处理器 - 处理4xx响应（无需重试）
class ClientErrorHandler implements ResponseHandlerStrategy {
  @override
  HandleResult handle(http.StreamedResponse response, EndpointEntity endpoint) {
    // 4xx错误是客户端问题，无需重试，直接返回
    LoggerUtil.instance.w(
      'Client error from endpoint ${endpoint.name}: ${response.statusCode}',
    );
    return HandleResult.clientError;
  }
}

/// 异常处理器 - 处理网络异常等
class ExceptionHandler implements ExceptionHandlerStrategy {
  @override
  HandleResult handle(dynamic error, EndpointEntity endpoint) {
    LoggerUtil.instance.e('Exception from endpoint ${endpoint.name}: $error');
    return HandleResult.exception;
  }
}

/// 异常处理器策略 - 用于处理异常情况
abstract class ExceptionHandlerStrategy {
  /// 处理异常，返回HandleResult
  HandleResult handle(dynamic error, EndpointEntity endpoint);
}

/// 响应处理结果
enum HandleResult {
  success, // 成功响应（2xx）
  clientError, // 客户端错误（4xx）
  serverError, // 服务器错误（5xx）
  exception, // 网络异常
}

/// 端点路由器 - 状态机实现
class ProxyServerRouter {
  final ProxyServerConfig _config;
  final void Function(EndpointEntity)? _onEndpointUnavailable;

  List<EndpointEntity> _endpoints = [];
  int _currentEndpointIndex = 0;
  int _currentAttempt = 0;
  RouteState _state = RouteState.selectingEndpoint;

  ProxyServerRouter({
    required ProxyServerConfig config,
    void Function(EndpointEntity)? onEndpointUnavailable,
  }) : _config = config,
       _onEndpointUnavailable = onEndpointUnavailable;

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

  /// 判断是否还有下一个端点或需要重试
  /// previousResult: 上一次的响应结果，null表示第一次调用
  bool hasNext(HandleResult? previousResult) {
    // 第一次调用
    if (previousResult == null) {
      _resetForNewRequest();
      return _endpoints.isNotEmpty;
    }

    // 根据上一次的结果决定下一步
    switch (previousResult) {
      case HandleResult.success:
      case HandleResult.clientError:
        // 成功或客户端错误，不需要继续
        return false;

      case HandleResult.serverError:
      case HandleResult.exception:
        // 服务器错误或异常，需要重试或转移
        if (_currentAttempt < _config.maxRetries) {
          // 重试当前端点
          _currentAttempt++;
          _state = RouteState.retryingEndpoint;
          LoggerUtil.instance.w(
            'Retrying endpoint ${currentEndpoint?.name} '
            '($_currentAttempt/${_config.maxRetries})',
          );
          return true;
        } else {
          // 重试用尽，转移到下一个端点
          LoggerUtil.instance.e(
            'Endpoint ${currentEndpoint?.name} exhausted retries',
          );
          _onEndpointUnavailable?.call(currentEndpoint!);
          _moveToNextEndpoint();

          if (_currentEndpointIndex < _endpoints.length) {
            _state = RouteState.failingOver;
            LoggerUtil.instance.i('Failing over to next endpoint');
            return true;
          } else {
            // 所有端点都用尽
            _state = RouteState.failed;
            return false;
          }
        }
    }
  }

  /// 设置端点列表
  void setEndpoints(List<EndpointEntity> endpoints) {
    _endpoints = endpoints.where((e) => e.enabled).toList();
    _resetForNewRequest();
  }

  /// 移动到下一个端点
  void _moveToNextEndpoint() {
    _currentEndpointIndex++;
    _currentAttempt = 0;
  }

  /// 重置路由状态
  void _resetForNewRequest() {
    _currentEndpointIndex = 0;
    _currentAttempt = 0;
    _state = RouteState.selectingEndpoint;
  }
}

/// 响应处理器策略 - 用于处理不同类型的HTTP响应
abstract class ResponseHandlerStrategy {
  /// 处理响应，返回HandleResult
  HandleResult handle(http.StreamedResponse response, EndpointEntity endpoint);
}

/// 路由状态枚举
enum RouteState {
  selectingEndpoint, // 选择端点
  retryingEndpoint, // 重试当前端点
  failingOver, // 故障转移到下一个端点
  completed, // 完成（成功）
  failed, // 失败（所有端点都用尽）
}

/// 服务器错误处理器 - 处理5xx响应（需要重试）
class ServerErrorHandler implements ResponseHandlerStrategy {
  @override
  HandleResult handle(http.StreamedResponse response, EndpointEntity endpoint) {
    LoggerUtil.instance.w(
      'Server error from endpoint ${endpoint.name}: ${response.statusCode}',
    );
    return HandleResult.serverError;
  }
}

/// 成功处理器 - 处理2xx响应
class SuccessHandler implements ResponseHandlerStrategy {
  @override
  HandleResult handle(http.StreamedResponse response, EndpointEntity endpoint) {
    LoggerUtil.instance.i(
      'Success response from endpoint ${endpoint.name}: ${response.statusCode}',
    );
    return HandleResult.success;
  }
}
