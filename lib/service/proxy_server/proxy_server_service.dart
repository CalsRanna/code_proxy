import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_error_classifier.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request_handler.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response_handler.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_local_responder.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_router.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_circuit_breaker_registry.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

class ProxyServerService {
  final ProxyServerConfig config;
  final String _authToken;

  final void Function(EndpointEntity)? onEndpointUnavailable;
  final void Function(EndpointEntity)? onEndpointRestored;
  final void Function(EndpointEntity, ProxyServerRequest, ProxyServerResponse)?
  onRequestCompleted;

  late final ProxyServerRouter _router;

  /// 出站请求处理器，随 [start] 重建、随 [stop] 关闭置空。
  ///
  /// 不做成 `late final` 单例：stop() 会关闭其内部 HttpClient，
  /// 若重启失败后回滚复用同一实例，后续所有转发都会抛
  /// "Client is already closed"。见 [_proxyHandler] 中的空值兜底。
  ProxyServerRequestHandler? _requestHandler;
  late final ProxyServerResponseHandler _responseHandler;
  late final ProxyServerLocalResponder _localResponder;
  late final ProxyServerCircuitBreakerRegistry _circuitBreakerRegistry;
  HttpServer? _server;

  ProxyServerService({
    required this.config,
    required String authToken,
    this.onRequestCompleted,
    this.onEndpointUnavailable,
    this.onEndpointRestored,
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
    _responseHandler = ProxyServerResponseHandler(
      onRequestCompleted: onRequestCompleted,
      // 流式响应中途中断时补记一次失败，避免断路器把损坏的流记为成功
      onStreamError: (endpoint) => _router.recordFailure(endpoint),
    );
    _localResponder = ProxyServerLocalResponder(_router);
  }

  set endpoints(List<EndpointEntity> endpoints) {
    _router.setEndpoints(endpoints);
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
      _server = await shelf_io.serve(
        _proxyHandler,
        config.address,
        config.port,
        poweredByHeader: null,
      );
    } catch (_) {
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
    final server = _server;
    _server = null;
    final handler = _requestHandler;
    _requestHandler = null;
    try {
      await server?.close(force: true);
    } finally {
      handler?.close();
    }
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
      final localResponse = _localResponder.tryRespond(request, const []);
      if (localResponse != null) return localResponse;
    }

    // 在读取完整请求体和接触上游密钥前验证本地代理令牌。
    if (!_isAuthorized(request)) return _unauthorizedResponse();

    // 用 BytesBuilder 收集为 Uint8List，而不是 .expand((x) => x).toList()：
    // 后者得到的 List<int> 在 Dart VM 里每个元素占一个字长，一个 10 MB 的
    // 长上下文请求会膨胀成约 80 MB（实测 2 MiB 载荷造成约 56 MiB RSS
    // 增量）。Uint8List 是 1:1 存储，且是 List<int> 的子类，下游签名无需改动。
    final bodyBuilder = BytesBuilder(copy: false);
    await request.read().forEach(bodyBuilder.add);
    final Uint8List rawBody = bodyBuilder.takeBytes();

    // 本地应答: 对健康检查、count_tokens 等请求直接返回，
    // 避免不必要的上游网络往返。
    final localResponse = _localResponder.tryRespond(request, rawBody);
    if (localResponse != null) return localResponse;

    final routeSession = _router.startRequest();
    // 同一请求内的请求体处理缓存：同端点重试时复用已处理好的字节，
    // 避免对大请求体重复 decode + encode。随请求创建、随请求丢弃。
    final bodyCache = ProxyServerBodyCache();
    bool? previousSucceeded;
    shelf.Response? finalResponse;
    Object? lastException;

    // 循环尝试端点
    while (await routeSession.hasNext(previousSucceeded)) {
      final endpoint = routeSession.currentEndpoint;
      if (endpoint == null) break;
      int? startTime;
      http.Request? preparedRequest;
      final requestHandler = _requestHandler;
      if (requestHandler == null) {
        // 理论上不可达：_server 非 null 时 _requestHandler 必已重建。
        // 防御 stop() 与在途请求的极端交错，避免空引用崩溃。
        return shelf.Response.internalServerError(
          body: 'Proxy server is shutting down',
        );
      }
      try {
        // 1. 构建请求
        preparedRequest = requestHandler.prepareRequest(
          request,
          endpoint,
          rawBody,
          bodyCache: bodyCache,
        );
        // 2. 发送请求（在此处开始计时，确保 responseTime 是真实的服务器响应时间）
        startTime = DateTime.now().millisecondsSinceEpoch;
        final response = await requestHandler.forwardRequest(preparedRequest);
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

        // 2xx/3xx 均为成功透传：3xx（重定向/缓存语义）不视为端点故障，
        // 不重试、不进断路器。
        //
        // 用 continue 让循环条件处的 hasNext(true) 向断路器记录本次成功
        // （连续失败计数清零 / halfOpen 探测成功恢复 closed）后再结束轮次，
        // 它固定返回 false，不会产生额外迭代。此处若直接 break，
        // recordSuccess 将永远不会被主链路调用。
        if (response.statusCode >= 200 && response.statusCode < 400) {
          previousSucceeded = true;
          continue;
        }
        // 4xx：原样返回客户端，不重试、不熔断、不故障转移。
        //
        // 这不是"4xx 都是客户端的错所以端点没问题"那种教科书判断 ——
        // 部分第三方网关的状态码不规范，一个 4xx 很可能只是**限流**
        // （有的网关限流返回 429，有的返回 400/403），并不代表端点故障。
        // 之所以仍然一律短路，是因为在这里做任何处理都比交给客户端更差：
        //
        // 1. 故障转移会牺牲 prompt cache。本项目的主备策略就是为了让请求
        //    始终落在同一端点以最大化 cache 命中（见 CLAUDE.md）。为一次
        //    可能几百毫秒就恢复的限流而切走，等于把整个长上下文的
        //    cache_read 变成全额未缓存输入，代价远高于等一下再试。
        // 2. 熔断会放大伤害。限流是瞬时的，断路器一开就是整整
        //    recoveryTimeout，把一个本来还能用的端点直接摘掉。
        // 3. 客户端本来就会重试。Claude Code / Anthropic SDK 自带对 429 的
        //    退避重试并遵守 retry-after，且重试仍打向同一端点 —— 既保住了
        //    cache 亲和性，退避策略也比代理层的盲猜更准确。
        //
        // 换言之：4xx 不进断路器，不是因为它无害，而是因为**代理层缺少
        // 分辨"限流"与"真错"的可靠信号**，而客户端那一层两者都能处理得
        // 更好。若将来要细化，正确方向是按 retry-after / 端点级配置识别
        // 限流，而不是把 4xx 并入 5xx 的熔断路径。
        if (response.statusCode >= 400 && response.statusCode < 500) {
          previousSucceeded = false;
          break;
        }
        // 5xx 及以上：端点故障，统一通过断路器机制决定重试或故障转移
        previousSucceeded = false;
      } catch (e) {
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
          previousSucceeded = null; // 跳过 hasNext 的断路器逻辑,直接重进循环体
          continue;
        }

        // 预警:疑似 header 未达但未被分类器精确命中(可能 SDK 改了错误文案,
        // 导致透明重试静默失效)。窄范围匹配,避免对正常传输异常产生噪音。
        if (ProxyServerErrorClassifier.isPossibleHeaderNotReceivedVariant(e)) {
          LoggerUtil.instance.w(
            'Possible unrecognized header-not-received variant '
            '(classifier may be stale): $e',
          );
        }

        // 异常走统一失败处理
        previousSucceeded = false;
        lastException = e;
        LoggerUtil.instance.e('Exception during request: $e');

        // 记录异常请求到数据库
        _responseHandler.recordException(
          endpoint: endpoint,
          request: request,
          requestBodyBytes: rawBody,
          startTime: startTime,
          error: e,
          statusCode: HttpStatus.badGateway,
          mappedRequestBodyBytes: preparedRequest?.bodyBytes,
          forwardedHeaders: preparedRequest?.headers,
        );
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
