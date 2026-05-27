import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_model_mapper.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shelf/shelf.dart' as shelf;

/// 请求处理器 - 负责请求准备和转发
///
/// 内置 HTTP 客户端健康检查与自动重建机制：
/// - 所有上游请求共用同一个 [IOClient] 实例以复用连接池
/// - 当连续发生 3 次传输层异常（[ClientException]、[SocketException]、
///   [HandshakeException]、[TlsException]）时判定客户端内部状态可能已损坏，
///   自动创建新实例替换
/// - 旧客户端等待所有 in-flight 请求完成后安全关闭，保证零中断
class ProxyServerRequestHandler {
  http.Client _httpClient;
  final ProxyServerConfig config;

  http.Client? _oldClient;
  int _inFlightCount = 0;
  int _consecutiveConnectionErrors = 0;
  static const int _maxConsecutiveConnectionErrors = 3;

  ProxyServerRequestHandler(this.config) : _httpClient = _buildHttpClient();

  void close() {
    _httpClient.close();
    _oldClient?.close();
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
  ///
  /// 请求成功时重置连续传输错误计数；
  /// 发生传输层异常时累加计数，连续达到 [_maxConsecutiveConnectionErrors]
  /// 次后自动重建 [_httpClient] 实例。
  Future<http.StreamedResponse> forwardRequest(http.Request request) async {
    _inFlightCount++;
    try {
      final response = await _httpClient
          .send(request)
          .timeout(Duration(milliseconds: config.apiTimeoutMs));
      _consecutiveConnectionErrors = 0;
      return response;
    } on http.ClientException {
      _onConnectionError();
      rethrow;
    } on SocketException {
      _onConnectionError();
      rethrow;
    } on HandshakeException {
      _onConnectionError();
      rethrow;
    } on TlsException {
      _onConnectionError();
      rethrow;
    } finally {
      _inFlightCount--;
      _tryCloseOldClient();
    }
  }

  void _onConnectionError() {
    _consecutiveConnectionErrors++;
    if (_consecutiveConnectionErrors >= _maxConsecutiveConnectionErrors &&
        _oldClient == null) {
      _rebuildClient();
    }
  }

  void _rebuildClient() {
    LoggerUtil.instance.w(
      'Rebuilding HTTP client after $_maxConsecutiveConnectionErrors '
      'consecutive transport errors',
    );
    _oldClient = _httpClient;
    _httpClient = _buildHttpClient();
    _consecutiveConnectionErrors = 0;
  }

  void _tryCloseOldClient() {
    if (_oldClient != null && _inFlightCount == 0) {
      _oldClient!.close();
      _oldClient = null;
      LoggerUtil.instance.d('Closed old HTTP client after rebuild');
    }
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

    // 处理请求体中的模型映射
    final processedBody = _processRequestBody(rawBody, endpoint);

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
    final path = request.url.path;
    final query = request.url.query;
    final separator = path.startsWith('/') ? '' : '/';
    final url = query.isNotEmpty
        ? '$baseUrl$separator$path?$query'
        : '$baseUrl$separator$path';
    return Uri.parse(url);
  }

  /// 准备请求头
  Map<String, String> _prepareHeaders(
    shelf.Request request,
    EndpointEntity endpoint,
  ) {
    final headers = Map<String, String>.from(request.headers);
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
    return headers;
  }

  /// 根据客户端原始的认证方式替换 key 值
  ///
  /// 如果客户端使用 x-api-key，则替换 x-api-key 的值；
  /// 如果客户端使用 Authorization: Bearer，则替换 Bearer token；
  /// 如果两者都没有，则默认使用 x-api-key。
  void _replaceAuthToken(Map<String, String> headers, EndpointEntity endpoint) {
    final token = endpoint.anthropicAuthToken ?? '';
    if (headers.containsKey('x-api-key')) {
      headers['x-api-key'] = token;
    } else if (headers.containsKey('authorization')) {
      headers['authorization'] = 'Bearer $token';
    } else {
      headers['x-api-key'] = token;
    }
  }

  /// 处理请求体中的模型映射
  List<int> _processRequestBody(List<int> rawBody, EndpointEntity endpoint) {
    try {
      final bodyString = utf8.decode(rawBody, allowMalformed: true);
      if (bodyString.isEmpty) return rawBody;

      final bodyJson = jsonDecode(bodyString) as Map<String, dynamic>;

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

      return utf8.encode(jsonEncode(bodyJson));
    } catch (e) {
      LoggerUtil.instance.w('Failed to parse/replace model in body: $e');
      return rawBody;
    }
  }
}
