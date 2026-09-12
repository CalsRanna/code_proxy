import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_audit_body_writer.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_local_responder.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request_body.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request_handler.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/response/proxy_server_response_handler.dart';
import 'package:code_proxy/service/proxy_server/response/request_attempt_context.dart';
import 'package:code_proxy/service/proxy_server/response/request_attempt_recorder.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_circuit_breaker_registry.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_router.dart';
import 'package:code_proxy/service/proxy_server/transport/proxy_server_client_connections.dart';
import 'package:code_proxy/service/proxy_server/transport/proxy_server_request_cancellation.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

class ProxyServerService {
  final ProxyServerConfig config;
  final String _authToken;

  final void Function(EndpointEntity)? onEndpointUnavailable;
  final void Function(EndpointEntity)? onEndpointRestored;
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  onRequestCompleted;

  /// 每次尝试创建流式正文写入器的工厂；未配置时不启用流式审计。
  final ProxyAuditBodyWriter Function()? createAuditBodyWriter;

  late final ProxyServerRouter _router;

  /// 出站请求处理器，随 [start] 重建、随 [stop] 关闭置空。
  ///
  /// 不做成 `late final` 单例：stop() 会关闭其内部 HttpClient，
  /// 若重启失败后回滚复用同一实例，后续所有转发都会抛
  /// "Client is already closed"。stop() 先取消全部在途请求再置空，
  /// 处理路径按「server 运行 ⇒ handler 非空」直接断言。
  ProxyServerRequestHandler? _requestHandler;
  final _activeRequests = <ProxyServerRequestCancellation>{};
  late final ProxyServerLocalResponder _localResponder;
  late final ProxyServerCircuitBreakerRegistry _circuitBreakerRegistry;
  HttpServer? _server;
  ProxyServerClientConnections? _clientConnections;

  ProxyServerService({
    required this.config,
    required String authToken,
    this.onRequestCompleted,
    this.onEndpointUnavailable,
    this.onEndpointRestored,
    this.createAuditBodyWriter,
  }) : _authToken = authToken {
    if (authToken.trim().isEmpty) {
      throw ArgumentError.value(authToken, 'authToken', 'must not be empty');
    }
    _circuitBreakerRegistry = ProxyServerCircuitBreakerRegistry(
      failureThreshold: config.circuitBreakerFailureThreshold,
      recoveryTimeoutMs: config.circuitBreakerRecoveryTimeoutMs,
    );
    _router = ProxyServerRouter(
      config: config,
      circuitBreakerRegistry: _circuitBreakerRegistry,
      onEndpointUnavailable: onEndpointUnavailable,
      onEndpointRestored: onEndpointRestored,
    );
    _localResponder = ProxyServerLocalResponder(_router);
  }

  set endpoints(List<EndpointEntity> endpoints) {
    _router.setEndpoints(endpoints);
  }

  void _cancelActiveRequests(String reason) {
    for (final cancellation in _activeRequests.toList()) {
      cancellation.cancel(ProxyServerRequestCancelled(reason));
    }
    _activeRequests.clear();
  }

  Future<void> start() async {
    if (_server != null) {
      throw StateError('Server is already running');
    }
    // 每次启动都重建出站 HttpClient（stop 时已随旧实例关闭），
    // 保证服务实例可安全地 stop → start 循环复用（端口变更回滚路径依赖此语义）
    final requestHandler = ProxyServerRequestHandler(config);
    _requestHandler = requestHandler;

    try {
      final connections = ProxyServerClientConnections(
        await ServerSocket.bind(config.address, config.port),
      );
      _clientConnections = connections;
      _server = HttpServer.listenOn(connections);
      shelf_io.serveRequests(_server!, _proxyHandler, poweredByHeader: null);
    } catch (_) {
      await _clientConnections?.close();
      _clientConnections = null;
      if (identical(_requestHandler, requestHandler)) {
        _requestHandler = null;
      }
      requestHandler.close();
      rethrow;
    }
    // 禁用自动压缩，代理透传上游已压缩的响应，避免双重压缩导致客户端 ZlibError
    _server!.autoCompress = false;
    LoggerUtil.instance.d(
      'Proxy server started on ${config.address}:${config.port}',
    );
  }

  Future<void> stop() async {
    _cancelActiveRequests('Proxy server stopped');
    final server = _server;
    _server = null;
    final connections = _clientConnections;
    _clientConnections = null;
    final handler = _requestHandler;
    _requestHandler = null;
    try {
      await server?.close(force: true);
    } finally {
      // HttpServer.listenOn does not own the listening ServerSocket.
      await connections?.close();
      handler?.close();
    }
  }

  /// 重置指定端点的断路器
  void resetCircuitBreaker(String endpointId) {
    _circuitBreakerRegistry.reset(endpointId);
  }

  /// 移除端点的断路器实例（用于端点被删除时清理内存）
  void removeCircuitBreaker(String endpointId) {
    _circuitBreakerRegistry.removeBreaker(endpointId);
  }

