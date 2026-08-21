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
import 'package:http/io_client.dart';
import 'package:shelf/shelf.dart' as shelf;

/// 请求处理器 - 负责请求准备和转发
class ProxyServerRequestHandler {
  final http.Client _httpClient;
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
    _httpClient.close();
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
  // ===========================================================================
  static http.Client _buildHttpClient() {
    final httpClient = HttpClient()
      ..autoUncompress = false
      ..connectionFactory = _keepaliveConnectionFactory;
    return IOClient(httpClient);
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

  /// 转发HTTP请求
  Future<http.StreamedResponse> forwardRequest(http.Request request) async {
    final response = await _httpClient
        .send(request)
        .timeout(Duration(milliseconds: config.apiTimeoutMs));
    return response;
  }

  /// 为端点准备HTTP请求
  http.Request prepareRequest(
    shelf.Request request,
    EndpointEntity endpoint,
    List<int> rawBody,
  ) {
    // 构建目标URL
    final uri = _buildTargetUrl(endpoint, request);

    // 准备请求头
    final headers = _prepareHeaders(request, endpoint);

    // 处理请求体中的模型映射和 1M 上下文参数
    final processedBody = _processRequestBody(
      rawBody,
      endpoint,
      path: request.url.path,
    );

    return http.Request(request.method, uri)
      ..headers.addAll(headers)
      ..bodyBytes = processedBody;
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

    final normalized =
        originalPath.startsWith('/') ? originalPath : '/$originalPath';
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
  ) {
    final headers = Map<String, String>.from(request.headers);

    // OpenAI 格式端点走独立的头部处理
    if (_needsConversion(endpoint)) {
      return _prepareOpenAiHeaders(headers, endpoint);
    }

    // 保留客户端原始的认证方式，只替换 key 值
    _replaceAuthToken(headers, endpoint);
    headers.remove('host');
    headers.remove('content-length');
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
    _injectOneMContextHeader(headers, request.requestedUri.path);

    return headers;
  }

  /// 注入 1M 上下文需要的 beta 头和请求体参数。
  ///
  /// 某些上游端点（如 AnyRouter）要求同时具备：
  ///   - anthropic-beta: context-1m-2025-08-07,max-tokens-1m
  ///   - thinking: {"type": "adaptive"}
  ///   - max_tokens >= 32000
  ///
  /// Claude Desktop 的健康检查探针不包含这些参数，会导致 400 错误。
  void _injectOneMContextHeader(Map<String, String> headers, String path) {
    if (path != '/v1/messages') return;

    // 注入 context-1m 和 max-tokens-1m beta 标记
    const requiredBetas = ['context-1m-2025-08-07', 'max-tokens-1m'];
    final existing = headers['anthropic-beta'];
    final parts = existing != null ? existing.split(',') : <String>[];
    for (final beta in requiredBetas) {
      if (!parts.any((p) => p.trim() == beta)) {
        parts.add(beta);
      }
    }
    headers['anthropic-beta'] = parts.join(',');
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
    final tokenPreview = token.length > 8 ? '${token.substring(0, 4)}...${token.substring(token.length - 4)}' : '<empty or short>';
    LoggerUtil.instance.d(
      'Auth token for endpoint ${endpoint.name}: $tokenPreview',
    );
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
    final tokenPreview = token.length > 8
        ? '${token.substring(0, 4)}...${token.substring(token.length - 4)}'
        : '<empty or short>';
    LoggerUtil.instance.d(
      'Auth token for OpenAI-format endpoint ${endpoint.name}: $tokenPreview',
    );

    headers
      ..remove('x-api-key')
      ..remove('anthropic-beta')
      ..remove('anthropic-version')
      ..remove('host')
      ..remove('content-length')
      ..remove('accept-encoding');
    headers['authorization'] = 'Bearer $token';
    headers['accept-encoding'] = 'identity';
    return headers;
  }

  /// 处理请求体中的模型映射和 1M 上下文参数注入。
  List<int> _processRequestBody(
    List<int> rawBody,
    EndpointEntity endpoint, {
    String path = '/v1/messages',
  }) {
    try {
      final bodyString = utf8.decode(rawBody, allowMalformed: true);
      if (bodyString.isEmpty) return rawBody;

      final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;

      // 模型映射
      if (bodyJson.containsKey('model')) {
        final originalModel = bodyJson['model'] as String?;
        final mappedModel = ProxyServerModelMapper.mapModel(
          originalModel,
          endpoint: endpoint,
        );

        LoggerUtil.instance.d(
          'Model mapping: endpoint=${endpoint.name}, original=$originalModel, mapped=$mappedModel',
        );

        if (mappedModel != null && mappedModel.isNotEmpty) {
          bodyJson['model'] = mappedModel;
        }
      }

      // OpenAI 格式端点：整体转换为对应 API 的请求格式。
      // 模型映射已先行完成；1M 上下文注入为 Anthropic 专有逻辑不适用。
      switch (endpoint.apiFormat) {
        case EndpointApiFormat.openai:
          return utf8.encode(
            jsonEncode(_openAiRequestConverter.convert(bodyJson)),
          );
        case EndpointApiFormat.openaiResponses:
          return utf8.encode(
            jsonEncode(_openAiResponsesRequestConverter.convert(bodyJson)),
          );
        case EndpointApiFormat.anthropic:
          break;
      }

      // 注入 1M 上下文参数（仅 /v1/messages）
      if (path == '/v1/messages') {
        _injectOneMContextBody(bodyJson);
      }

      return utf8.encode(jsonEncode(bodyJson));
    } catch (e) {
      LoggerUtil.instance.w('Failed to parse/replace model in body: $e');
      return rawBody;
    }
  }

  /// 注入 1M 上下文需要的请求体参数。
  ///
  /// 仅当客户端未自行提供这些参数时才注入：
  ///   - thinking 缺失时注入 adaptive thinking
  ///   - max_tokens 缺失或 < 32000 时设为 32000
  ///
  /// Claude Code 已自行发送这些参数，此注入对其无影响。
  void _injectOneMContextBody(Map<String, dynamic> body) {
    // 仅对 Claude 族模型注入（避免影响 DeepSeek 等非 Claude 端点）
    final model = body['model'] as String?;
    if (model == null || !model.startsWith('claude-')) return;

    if (!body.containsKey('thinking')) {
      body['thinking'] = {'type': 'adaptive'};
    }

    final maxTokens = body['max_tokens'];
    if (maxTokens == null || (maxTokens is int && maxTokens < 32000)) {
      body['max_tokens'] = 32000;
    }
  }
}
