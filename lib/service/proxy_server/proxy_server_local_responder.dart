import 'dart:convert';

import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'proxy_server_router.dart';
import 'proxy_server_token_estimator.dart';

/// 本地应答层 —— 在请求进入路由/转发循环之前，对可本地应答的
/// 请求类型直接返回响应，避免无效的网络往返。
///
/// 当前处理的请求类型:
///   - `HEAD *`           → 存活性检查，直接返回 200
///   - `GET /v1/models`   → 返回本地模型列表，确保 ID 与 Profile inferenceModels 一致
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

    // 2) GET /v1/models → 返回本地模型列表，确保 ID 与 Profile inferenceModels
    //    精确一致，打通 Claude Desktop 的 discovery 链路使 prefer1m 正常生效。
    if (method == 'GET' && path == '/v1/models') {
      return _buildModelsResponse();
    }

    // 3) count_tokens → 本地估算，避免 60% 上游 404
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

  /// 从 [ClaudeCodeModelConfigService] 构建 /v1/models 响应。
  ///
  /// 使用标准 Anthropic API 字段格式。Claude Desktop 自动发现模型列表时
  /// 通过 [max_input_tokens] 识别 1M 上下文支持——数据来自 models.dev 的
  /// limit.context，与模型定价同源，避免硬编码。
  static shelf.Response _buildModelsResponse() {
    final models = <Map<String, dynamic>>[];
    final pricing = ModelPricingService.instance;

    try {
      final config = ClaudeCodeModelConfigService.instance.config;
      for (final modelId in [
        config.anthropicDefaultOpusModel,
        config.anthropicDefaultSonnetModel,
        config.anthropicDefaultHaikuModel,
      ]) {
        if (modelId.isEmpty) continue;

        final entry = <String, dynamic>{
          'id': modelId,
          'display_name': _displayName(modelId),
          'type': 'model',
        };

        // 从 models.dev 数据中获取真实上下文窗口
        final info = pricing.getPricing(modelId);
        if (info?.contextWindow != null) {
          entry['max_input_tokens'] = info!.contextWindow;
        }

        models.add(entry);
      }
    } catch (_) {}

    if (models.isEmpty) return _emptyModelsResponse();

    final data = <String, dynamic>{
      'data': models,
      'has_more': false,
      'first_id': models.first['id'],
      'last_id': models.last['id'],
    };

    return shelf.Response.ok(
      jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  }

  /// 配置不可用时返回空列表。
  static shelf.Response _emptyModelsResponse() {
    return shelf.Response.ok(
      jsonEncode({'data': <Map<String, dynamic>>[], 'has_more': false}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// 从模型 ID 生成可读的显示名称。
  static String _displayName(String modelId) {
    final match =
        RegExp(r'^claude-(\w+)-(\d+)-(\d+)').firstMatch(modelId);
    if (match != null) {
      final variant = match.group(1)!;
      final major = match.group(2)!;
      final minor = match.group(3)!;
      return 'Claude ${variant[0].toUpperCase()}${variant.substring(1)} $major.$minor';
    }
    return modelId
        .split('-')
        .map((s) => s[0].toUpperCase() + s.substring(1))
        .join(' ');
  }

  static String _normalizePath(String path) {
    if (path.isEmpty) return '/';
    return path.startsWith('/') ? path : '/$path';
  }
}
