import 'dart:convert';

import 'package:code_proxy/service/claude_code_model_config_service.dart';
import 'package:code_proxy/service/model_pricing_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_sentinel.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:code_proxy/util/model_display_name_util.dart';
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
  /// id 使用统一哨兵名(见 [ProxySentinel]):CLI(经模型发现拿到同一
  /// id)与 Desktop(发现列表 id)从同一入口进入代理,由
  /// ProxyServerModelMapper 精确映射到端点实际模型 —— 故障转移只改出口,
  /// 客户端视角的模型名恒定。
  ///
  /// 哨兵以 `claude-` 开头并通过 [anthropic_family_tier] 标记 —— 同时
  /// 满足 Claude Desktop(v1.6259.1 起)与 Claude Code 自动发现的
  /// "必须是明显 Claude 模型"过滤(官方文档:auto-discovery shows only
  /// models whose IDs are recognizably Claude)。
  ///
  /// 使用标准 Anthropic API 字段格式。Claude Desktop 自动发现模型列表时
  /// 通过 [max_input_tokens] 识别 1M 上下文支持——数据来自 models.dev 的
  /// limit.context，与模型定价同源，避免硬编码。
  static shelf.Response _buildModelsResponse() {
    final models = <Map<String, dynamic>>[];
    final pricing = ModelPricingService.instance;

    try {
      final config = ClaudeCodeModelConfigService.instance.config;
      final entries = [
        (
          sentinel: ProxySentinel.opus,
          modelId: config.anthropicDefaultOpusModel,
          tier: ProxySentinel.tierOpus,
        ),
        (
          sentinel: ProxySentinel.sonnet,
          modelId: config.anthropicDefaultSonnetModel,
          tier: ProxySentinel.tierSonnet,
        ),
        (
          sentinel: ProxySentinel.haiku,
          modelId: config.anthropicDefaultHaikuModel,
          tier: ProxySentinel.tierHaiku,
        ),
      ];
      for (final entry in entries) {
        if (entry.modelId.isEmpty) continue;

        final model = <String, dynamic>{
          'id': entry.sentinel,
          'display_name': modelDisplayName(entry.modelId),
          'type': 'model',
          'anthropic_family_tier': entry.tier,
        };

        // 从 models.dev 数据中获取真实上下文窗口
        final info = pricing.getPricing(entry.modelId);
        if (info?.contextWindow != null) {
          model['max_input_tokens'] = info!.contextWindow;
        }

        models.add(model);
      }
    } catch (e) {
      // 部分降级：已成功构建的条目仍会返回。此处记日志避免静默失效 ——
      // 早前 _displayName 对畸形模型名抛 RangeError 时会无声丢掉条目。
      LoggerUtil.instance.w('Failed to build /v1/models entries: $e');
    }

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

  static String _normalizePath(String path) {
    if (path.isEmpty) return '/';
    return path.startsWith('/') ? path : '/$path';
  }
}
