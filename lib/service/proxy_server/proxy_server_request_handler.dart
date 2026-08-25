import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_compat_request_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_responses_request_converter.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_model_mapper.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

/// 请求处理器 - 负责请求准备和转发
class ProxyServerRequestHandler {
  final HttpClient _httpClient;
  final ProxyServerConfig config;
  final OpenAiCompatRequestConverter _openAiRequestConverter =
      const OpenAiCompatRequestConverter();
  final OpenAiResponsesRequestConverter _openAiResponsesRequestConverter =
      const OpenAiResponsesRequestConverter();

  /// 端点是否需要代理完成协议转换（OpenAI 两大 API 格式）
  static bool _needsConversion(EndpointEntity endpoint) =>
      endpoint.apiFormat != EndpointApiFormat.anthropic;

  ProxyServerRequestHandler(this.config) : _httpClient = _buildHttpClient();

  void close() {
    // force: true 与 IOClient.close() 的语义一致 —— stop() 需要立即断开，
    // 不等在途连接自然结束。
    _httpClient.close(force: true);
  }

  // ===========================================================================
  // 出站 HttpClient 的构造
  // ===========================================================================
  //
  // 做两件事：
  //
  // 1) autoUncompress = false
  //    代理需要透传上游的原始压缩字节（gzip/deflate/br/zstd）给客户端，
  //    自身只在需要提取 token 使用量、记录日志时按需解压。打开自动解压会
  //    在遇到异常字节时直接抛 ZlibException，把可恢复的转发流变成致命错误。
  //
  // 2) connectionFactory 注入开了 TCP keepalive 的 socket
  //    背景：曾出现过大量 `ClientException: Connection closed before full
  //    header was received` 报错，且上游声称请求已经成功完成。本地复现实验
  //    证实：
  //      - Dart IOClient 自己能撑过 120s 完全静默的连接
  //      - 一旦上游 socket 在 HEADER 到达前被对端关闭，必然抛出与生产
  //        一字不差的这条 ClientException
  //    生产场景里上游是 SSE 长 TTFB（200-300s），中间的 NAT / 防火墙 /
  //    CDN（如 anyrouter 前的 ESA）会把这段完全静默的 TCP 链路当成 dead
  //    flow 清掉，等数据回来时只剩 RST。
  //
  //    `dart:io` 的 HttpClient 创建 Socket 时**不会**默认启用 SO_KEEPALIVE，
  //    所以没有任何 TCP 层的探针去刷新中间网元的 conntrack 表。我们通过
  //    `connectionFactory` 自己接管 Socket 创建，开启 SO_KEEPALIVE 并把
  //    idle/interval/probe count 都调成有用的值（macOS/Linux 的系统默认
  //    都是 2 小时才开始第一个探针，对我们 200-300s 的场景等于没开）。
  //
  //    这是一次性能改造的最小侵入版本。如果未来仍有静默断链问题，下一步
  //    可以考虑换 `package:cupertino_http` / `package:cronet_http` 拿到
  //    HTTP/2 PING 帧的应用层 keepalive。
  // 3) 直接持有 dart:io 的 HttpClient，不再包一层 package:http 的 IOClient
  //    只有 HttpClient 这条路径能拿到 HttpClientRequest.abort()，让超时真正
  //    切断底层请求。代价是 forwardRequest 必须自己复刻 IOClient 的异常
  //    转换（HttpException / SocketException → ClientException），否则
  //    ProxyServerErrorClassifier 的透明重试判定会静默失效。
  // ===========================================================================
  static HttpClient _buildHttpClient() {
    return HttpClient()
      ..autoUncompress = false
      ..connectionFactory = _keepaliveConnectionFactory;
  }

