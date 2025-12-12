import 'dart:async';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;

/// 客户端错误处理器 - 处理4xx响应（无需重试）
class ClientErrorHandler implements ResponseHandlerStrategy {
  @override
  RouteResult? handle(
    dynamic responseOrError,
    EndpointEntity endpoint,
    int attempt,
    int maxRetries,
    void Function(EndpointEntity)? onEndpointUnavailable,
  ) {
    final response = responseOrError as http.StreamedResponse;
    // 4xx错误是客户端问题，无需重试，直接返回
    return RouteResult.success(response, endpoint);
  }
}

/// 异常处理器 - 处理网络异常等
class ExceptionHandler implements ResponseHandlerStrategy {
  @override
  RouteResult? handle(
    dynamic responseOrError,
    EndpointEntity endpoint,
    int attempt,
    int maxRetries,
    void Function(EndpointEntity)? onEndpointUnavailable,
  ) {
    final error = responseOrError;

    if (attempt < maxRetries) {
      LoggerUtil.instance.w(
        'Endpoint ${endpoint.name} threw exception, retrying: $error',
      );
      // 返回null表示需要重试
      return null;
    } else {
      LoggerUtil.instance.e(
        'Endpoint ${endpoint.name} exhausted retries due to exception: $error',
      );
      onEndpointUnavailable?.call(endpoint);
      return RouteResult.failed(endpoint, error: error.toString());
    }
  }
}

/// 端点路由器 - 负责端点选择、重试和故障转移
class ProxyServerRouter {
  final ProxyServerConfig _config;
  final void Function(EndpointEntity)? _onEndpointUnavailable;

  ProxyServerRouter({
    required ProxyServerConfig config,
    void Function(EndpointEntity)? onEndpointUnavailable,
  }) : _config = config,
       _onEndpointUnavailable = onEndpointUnavailable;

  /// 路由请求到端点，支持重试和故障转移
  Future<RouteResult> routeRequest(
    List<EndpointEntity> endpoints,
    Future<http.StreamedResponse> Function(EndpointEntity) requestExecutor,
  ) async {
    for (var endpoint in endpoints.where((e) => e.enabled)) {
      final routeResult = await _tryEndpoint(endpoint, requestExecutor);

      // 如果成功或遇到错误，直接返回
      if (routeResult.success || routeResult.error != null) {
        return routeResult;
      }
      // 如果失败但需要重试，继续尝试下一个端点
    }

    // 所有端点都失败
    return const RouteResult.failed(null, error: 'All endpoints failed');
  }

  /// 根据状态码获取对应的响应处理器
  ResponseHandlerStrategy _getResponseHandler(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return SuccessHandler();
    } else if (statusCode >= 400 && statusCode < 500) {
      return ClientErrorHandler();
    } else if (statusCode >= 500) {
      return ServerErrorHandler();
    } else {
      // 1xx 或其他未知状态码，按成功处理
      return SuccessHandler();
    }
  }

  Future<RouteResult> _tryEndpoint(
    EndpointEntity endpoint,
    Future<http.StreamedResponse> Function(EndpointEntity) requestExecutor,
  ) async {
    LoggerUtil.instance.i('Forwarding request to endpoint ${endpoint.name}');
    for (int attempt = 0; attempt <= _config.maxRetries; attempt++) {
      try {
        final response = await requestExecutor(endpoint);

        // 使用策略模式处理不同的响应状态
        final handler = _getResponseHandler(response.statusCode);
        final result = handler.handle(
          response,
          endpoint,
          attempt,
          _config.maxRetries,
          _onEndpointUnavailable,
        );

        if (result != null) {
          return result;
        }
        // 如果返回 null，表示需要继续重试
      } catch (e) {
        final handler = ExceptionHandler();
        final result = handler.handle(
          e,
          endpoint,
          attempt,
          _config.maxRetries,
          _onEndpointUnavailable,
        );

        if (result != null) {
          return result;
        }
        // 如果返回 null，表示需要继续重试
      }
    }

    // 理论上不会到达这里，但为了类型安全
    return const RouteResult.failed(null, error: 'Unexpected error');
  }
}

/// 响应处理器策略 - 用于处理不同类型的HTTP响应
abstract class ResponseHandlerStrategy {
  /// 处理响应，返回RouteResult（返回null表示需要重试）
  RouteResult? handle(
    dynamic responseOrError,
    EndpointEntity endpoint,
    int attempt,
    int maxRetries,
    void Function(EndpointEntity)? onEndpointUnavailable,
  );
}

/// 路由结果 - 简化版结果封装
class RouteResult {
  final bool success;
  final http.StreamedResponse? response;
  final EndpointEntity? endpoint;
  final EndpointEntity? failedEndpoint;
  final String? error;

  const RouteResult.failed(this.failedEndpoint, {this.endpoint, this.error})
    : success = false,
      response = null;

  const RouteResult.success(this.response, this.endpoint)
    : success = true,
      failedEndpoint = null,
      error = null;
}

/// 服务器错误处理器 - 处理5xx响应（需要重试）
class ServerErrorHandler implements ResponseHandlerStrategy {
  @override
  RouteResult? handle(
    dynamic responseOrError,
    EndpointEntity endpoint,
    int attempt,
    int maxRetries,
    void Function(EndpointEntity)? onEndpointUnavailable,
  ) {
    final response = responseOrError as http.StreamedResponse;

    if (attempt < maxRetries) {
      LoggerUtil.instance.w(
        'Endpoint ${endpoint.name} returned ${response.statusCode}, '
        'retrying (attempt ${attempt + 1}/${maxRetries + 1})',
      );
      // 返回null表示需要重试
      return null;
    } else {
      LoggerUtil.instance.e(
        'Endpoint ${endpoint.name} exhausted retries (max: $maxRetries)',
      );
      onEndpointUnavailable?.call(endpoint);
      return RouteResult.failed(endpoint);
    }
  }
}

/// 成功处理器 - 处理2xx响应
class SuccessHandler implements ResponseHandlerStrategy {
  @override
  RouteResult? handle(
    dynamic responseOrError,
    EndpointEntity endpoint,
    int attempt,
    int maxRetries,
    void Function(EndpointEntity)? onEndpointUnavailable,
  ) {
    final response = responseOrError as http.StreamedResponse;
    return RouteResult.success(response, endpoint);
  }
}
