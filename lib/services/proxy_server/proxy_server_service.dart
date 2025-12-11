import 'dart:async';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request_handler.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response_handler.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_router.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

class ProxyServerService {
  final ProxyServerConfig config;

  final void Function(EndpointEntity)? onEndpointUnavailable;
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  onRequestCompleted;

  List<EndpointEntity> _endpoints = [];
  late final ProxyServerRouter _router;
  late final ProxyServerRequestHandler _requestHandler;
  late final ProxyServerResponseHandler _responseHandler;
  HttpServer? _server;

  // 临时存储映射后的请求体，用于日志记录
  List<int>? _lastMappedRequestBody;

  ProxyServerService({
    required this.config,
    this.onRequestCompleted,
    this.onEndpointUnavailable,
  }) {
    _router = ProxyServerRouter(
      config: config,
      onEndpointUnavailable: onEndpointUnavailable,
    );
    _requestHandler = ProxyServerRequestHandler();
    _responseHandler = ProxyServerResponseHandler(
      onRequestCompleted: onRequestCompleted,
    );
  }

  set endpoints(List<EndpointEntity> endpoints) => _endpoints = endpoints;

  Future<void> dispose() async {
    await stop();
    _requestHandler.close();
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
    await _server!.close(force: false);
    _server = null;
  }

  /// 为指定端点执行请求
  Future<http.StreamedResponse> _executeRequestForEndpoint(
    EndpointEntity endpoint,
    shelf.Request request,
    List<int> rawBody,
  ) async {
    final preparedRequest = _requestHandler.prepareRequest(
      request,
      endpoint,
      rawBody,
    );

    // 存储映射后的请求体，用于日志记录
    _lastMappedRequestBody = preparedRequest.bodyBytes;

    return _requestHandler.forwardRequest(preparedRequest);
  }

  /// 代理处理器 - 协调路由、请求处理和响应处理
  Future<shelf.Response> _proxyHandler(shelf.Request request) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final rawBody = await request.read().expand((x) => x).toList();

    // 使用路由器选择端点并执行请求
    final routeResult = await _router.routeRequest(
      _endpoints,
      (endpoint) => _executeRequestForEndpoint(endpoint, request, rawBody),
    );

    // 处理路由结果
    if (routeResult.success &&
        routeResult.response != null &&
        routeResult.endpoint != null) {
      return await _responseHandler.handleResponse(
        routeResult.response!,
        routeResult.endpoint!,
        request,
        rawBody,
        startTime,
        mappedRequestBodyBytes: _lastMappedRequestBody,
      );
    } else {
      // 失败的情况
      return shelf.Response.internalServerError(
        body: routeResult.error ?? 'All endpoints failed',
      );
    }
  }
}
