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

  /// 是否为"疑似 header 未达但未被 [isHeaderNotReceived] 精确命中"的变体。
  ///
  /// 用途:[isHeaderNotReceived] 依赖 Dart SDK 私有错误文案的精确匹配,
  /// 一旦 SDK 改措辞,匹配会静默失效——透明重试悄悄退化为不再触发,难以察觉。
  /// 本函数对"看起来像 header 未达、但没精确命中"的 ClientException 返回 true,
  /// 供 service 层打 WARNING 作为静默降级的预警信号。
  ///
  /// 收窄条件(大小写无关):同时包含 'header' 与 'connection closed',
  /// 且不是已被精确识别的那条——避免对连接拒绝/重置等正常异常产生噪音。
  static bool isPossibleHeaderNotReceivedVariant(Object error) {
    if (error is! http.ClientException) return false;
    if (isHeaderNotReceived(error)) return false;
    final message = error.message.toLowerCase();
    return message.contains('header') && message.contains('connection closed');
  }
}
