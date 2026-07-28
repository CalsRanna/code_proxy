import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;

import 'proxy_server_router.dart';
import 'proxy_server_token_estimator.dart';

/// 本地应答层 —— 在请求进入路由/转发循环之前，对可本地应答的
/// 请求类型直接返回响应，避免无效的网络往返。
///
/// 当前处理的请求类型:
///   - `HEAD *`           → 存活性检查，直接返回 200
///   - `POST /v1/messages/count_tokens` → 本地估算 token 数
///
/// 不处理的请求返回 null，交由正常的代理转发逻辑处理。
class ProxyServerLocalResponder {
  final ProxyServerRouter _router;

  const ProxyServerLocalResponder(this._router);

  /// 尝试本地处理此请求；无法处理时返回 null。
  shelf.Response? tryRespond(shelf.Request request, List<int> rawBody) {
    final method = request.method;
    final path = _normalizePath(request.requestedUri.path);

    // 1) HEAD 请求 → 存活性检查，根据端点可用性返回 200 或 503
    if (method == 'HEAD') {
      final hasEndpoints = _router.hasAvailableEndpoints;
      return shelf.Response(
        hasEndpoints ? 200 : 503,
        headers: {'content-length': '0'},
      );
    }

    // 2) count_tokens → 本地估算，避免 60% 上游 404
    if (method == 'POST' && path == '/v1/messages/count_tokens') {
      final estimatedTokens = ProxyServerTokenEstimator.estimateRequestBody(
        rawBody,
      );
      final body = jsonEncode({'input_tokens': estimatedTokens});
      return shelf.Response.ok(
        body,
        headers: {'content-type': 'application/json'},
      );
    }

    return null;
  }

  static String _normalizePath(String path) {
    if (path.isEmpty) return '/';
    return path.startsWith('/') ? path : '/$path';
  }
}
