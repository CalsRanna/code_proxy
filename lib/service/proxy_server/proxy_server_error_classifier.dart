import 'package:http/http.dart' as http;

/// 代理上游错误分类工具。
class ProxyServerErrorClassifier {
  ProxyServerErrorClassifier._();

  /// 是否为"首部到达前连接被关闭"的瞬时传输错误。
  ///
  /// 该错误严格发生在请求转发阶段——此时代理尚未向客户端写入任何字节,
  /// 因此对原端点透明重试对客户端完全无感,不破坏单条 SSE 约束。
  /// 仅匹配 [http.ClientException] 且消息包含目标短语,其余传输异常返回 false。
  static bool isHeaderNotReceived(Object error) {
    return error is http.ClientException &&
        error.message.contains(
          'Connection closed before full header was received',
        );
  }
}
