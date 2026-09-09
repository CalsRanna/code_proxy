import 'dart:async';
import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/default_model_config_service.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_chat_request_converter.dart';
import 'package:code_proxy/service/proxy_server/converter/openai_responses_request_converter.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_model_mapper.dart';
import 'package:code_proxy/service/proxy_server/transport/proxy_server_request_cancellation.dart';
import 'package:code_proxy/service/proxy_server/transport/proxy_server_transport.dart';
import 'package:code_proxy/util/logger_util.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

/// 请求处理器 - 负责请求准备和转发
class ProxyServerRequestHandler {
  final ProxyServerTransport _transport;
  final ProxyServerConfig config;
  final OpenAiChatRequestConverter _openAiRequestConverter =
      const OpenAiChatRequestConverter();
  final OpenAiResponsesRequestConverter _openAiResponsesRequestConverter =
      const OpenAiResponsesRequestConverter();

  /// 端点是否需要代理完成协议转换（OpenAI 两大 API 格式）
  static bool _needsConversion(EndpointEntity endpoint) =>
      endpoint.apiFormat != EndpointApiFormat.anthropic;

  ProxyServerRequestHandler(this.config)
    : _transport = ProxyServerTransport(apiTimeoutMs: config.apiTimeoutMs);

  void close() => _transport.close();

  Future<http.StreamedResponse> forwardRequest(
    http.Request request, {
    ProxyServerRequestCancellation? cancellation,
  }) => _transport.forwardRequest(request, cancellation: cancellation);

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
    final baseUrl = (endpoint.baseUrl ?? '').replaceAll(RegExp(r'/$'), '');
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
    final baseUrl = (endpoint.baseUrl ?? '').replaceAll(RegExp(r'/+$'), '');
    final hasV1Suffix = baseUrl.endsWith('/v1');
    switch (endpoint.apiFormat) {
      case EndpointApiFormat.openaiChat:
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
    final token = endpoint.authToken ?? '';
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

  /// OpenAI Chat Completions 端点的请求头处理。
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
    final token = endpoint.authToken ?? '';

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
        final mappedModel = model == null
            ? null
            : ProxyServerModelMapper.mapModel(
                model,
                endpoint: endpoint,
                defaultConfig: DefaultModelConfigService.instance.config,
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
        case EndpointApiFormat.openaiChat:
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
