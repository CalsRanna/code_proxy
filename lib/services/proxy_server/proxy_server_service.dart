import 'dart:async';
import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request_handler.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response_handler.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_router.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

class ProxyServerService {
  final ProxyServerConfig config;

  final void Function(EndpointEntity)? onEndpointUnavailable;
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  onRequestCompleted;

  late final ProxyServerRouter _router;
  late final ProxyServerRequestHandler _requestHandler;
  late final ProxyServerResponseHandler _responseHandler;
  HttpServer? _server;

  ProxyServerService({
    required this.config,
    this.onRequestCompleted,
    this.onEndpointUnavailable,
  }) {
    final repository = EndpointRepository(Database.instance);
    _router = ProxyServerRouter(
      config: config,
      repository: repository,
      onEndpointUnavailable: onEndpointUnavailable,
    );
    _requestHandler = ProxyServerRequestHandler();
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

  /// 代理处理器 - 协调路由、请求处理和响应处理
  Future<shelf.Response> _proxyHandler(shelf.Request request) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final rawBody = await request.read().expand((x) => x).toList();

    HandleResult? previousResult;
    shelf.Response? finalResponse;

    // 循环尝试端点
    while (await _router.hasNext(previousResult)) {
      final endpoint = _router.currentEndpoint;
      if (endpoint == null) break;

      try {
        // 1. 构建请求
        final preparedRequest = _requestHandler.prepareRequest(
          request,
          endpoint,
          rawBody,
        );

        // 2. 发送请求
        final response = await _requestHandler.forwardRequest(preparedRequest);

        // 3. 处理响应并判断是否需要继续
        finalResponse = await _responseHandler.handleResponse(
          response,
          endpoint,
          request,
          rawBody,
          startTime,
          mappedRequestBodyBytes: preparedRequest.bodyBytes,
        );

        // 如果返回非null，这是最终响应
        if (finalResponse != null) {
          // 获取HandleResult并设置previousResult
          previousResult = _responseHandler.getHandleResult(response);
          break;
        }

        // 如果返回null，继续循环
        // 设置previousResult为serverError，触发重试或转移逻辑
        previousResult = HandleResult.serverError;
      } catch (e) {
        // 异常：设置previousResult为exception，触发重试或转移
        previousResult = HandleResult.exception;
        LoggerUtil.instance.e('Exception during request: $e');

        // 记录异常请求到数据库
        _responseHandler.recordException(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: rawBody,
          startTime: startTime,
          error: e,
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