  /// 建立 socket 时启用 TCP keepalive 的 connectionFactory。
  ///
  /// 重要：当设置了自定义 connectionFactory 后，Dart SDK 的 HttpClient
  /// **不会**自动为 HTTPS 请求做 TLS 升级。SDK 内部的逻辑是：
  ///   - 没有 connectionFactory → HTTPS 直连用 SecureSocket.startConnect
  ///   - 有 connectionFactory → 直接调用 factory，拿到什么 socket 就用什么
  ///
  /// 因此我们必须自己判断 scheme：
  ///   - https → 用 SecureSocket.startConnect（返回的 socket 已完成 TLS）
  ///   - http  → 用 Socket.startConnect（裸 TCP）
  ///
  /// TCP keepalive 选项在 TLS 之下的底层 TCP socket 上设置。对于
  /// SecureSocket，我们通过监听 Future 在 socket 建立后设置选项——
  /// SecureSocket 底层仍然是 TCP socket，keepalive 探针在 TCP 层工作，
  /// 不受 TLS 层影响。
  static Future<ConnectionTask<Socket>> _keepaliveConnectionFactory(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final host = proxyHost ?? uri.host;
    final port = proxyPort ?? uri.port;
    final isSecure = uri.isScheme('https');

    final ConnectionTask<Socket> task;
    if (isSecure) {
      task = await SecureSocket.startConnect(host, port);
    } else {
      task = await Socket.startConnect(host, port);
    }

    // socket 真正建立后再设置 keepalive 选项。
    // SecureSocket 底层仍是 TCP socket，setRawOption 对其同样有效。
    unawaited(task.socket.then(_enableTcpKeepalive).catchError((_) {}));
    return task;
  }

  /// 在已连接 socket 上启用 TCP keepalive 并把时序参数调小。
  ///
  /// 默认 OS 行为：
  ///   - macOS: 7200s 空闲后才发第一个探针，间隔 75s，共 8 次 —— 对我们
  ///     无意义，conntrack 早过期了。
  ///   - Linux: 同样 7200s / 75s / 9 次。
  ///
  /// 我们调整为：30s 空闲就开始探针、每 15s 一次、共 4 次。这样在长
  /// TTFB 静默期，TCP 层每 15s 就有一次 keepalive 包来回，足以让中间
  /// 网元持续认为这条连接是 live 的。
  ///
  /// 平台常量列表 (level / option)：
  ///   - SO_KEEPALIVE (开启总开关)
  ///       macOS:  SOL_SOCKET=0xffff, SO_KEEPALIVE=0x0008
  ///       Linux:  SOL_SOCKET=1,      SO_KEEPALIVE=9
  ///   - 首次探针前的空闲时长 (秒)
  ///       macOS:  IPPROTO_TCP=6,     TCP_KEEPALIVE=0x10
  ///       Linux:  IPPROTO_TCP=6,     TCP_KEEPIDLE=4
  ///   - 探针之间的间隔 (秒)
  ///       macOS:  IPPROTO_TCP=6,     TCP_KEEPINTVL=0x101
  ///       Linux:  IPPROTO_TCP=6,     TCP_KEEPINTVL=5
  ///   - 判定链路死亡前的最大探针次数
  ///       macOS:  IPPROTO_TCP=6,     TCP_KEEPCNT=0x102
  ///       Linux:  IPPROTO_TCP=6,     TCP_KEEPCNT=6
  ///
  /// Windows 走的是 WSAIoctl(SIO_KEEPALIVE_VALS)，无法通过 setRawOption
  /// 直接表达，这里只开总开关，让系统按默认参数发探针。
  static const int _keepaliveIdleSeconds = 30;
  static const int _keepaliveIntervalSeconds = 15;
  static const int _keepaliveProbeCount = 4;

  static void _enableTcpKeepalive(Socket socket) {
    try {
      final isLinux = Platform.isLinux;
      final isApple = Platform.isMacOS || Platform.isIOS;

      // SOL_SOCKET / SO_KEEPALIVE — 所有平台都先把总开关打开
      final solSocket = isLinux ? 1 : 0xffff;
      final soKeepalive = isLinux ? 9 : 0x8;
      socket.setRawOption(RawSocketOption.fromInt(solSocket, soKeepalive, 1));

      // 仅 macOS / Linux 调整时序参数；Windows 走系统默认
      if (isLinux || isApple) {
        const ipprotoTcp = 6;

        final tcpIdleOpt = isApple ? 0x10 : 4; // TCP_KEEPALIVE / TCP_KEEPIDLE
        final tcpIntvlOpt = isApple ? 0x101 : 5; // TCP_KEEPINTVL
        final tcpCntOpt = isApple ? 0x102 : 6; // TCP_KEEPCNT

        socket.setRawOption(
          RawSocketOption.fromInt(
            ipprotoTcp,
            tcpIdleOpt,
            _keepaliveIdleSeconds,
          ),
        );
        socket.setRawOption(
          RawSocketOption.fromInt(
            ipprotoTcp,
            tcpIntvlOpt,
            _keepaliveIntervalSeconds,
          ),
        );
        socket.setRawOption(
          RawSocketOption.fromInt(ipprotoTcp, tcpCntOpt, _keepaliveProbeCount),
        );
      }
    } catch (e) {
      // setRawOption 失败不致命：socket 仍然能用，只是退化到系统默认的
      // keepalive 行为（即"等同没开"）。打个 warn 方便后续排查。
      LoggerUtil.instance.w(
        'Failed to configure TCP keepalive on outbound socket: $e',
      );
    }
  }