  int? get boundPort => _server?.port;

  /// 获取当前仍处于断路中的端点 ID
  Set<String> getOpenCircuitBreakerEndpointIds(Iterable<String> endpointIds) {
    return _circuitBreakerRegistry.getOpenEndpointIds(endpointIds);
  }

  /// 代理处理器 - 协调路由、请求处理和响应处理
  Future<shelf.Response> _proxyHandler(shelf.Request request) async {
    // HEAD 仅返回本地存活状态，不读取正文、也不会访问上游，因此可供
    // 操作系统或桌面客户端在尚未装载凭据时探活。
    if (request.method == 'HEAD') {
      final localResponse = _localResponder.tryRespond(
        request,
        ProxyServerRequestBody.empty(),
      );
      if (localResponse != null) return localResponse;
    }

    // 在读取完整请求体和接触上游密钥前验证本地代理令牌。
    if (!_isAuthorized(request)) return _unauthorizedResponse();

    final cancellation = ProxyServerRequestCancellation();
    _activeRequests.add(cancellation);
    final untrack = _clientConnections!.track(
      request.context['shelf.io.connection_info'] as HttpConnectionInfo,
      cancellation,
    );
    void completed() {
      untrack();
      _activeRequests.remove(cancellation);
    }

    try {
      final response = await _handleAuthorizedRequest(request, cancellation);
      cancellation.throwIfCancelled();
      return response.change(
        body: cancellation.bindStream(
          response.read(),
          cancelWithError: false,
          onDone: completed,
        ),
      );
    } on ProxyServerRequestCancelled catch (error) {
      completed();
      return shelf.Response(
        HttpStatus.serviceUnavailable,
        headers: {'content-type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'type': 'error',
          'error': {'type': 'api_error', 'message': error.reason},
        }),
      );
    } catch (_) {
      completed();
      rethrow;
    }
  }

  Future<shelf.Response> _handleAuthorizedRequest(
    shelf.Request request,
    ProxyServerRequestCancellation cancellation,
  ) async {
    // 用 BytesBuilder 收集为 Uint8List，而不是 .expand((x) => x).toList()：
    // 后者得到的 List<int> 在 Dart VM 里每个元素占一个字长，一个 10 MB 的
    // 长上下文请求会膨胀成约 80 MB（实测 2 MiB 载荷造成约 56 MiB RSS
    // 增量）。Uint8List 是 1:1 存储，且是 List<int> 的子类，下游签名无需改动。
    final bodyBuilder = BytesBuilder(copy: false);
    await cancellation.bindStream(request.read()).forEach(bodyBuilder.add);
    cancellation.throwIfCancelled();
    final Uint8List rawBody = bodyBuilder.takeBytes();

    // 请求体解析结果在本请求内共享：探针识别与模型映射/协议转换读同一份，
    // 避免各自把整段请求体 jsonDecode 一遍（见 ProxyServerRequestBody）。
    final requestBody = ProxyServerRequestBody(rawBody);

    // 本地应答: 对健康检查、count_tokens 等请求直接返回，
    // 避免不必要的上游网络往返。
    final localResponse = _localResponder.tryRespond(request, requestBody);
    if (localResponse != null) return localResponse;

    return _handleForwardedRequest(request, requestBody, cancellation);
  }

  Future<shelf.Response> _handleForwardedRequest(
    shelf.Request request,
    ProxyServerRequestBody requestBody,
    ProxyServerRequestCancellation cancellation,
  ) async {
    // Do not filter completed attempts by status when forwarding them for logging.
    // Cancellation suppresses its own log and breaker failure, including late
    // errors after a setting change; previously recorded attempts remain intact.
    final recorder = RequestAttemptRecorder(
      onRequestCompleted: (endpoint, request, response) {
        if (!cancellation.isCancelled) {
          // 记录器在正文完整结束后回调，兼顾普通响应与 SSE。
          if (response.statusCode >= 200 && response.statusCode < 400) {
            _router.recordSuccess(endpoint);
          }
          onRequestCompleted?.call(endpoint, request, response);
        }
      },
    );
    final responseHandler = ProxyServerResponseHandler(
      recorder: recorder,
      onStreamError: (endpoint) {
        if (!cancellation.isCancelled) _router.recordFailure(endpoint);
      },
    );

    final routeSession = _router.startRequest();
    // 同一请求内的请求体处理缓存：同端点重试时复用已处理好的字节，
    // 避免对大请求体重复 decode + encode。随请求创建、随请求丢弃。
    final bodyCache = ProxyServerBodyCache();
    shelf.Response? finalResponse;
    Object? lastException;

    // 循环尝试端点
    while (true) {
      cancellation.throwIfCancelled();
      String? retryAfter;
      var succeeded = false;
      final endpoint = routeSession.currentEndpoint;
      if (endpoint == null) break;
      int? startTime;
      PreparedRequest? prepared;
      final bodyWriter = createAuditBodyWriter?.call();
      if (bodyWriter != null) {
        // 客户端取消时清理尚未落盘的临时正文；日志层接管后 discard 是空操作。
        cancellation.onCancel(() => unawaited(bodyWriter.discard()));
      }
      RequestAttemptContext attemptContext() => RequestAttemptContext(
        endpoint: endpoint,
        request: request,
        originalRequestBodyBytes: requestBody.bytes,
        originalModel: requestBody.originalModel,
        // prepareRequest 抛异常时出站请求为空，转发体回退为原始字节，
        // 日志里记录的模型名应与之一致，取原始模型名。
        mappedModel: prepared?.mappedModel ?? requestBody.originalModel,
        startTime: startTime,
        bodyWriter: bodyWriter,
        mappedRequestBodyBytes: prepared?.request.bodyBytes,
        forwardedHeaders: prepared?.request.headers,
      );
      final requestHandler = _requestHandler!;
      try {
        // 1. 构建请求
        final preparedForAttempt = requestHandler.prepareRequest(
          request,
          endpoint,
          requestBody,
          bodyCache: bodyCache,
        );
        prepared = preparedForAttempt;
        // 2. 从本次发送开始计时，responseTime 不包含此前的退避等待。
        startTime = DateTime.now().millisecondsSinceEpoch;
        final response = await cancellation.run(
          requestHandler.forwardRequest(
            preparedForAttempt.request,
            cancellation: cancellation,
          ),
        );
        // 3. 处理响应并判断是否需要继续
        finalResponse = await cancellation.run(
          responseHandler.handleResponse(response, attemptContext()),
        );
        cancellation.throwIfCancelled();

        // 2xx/3xx 均为成功透传：3xx（重定向/缓存语义）不视为端点故障，
        // 不重试、不进断路器。
        succeeded = response.statusCode >= 200 && response.statusCode < 400;
        // 上游 4xx 直接返回客户端，不重试、不计入熔断。
        if (response.statusCode >= 400 && response.statusCode < 500) {
          break;
        }
        retryAfter = response.headers['retry-after'];
      } catch (e) {
        cancellation.throwIfCancelled();
        // header 未达瞬时错误:原端点透明重试,不污染断路器/不重建 client。
        //
        // 安全性说明:此时代理虽未向客户端写入任何字节,但**无法确定上游是否
        // 已执行甚至完成推理**——重发 POST 可能导致上游重复推理与重复计费。
        // 这是经权衡后接受的风险(换取长任务的成功率),并非无副作用的安全重试。
        if (routeSession.shouldTransientRetry(endpoint, e)) {
          final used = routeSession.transientRetriesUsedFor(endpoint);
          routeSession.recordTransientRetry(endpoint);
          // 中间失败仅记日志,不入 request_logs,避免污染失败率/请求量统计。
          LoggerUtil.instance.w(
            'Transient header-not-received on ${endpoint.name}, '
            'retrying same endpoint (${used + 1}/2); '
            'upstream may have executed — possible duplicate billing',
          );
          startTime = null;
          continue;
        }

        // 异常走统一失败处理
        lastException = e;
        LoggerUtil.instance.e('Exception during request: $e');

        // 记录异常请求到数据库
        recorder.recordException(attemptContext(), e);
      }
      cancellation.throwIfCancelled();
      if (succeeded) {
        break;
      }
      routeSession.recordFailure();
      if (!await routeSession.advanceAfterAttempt(
        cancellation: cancellation,
        retryAfter: retryAfter,
      )) {
        break;
      }
    }

    if (finalResponse != null) {
      return finalResponse;
    } else {
      final message = lastException != null
          ? 'All endpoints failed: $lastException'
          : 'All endpoints failed';
      return shelf.Response.internalServerError(body: message);
    }
  }

  bool _isAuthorized(shelf.Request request) {
    final apiKey = request.headers['x-api-key']?.trim();
    if (apiKey != null && _constantTimeEquals(apiKey, _authToken)) {
      return true;
    }

    final authorization = request.headers[HttpHeaders.authorizationHeader];
    if (authorization == null) return false;
    final match = RegExp(
      r'^\s*Bearer\s+(.+?)\s*$',
      caseSensitive: false,
    ).firstMatch(authorization);
    final bearer = match?.group(1);
    return bearer != null && _constantTimeEquals(bearer, _authToken);
  }

  static bool _constantTimeEquals(String left, String right) {
    var difference = left.length ^ right.length;
    final length = left.length > right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      final leftCode = index < left.length ? left.codeUnitAt(index) : 0;
      final rightCode = index < right.length ? right.codeUnitAt(index) : 0;
      difference |= leftCode ^ rightCode;
    }
    return difference == 0;
  }

  static shelf.Response _unauthorizedResponse() {
    return shelf.Response(
      HttpStatus.unauthorized,
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.wwwAuthenticateHeader: 'Bearer realm="Code Proxy"',
      },
      body: jsonEncode({
        'type': 'error',
        'error': {
          'type': 'authentication_error',
          'message': 'Invalid or missing proxy authentication token',
        },
      }),
    );
  }
}
