import 'dart:async';
import 'dart:io';

import 'package:code_proxy/service/proxy_server/transport/proxy_server_request_cancellation.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;

/// 出站连接、超时和取消；请求协议的准备由 RequestHandler 负责。
class ProxyServerTransport {
  ProxyServerTransport({required this.apiTimeoutMs})
    : _httpClient = _buildHttpClient();

  final int apiTimeoutMs;
  final HttpClient _httpClient;
  // HttpClient 的 connectionFactory 没有请求参数，通过 Zone 传递连接取消信号。
  static final _connectionCancellationKey = Object();

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
  /// HTTPS 直连时 SDK 直接使用 factory 返回的 socket，必须自行完成 TLS。
  /// 经 HTTP 代理时则返回裸 TCP，SDK 负责发送 CONNECT 并升级隧道的 TLS。
  /// 普通 HTTP 也返回裸 TCP。
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
    final cancellation =
        Zone.current[_connectionCancellationKey]
            as ProxyServerRequestCancellation?;
    cancellation?.throwIfCancelled();
    final host = proxyHost ?? uri.host;
    final port = proxyPort ?? uri.port;
    // HTTP 代理先通过裸 TCP 建立 CONNECT 隧道；HttpClient 随后升级 TLS。
    final isSecure = uri.isScheme('https') && proxyHost == null;

    final ConnectionTask<Socket> task;
    if (isSecure) {
      task = await SecureSocket.startConnect(host, port);
    } else {
      task = await Socket.startConnect(host, port);
    }

    // socket 真正建立后再设置 keepalive 选项。
    // SecureSocket 底层仍是 TCP socket，setRawOption 对其同样有效。
    final remove = cancellation?.onCancel(task.cancel);
    unawaited(
      task.socket.then<void>((socket) {
        remove?.call();
        if (cancellation?.isCancelled ?? false) {
          socket.destroy();
        } else {
          _enableTcpKeepalive(socket);
        }
      }, onError: (Object _) => remove?.call()),
    );
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
  /// - 建立连接的最长时间；
  /// - 等待响应头的最长时间；
  /// - 响应体相邻数据块之间的最长空闲时间。
  ///
  /// 后者是 idle timeout 而非流的总时长，因此持续有数据的长 SSE 不会
  /// 因总运行时间较长而被误杀，但响应头后永久停顿会可靠终止。
  ///
  /// [cancellation] 取消当前请求的连接任务、响应头等待或响应体订阅，
  /// 不关闭共享客户端中的其他并发请求。等待响应头时调用
  /// [HttpClientRequest.abort]；当前 Dart SDK 的 TLS 握手取消可能延迟释放
  /// 底层连接，迟到的结果会被清理，不恢复请求或重试。
  ///
  /// 末尾的异常转换复刻 IOClient 的行为：dart:io 抛的是 HttpException /
  /// SocketException，而透明重试判定使用
  /// [http.ClientException]（"Connection closed before full header was
  /// received"）。少了这层转换，透明重试会静默退化为不再触发。
  Future<http.StreamedResponse> forwardRequest(
    http.Request request, {
    ProxyServerRequestCancellation? cancellation,
  }) async {
    final timeout = Duration(milliseconds: apiTimeoutMs);

    try {
      final ioRequest = await _openRequest(request, timeout, cancellation);
      // Observe abort errors even if cancellation happens before close().
      unawaited(ioRequest.done.then<void>((_) {}, onError: (Object _) {}));
      final remove = cancellation?.onCancel(ioRequest.abort);
      try {
        cancellation?.throwIfCancelled();
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

        // Once headers arrive, abort() no longer closes the socket. Cancelling
        // the response subscription terminates only this request's connection.
        final responseBody = cancellation == null
            ? ioResponse
            : cancellation.bindStream<List<int>>(ioResponse);

        final headers = <String, String>{};
        ioResponse.headers.forEach((name, values) {
          headers[name] = values.join(',');
        });

        final timedBody = responseBody
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
      } finally {
        remove?.call();
      }
    } on SocketException catch (error) {
      throw http.ClientException(error.message, request.url);
    } on HttpException catch (error) {
      throw http.ClientException(error.message, error.uri);
    }
  }

  Future<HttpClientRequest> _openRequest(
    http.Request request,
    Duration timeout,
    ProxyServerRequestCancellation? cancellation,
  ) async {
    final connecting = ProxyServerRequestCancellation();
    final remove = cancellation?.onCancel(
      () => connecting.cancel(cancellation.reason!),
    );
    try {
      connecting.throwIfCancelled();
      final pending =
          runZoned(
            () => _httpClient.openUrl(request.method, request.url),
            zoneValues: {_connectionCancellationKey: connecting},
          ).then((ioRequest) {
            if (connecting.isCancelled) {
              unawaited(
                ioRequest.done.then<void>((_) {}, onError: (Object _) {}),
              );
              ioRequest.abort();
              connecting.throwIfCancelled();
            }
            return ioRequest;
          });
      return await connecting
          .run(pending)
          .timeout(
            timeout,
            onTimeout: () {
              final error = TimeoutException(
                'Upstream connection timed out',
                timeout,
              );
              connecting.cancel(error);
              throw error;
            },
          );
    } finally {
      remove?.call();
    }
  }
}