  /// 转发 HTTP 请求。
  ///
  /// 同一个配置值分别限制：
  /// - 等待响应头的最长时间；
  /// - 响应体相邻数据块之间的最长空闲时间。
  ///
  /// 后者是 idle timeout 而非流的总时长，因此持续有数据的长 SSE 不会
  /// 因总运行时间较长而被误杀，但响应头后永久停顿会可靠终止。
  ///
  /// 两处超时都调用 [HttpClientRequest.abort] 真正切断请求。此前用
  /// `Future.timeout` 包 IOClient 只能让等待的 Future 提前完成，底层请求
  /// 仍在跑，超时的连接会一直占着连接池直到自然回收 —— 在 SSE 长 TTFB
  /// （200-300s）场景下这会累积成大量僵死连接。
  ///
  /// 末尾的异常转换复刻 IOClient 的行为：dart:io 抛的是 HttpException /
  /// SocketException，而 [ProxyServerErrorClassifier] 只认
  /// [http.ClientException]（"Connection closed before full header was
  /// received"）。少了这层转换，透明重试会静默退化为不再触发。
  Future<http.StreamedResponse> forwardRequest(http.Request request) async {
    final timeout = Duration(milliseconds: config.apiTimeoutMs);

    try {
      // 连接阶段单独计时：此时还没有 HttpClientRequest，无法 abort，
      // 但 TCP/TLS 握手远快于响应头等待，实际超时几乎只发生在下一步。
      final ioRequest = await _httpClient
          .openUrl(request.method, request.url)
          .timeout(timeout);
      ioRequest
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..contentLength = request.bodyBytes.length
        ..persistentConnection = request.persistentConnection;
      request.headers.forEach((name, value) {
        ioRequest.headers.set(name, value);
      });
      ioRequest.add(request.bodyBytes);

      final HttpClientResponse ioResponse;
      try {
        ioResponse = await ioRequest.close().timeout(timeout);
      } on TimeoutException {
        // 切断请求本身。abort 会让上面那个 Future 以错误完成，但
        // Future.timeout 内部已注册 onError，不会变成 unhandled async error。
        ioRequest.abort();
        rethrow;
      }

      final headers = <String, String>{};
      ioResponse.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });

      final timedBody = ioResponse
          .timeout(
            timeout,
            onTimeout: (sink) {
              ioRequest.abort();
              sink.addError(
                TimeoutException(
                  'Upstream response body was idle for '
                  '${timeout.inMilliseconds}ms',
                  timeout,
                ),
              );
              sink.close();
            },
          )
          .handleError((Object error) {
            final httpException = error as HttpException;
            throw http.ClientException(
              httpException.message,
              httpException.uri,
            );
          }, test: (error) => error is HttpException);

