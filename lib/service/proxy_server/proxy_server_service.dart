import 'dart:async';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request_handler.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response_handler.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_router.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker_registry.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

class ProxyServerService {
  final ProxyServerConfig config;

  final void Function(EndpointEntity)? onEndpointUnavailable;
  final void Function(EndpointEntity)? onEndpointRestored;
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  onRequestCompleted;

  late final ProxyServerRouter _router;
  late final ProxyServerRequestHandler _requestHandler;
  late final ProxyServerResponseHandler _responseHandler;
  late final ProxyServerCircuitBreakerRegistry _circuitBreakerRegistry;
  HttpServer? _server;

  ProxyServerService({
    required this.config,
    this.onRequestCompleted,
    this.onEndpointUnavailable,
    this.onEndpointRestored,
  }) {
    _circuitBreakerRegistry = ProxyServerCircuitBreakerRegistry(
      failureThreshold: config.circuitBreakerFailureThreshold,
      recoveryTimeoutMs: config.circuitBreakerRecoveryTimeoutMs,
      slidingWindowMs: config.circuitBreakerSlidingWindowMs,
    );
    _router = ProxyServerRouter(
      config: config,
      circuitBreakerRegistry: _circuitBreakerRegistry,
      onEndpointUnavailable: onEndpointUnavailable,
      onEndpointRestored: onEndpointRestored,
    );
    _requestHandler = ProxyServerRequestHandler(config);
    _responseHandler = ProxyServerResponseHandler(
      onRequestCompleted: onRequestCompleted,
    );
  }

  set endpoints(List<EndpointEntity> endpoints) {
    _router.setEndpoints(endpoints);
  }

  Future<void> start() async {
    if (_server != null) {
      throw StateError('Server is already running');
    }

    _server = await shelf_io.serve(
      _proxyHandler,
      config.address,
      config.port,
      poweredByHeader: null,
    );
    // 禁用自动压缩，代理透传上游已压缩的响应，避免双重压缩导致客户端 ZlibError
    _server!.autoCompress = false;
    LoggerUtil.instance.d(
      'Proxy server started on ${config.address}:${config.port}',
    );
  }

  Future<void> stop() async {
    if (_server == null) return;
    await _server!.close(force: true);
    _server = null;
    _requestHandler.close();
  }

  /// 重置指定端点的断路器
  void resetCircuitBreaker(String endpointId) {
    _circuitBreakerRegistry.reset(endpointId);
  }

  /// 重置所有断路器
  void resetAllCircuitBreakers() {
    _circuitBreakerRegistry.resetAll();
  }

  /// 移除端点的断路器实例（用于端点被删除时清理内存）
  void removeCircuitBreaker(String endpointId) {
    _circuitBreakerRegistry.removeBreaker(endpointId);
  }

  /// 获取当前仍处于断路中的端点 ID
  Set<String> getOpenCircuitBreakerEndpointIds(Iterable<String> endpointIds) {
    return _circuitBreakerRegistry.getOpenEndpointIds(endpointIds);
  }

  /// 代理处理器 - 协调路由、请求处理和响应处理
  Future<shelf.Response> _proxyHandler(shelf.Request request) async {
    final rawBody = await request.read().expand((x) => x).toList();

    bool? previousSucceeded;
    shelf.Response? finalResponse;

    // 循环尝试端点
    while (await _router.hasNext(previousSucceeded)) {
      final endpoint = _router.currentEndpoint;
      if (endpoint == null) break;
      int? startTime;
      http.Request? preparedRequest;
      try {
        // 1. 构建请求
        preparedRequest = _requestHandler.prepareRequest(
          request,
          endpoint,
          rawBody,
        );
        // 2. 发送请求（在此处开始计时，确保 responseTime 是真实的服务器响应时间）
        startTime = DateTime.now().millisecondsSinceEpoch;
        final response = await _requestHandler.forwardRequest(preparedRequest);
        // 3. 处理响应并判断是否需要继续
        finalResponse = await _responseHandler.handleResponse(
          response,
          endpoint,
          request,
          rawBody,
          startTime,
          mappedRequestBodyBytes: preparedRequest.bodyBytes,
          forwardedHeaders: preparedRequest.headers,
        );

        previousSucceeded =
            response.statusCode >= 200 && response.statusCode < 300;

        if (previousSucceeded) {
          break;
        }
        // 失败响应：统一通过路由器中的断路器机制决定重试或故障转移
      } catch (e) {
        // 异常也按普通失败处理，统一交给断路器计数
        previousSucceeded = false;
        LoggerUtil.instance.e('Exception during request: $e');

        // 记录异常请求到数据库
        _responseHandler.recordException(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: rawBody,
          startTime: startTime,
          error: e,
          mappedRequestBodyBytes: preparedRequest?.bodyBytes,
          forwardedHeaders: preparedRequest?.headers,
        );
      }
    }

    if (finalResponse != null) {
      return finalResponse;
    } else {
      // 所有端点都失败
      return shelf.Response.internalServerError(body: 'All endpoints failed');
    }
  }
}