      return http.StreamedResponse(
        timedBody,
        ioResponse.statusCode,
        contentLength: ioResponse.contentLength == -1
            ? null
            : ioResponse.contentLength,
        request: request,
        headers: headers,
        isRedirect: ioResponse.isRedirect,
        persistentConnection: ioResponse.persistentConnection,
        reasonPhrase: ioResponse.reasonPhrase,
      );
    } on SocketException catch (error) {
      throw http.ClientException(error.message, request.url);
    } on HttpException catch (error) {
      throw http.ClientException(error.message, error.uri);
    }
  }

  /// 为端点准备HTTP请求
  http.Request prepareRequest(
    shelf.Request request,
    EndpointEntity endpoint,
    List<int> rawBody, {
    ProxyServerBodyCache? bodyCache,
  }) {
    // 构建目标URL
    final uri = _buildTargetUrl(endpoint, request);

    // 请求体只解析一次：得到的模型名同时用于模型映射结果和 beta 头的
    // 模型族判断。传入 bodyCache 时，同端点重试直接复用上次的字节，
    // 不再对大请求体重复 decode + encode。
    final processed = bodyCache == null
        ? _processRequestBody(rawBody, endpoint)
        : bodyCache.putIfAbsent(
            endpoint.id,
            () => _processRequestBody(rawBody, endpoint),
          );

    // 准备请求头
    final headers = _prepareHeaders(request, endpoint, processed.model);

    return http.Request(request.method, uri)
      ..headers.addAll(headers)
      ..bodyBytes = processed.bytes;
  }

  /// 构建目标URL
  Uri _buildTargetUrl(EndpointEntity endpoint, shelf.Request request) {
    final baseUrl = (endpoint.anthropicBaseUrl ?? '').replaceAll(
      RegExp(r'/$'),
      '',
    );
    final path = _resolveForwardPath(endpoint, request.url.path);
    final query = request.url.query;
    final separator = path.startsWith('/') ? '' : '/';
    final url = query.isNotEmpty
        ? '$baseUrl$separator$path?$query'
        : '$baseUrl$separator$path';
    return Uri.parse(url);
  }

  /// 解析实际转发路径。
  ///
  /// OpenAI 格式端点将 POST /v1/messages 重写为对应 API 路径：
  /// - chat completions：baseUrl 已以 /v1 结尾 → /chat/completions，
  ///   否则 → /v1/chat/completions
  /// - responses：baseUrl 已以 /v1 结尾 → /responses，否则 → /v1/responses
  ///
  /// 其他路径（正常流量中不会出现：count_tokens/models 由 LocalResponder
  /// 本地应答）原样透传并告警。
  ///
  /// 注意：`request.url.path` 是不带前导斜杠的相对路径
  /// （_proxyHandler 直接挂载在 shelf_io.serve 上，无前缀剥离），
  /// 这里统一归一化为绝对路径再比较。
  String _resolveForwardPath(EndpointEntity endpoint, String originalPath) {
    if (endpoint.apiFormat == EndpointApiFormat.anthropic) return originalPath;

    final normalized = originalPath.startsWith('/')
        ? originalPath
        : '/$originalPath';
    if (normalized != '/v1/messages') {
      LoggerUtil.instance.w(
        'OpenAI-format endpoint received unexpected path "$originalPath", '
        'forwarding as-is',
      );
      return originalPath;
    }
    final baseUrl = (endpoint.anthropicBaseUrl ?? '').replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final hasV1Suffix = baseUrl.endsWith('/v1');
    switch (endpoint.apiFormat) {
      case EndpointApiFormat.openai:
        return hasV1Suffix ? '/chat/completions' : '/v1/chat/completions';
      case EndpointApiFormat.openaiResponses:
        return hasV1Suffix ? '/responses' : '/v1/responses';
      case EndpointApiFormat.anthropic:
        return originalPath;
    }
  }

  /// 准备请求头
  Map<String, String> _prepareHeaders(
    shelf.Request request,
    EndpointEntity endpoint,
    String? model,
  ) {
    final headers = Map<String, String>.from(request.headers);

    // OpenAI 格式端点走独立的头部处理
    if (_needsConversion(endpoint)) {
      return _prepareOpenAiHeaders(headers, endpoint);
    }

    // 保留客户端原始的认证方式，只替换 key 值
    _replaceAuthToken(headers, endpoint);
    _stripNonForwardableHeaders(headers);
    // 将 accept-encoding 限制为 gzip, deflate
    //
    // 原因：Dart 标准库仅支持 gzip/deflate 解压，不支持 brotli(br)/zstd。
    // 客户端（如 Claude Code CLI）原始请求中携带 accept-encoding: gzip, deflate, br, zstd，
    // 当上游 API 返回 brotli 压缩的响应时，代理无法解压以提取 token 使用量和记录审计日志。
    // 修改此头不会影响上游处理请求，accept-encoding 是标准的 HTTP 内容协商头，
    // 各类代理和 CDN 在链路中修改它是常规行为。
    //
    // 替代方案：引入第三方包支持 brotli/zstd 解压，保持请求头不变：
    //   - brotli (pub.dev/packages/brotli): 纯 Dart 实现，推荐，无 FFI 依赖
    //   - es_compression (pub.dev/packages/es_compression): FFI 实现，
    //     同时支持 brotli/lz4/zstd，性能更好但需要预编译二进制
    headers['accept-encoding'] = 'gzip, deflate';

    // 自动注入 1M 上下文支持头。
    //
    // 某些上游端点（如 AnyRouter）已将 1M 上下文设为默认要求，
    // 不携带此头的请求会被拒绝。Claude Desktop 的健康检查探针
    // 不发送此头，会导致探针失败。
    _injectOneMContextHeader(headers, request.requestedUri.path, model);

    return headers;
  }

  /// 注入 1M 上下文需要的 beta 头。
  ///
  /// 某些上游端点（如 AnyRouter）已将 1M 上下文设为默认要求，不携带
  /// `anthropic-beta: context-1m-2025-08-07,max-tokens-1m` 的请求会被拒绝；
  /// Claude Desktop 的健康检查探针不发送此头，会导致探针 400。
  ///
  /// 历史说明：曾另有一套请求体注入（`thinking: adaptive` 与
  /// `max_tokens >= 32000`），但其路径判断误用了不带前导斜杠的
  /// `request.url.path`，条件恒为 false，从未执行过。项目在只有 beta 头
  /// 生效的状态下长期稳定运行，证明那些请求体参数并非必需，故已删除。
  ///
  /// 若将来确实遇到需要它们的网关，应做成**端点级开关**而不是全局注入：
  /// 无条件把 `max_tokens` 抬到 32000 会让分类类调用（常用 256）和
  /// 缓存预热（0）变成一次完整推理，产生真实费用。
  void _injectOneMContextHeader(
    Map<String, String> headers,
    String path,
    String? model,
  ) {
    if (path != '/v1/messages') return;

    // 仅在明确不是 Claude 族模型时跳过：anthropic-beta 是 Anthropic 专有头，
    // anthropic 格式端点后面接非 Claude 模型（如自建网关转 DeepSeek）时
    // 发送它可能触发上游 400。
    //
    // model 为 null（请求体无 model 字段或解析失败）时保持注入 —— 不带
    // 完整请求体的健康检查探针依赖这个头。
    if (model != null && !model.startsWith('claude-')) return;

    // 注入 context-1m 和 max-tokens-1m beta 标记。
    //
    // 按空白过滤而非直接 split：客户端可能发来空的 anthropic-beta 头，
    // 而 ''.split(',') 返回 ['']，会拼出前导逗号
    // （",context-1m-2025-08-07,max-tokens-1m"），严格的网关会拒绝。
    const requiredBetas = ['context-1m-2025-08-07', 'max-tokens-1m'];
    final parts = (headers['anthropic-beta'] ?? '')
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    for (final beta in requiredBetas) {
      if (!parts.contains(beta)) {
        parts.add(beta);
      }
    }
    headers['anthropic-beta'] = parts.join(',');
  }

  /// 逐跳（hop-by-hop）头只对单段连接有意义，代理必须剥离而不是转发。
  ///
  /// 实测 shelf 会把客户端的 `connection` / `te` / `upgrade` 原样交到
  /// handler，若直接转发给上游，可能与代理自己设置的 content-length 语义
  /// 冲突，或让上游误以为客户端要求协议升级。`transfer-encoding` 在
  /// dart:io 层就已被消费（不会出现在 shelf headers 中），仍按 RFC 7230
  /// §6.1 一并列出。
  ///
  /// host / content-length 一并移除：目标主机已变，长度由出站请求重新计算。
  static const _hopByHopHeaders = [
    'connection',
    'keep-alive',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'proxy-connection',
  ];

  static void _stripNonForwardableHeaders(Map<String, String> headers) {
    headers.remove('host');
    headers.remove('content-length');
    for (final name in _hopByHopHeaders) {
      headers.remove(name);
    }
  }

  /// 根据端点的认证方式配置替换 key 值
  ///
  /// - preserve: 保持客户端原始的认证方式（如果客户端使用 x-api-key，
  ///   则替换 x-api-key 的值；如果客户端使用 Authorization: Bearer，
  ///   则替换 Bearer token；两者都没有则默认 x-api-key）
  /// - xApiKey: 强制使用 x-api-key（如 OpenCode Go 的 /v1/messages 只认此头）
  /// - bearer: 强制使用 Authorization: Bearer
  void _replaceAuthToken(Map<String, String> headers, EndpointEntity endpoint) {
    final token = endpoint.anthropicAuthToken ?? '';
    switch (endpoint.authMode) {
      case EndpointAuthMode.preserve:
        if (headers.containsKey('x-api-key')) {
          headers['x-api-key'] = token;
        } else if (headers.containsKey('authorization')) {
          headers['authorization'] = 'Bearer $token';
        } else {
          headers['x-api-key'] = token;
        }
      case EndpointAuthMode.xApiKey:
        headers.remove('authorization');
        headers['x-api-key'] = token;
      case EndpointAuthMode.bearer:
        headers.remove('x-api-key');
        headers['authorization'] = 'Bearer $token';
    }
  }

  /// OpenAI 兼容端点的请求头处理。
  ///
  /// - 认证统一为 Authorization: Bearer（authMode 配置对 openai 端点
  ///   不生效，OpenAI 生态标准认证方式即 Bearer）
  /// - 移除 Anthropic 专有头，避免严格网关对未知头报错
  /// - accept-encoding 强制 identity：响应体需要整体转换后重发给客户端，
  ///   不透传压缩字节，流式转换无需边解压边转
  Map<String, String> _prepareOpenAiHeaders(
    Map<String, String> headers,
    EndpointEntity endpoint,
  ) {
    final token = endpoint.anthropicAuthToken ?? '';

    headers
      ..remove('x-api-key')
      ..remove('anthropic-beta')
      ..remove('anthropic-version')
      ..remove('accept-encoding');
    _stripNonForwardableHeaders(headers);
    headers['authorization'] = 'Bearer $token';
    headers['accept-encoding'] = 'identity';
    return headers;
  }

  /// 处理请求体中的模型映射，并回传映射后的模型名。
  ProcessedRequestBody _processRequestBody(
    List<int> rawBody,
    EndpointEntity endpoint,
  ) {
    try {
      final bodyString = utf8.decode(rawBody, allowMalformed: true);
      if (bodyString.isEmpty) return ProcessedRequestBody(rawBody, null);

      final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;

      // 模型映射
      var model = bodyJson['model'] as String?;
      if (bodyJson.containsKey('model')) {
        final mappedModel = ProxyServerModelMapper.mapModel(
          model,
          endpoint: endpoint,
        );

        LoggerUtil.instance.d(
          'Model mapping: endpoint=${endpoint.name}, original=$model, mapped=$mappedModel',
        );

        if (mappedModel != null && mappedModel.isNotEmpty) {
          bodyJson['model'] = mappedModel;
          model = mappedModel;
        }
      }

      // OpenAI 格式端点：整体转换为对应 API 的请求格式。
      // 模型映射已先行完成。
      switch (endpoint.apiFormat) {
        case EndpointApiFormat.openai:
          return ProcessedRequestBody(
            utf8.encode(jsonEncode(_openAiRequestConverter.convert(bodyJson))),
            model,
          );
        case EndpointApiFormat.openaiResponses:
          return ProcessedRequestBody(
            utf8.encode(
              jsonEncode(_openAiResponsesRequestConverter.convert(bodyJson)),
            ),
            model,
          );
        case EndpointApiFormat.anthropic:
          break;
      }

      return ProcessedRequestBody(utf8.encode(jsonEncode(bodyJson)), model);
    } catch (e) {
      LoggerUtil.instance.w('Failed to parse/replace model in body: $e');
      return ProcessedRequestBody(rawBody, null);
    }
  }
}

/// 处理后的请求体字节，以及其中携带的（映射后）模型名。
///
/// 模型名单独回传，避免调用方为了判断模型族而把请求体再解析一遍。
class ProcessedRequestBody {
  final List<int> bytes;

  /// 映射后的模型名；请求体无 model 字段或解析失败时为 null。
  final String? model;

  const ProcessedRequestBody(this.bytes, this.model);
}

/// 单个代理请求内的请求体处理缓存。
///
/// 模型映射与协议转换的结果只取决于端点配置，因此同一端点的重试可以直接
/// 复用上一次的结果，避免对大请求体重复 decode + encode。
///
/// 按请求创建、随请求丢弃：不跨请求共享，也就不会在并发请求之间串状态。
class ProxyServerBodyCache {
  final Map<String, ProcessedRequestBody> _byEndpointId = {};

  ProcessedRequestBody putIfAbsent(
    String endpointId,
    ProcessedRequestBody Function() compute,
  ) {
    return _byEndpointId.putIfAbsent(endpointId, compute);
  }
}
