import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/model/proxy_config.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:http/http.dart' as http;
import 'load_balancer.dart';
import 'health_checker.dart';
import 'stats_collector.dart';
import 'claude_code_config_manager.dart';

/// 转发响应包装类
/// 包含响应和实际使用的请求头
class _ForwardedResponse {
  final Response response;
  final Map<String, String> actualHeaders;

  _ForwardedResponse({required this.response, required this.actualHeaders});
}

/// 代理服务器
/// 使用 shelf 实现透明 HTTP 代理
class ProxyServer {
  final ProxyConfig config;
  final List<Endpoint> Function() getEndpoints;
  final LoadBalancer loadBalancer;
  final HealthChecker healthChecker;
  final StatsCollector statsCollector;
  final ClaudeCodeConfigManager claudeCodeConfigManager;

  /// HTTP 服务器实例
  HttpServer? _server;

  /// HTTP 客户端
  final http.Client _httpClient = http.Client();

  /// 当前活跃连接数
  int _activeConnections = 0;

  /// 服务器启动时间戳
  int? _startedAt;

  /// 缓存的真实 API Key（从备份配置读取）
  String? _realApiKey;

  ProxyServer({
    required this.config,
    required this.getEndpoints,
    required this.loadBalancer,
    required this.healthChecker,
    required this.statsCollector,
    required this.claudeCodeConfigManager,
  });

  // =========================
  // 服务器控制
  // =========================

  /// 启动代理服务器
  Future<void> start() async {
    if (_server != null) {
      throw StateError('Server is already running');
    }

    // 从备份配置读取真实的 API Key
    await _loadRealApiKey();

    // 创建请求处理管道（不使用 logRequests middleware）
    final handler = _proxyHandler;

    // 启动服务器
    _server = await shelf_io.serve(
      handler,
      config.listenAddress,
      config.listenPort,
    );

    _startedAt = DateTime.now().millisecondsSinceEpoch;

    // 启动健康检查
    healthChecker.startActiveHealthCheck();
  }

  /// 从备份配置读取真实的 API Key
  Future<void> _loadRealApiKey() async {
    final backupConfig = await claudeCodeConfigManager.readBackupConfig();
    if (backupConfig != null) {
      _realApiKey = backupConfig['env']?['ANTHROPIC_AUTH_TOKEN'] as String?;
      if (_realApiKey != null) {}
    }
  }

  /// 停止代理服务器
  Future<void> stop() async {
    if (_server == null) return;

    // 停止健康检查
    healthChecker.stopActiveHealthCheck();

    // 关闭服务器
    await _server!.close(force: false);
    _server = null;
    _startedAt = null;
    _activeConnections = 0;

    // 清理缓存的 API Key
    _realApiKey = null;
  }

  /// 服务器是否正在运行
  bool get isRunning => _server != null;

  /// 获取服务器启动时间戳
  int? get startedAt => _startedAt;

  /// 获取当前活跃连接数
  int get activeConnections => _activeConnections;

  // =========================
  // 请求处理
  // =========================

  /// 代理请求处理器
  Future<Response> _proxyHandler(Request request) async {
    _activeConnections++;

    try {
      return await _handleRequest(request);
    } finally {
      _activeConnections--;
    }
  }

  /// 处理单个请求
  Future<Response> _handleRequest(Request request) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final triedEndpoints = <String>{}; // 记录本次请求已尝试的端点

    // 提前读取请求体（只能读取一次）
    final bodyBytes = await request.read().fold<List<int>>(
      [],
      (previous, element) => previous..addAll(element),
    );

    // 尝试多次重试
    for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
      // 选择最优端点（排除已尝试的）
      final endpoint = _selectUntried(triedEndpoints);

      if (endpoint == null) {
        // 没有可用端点
        final error = triedEndpoints.isEmpty
            ? 'No available endpoints'
            : 'All available endpoints failed';
        _recordFailure(
          endpointId: 'unknown',
          endpointName: 'unknown',
          path: request.url.path,
          method: request.method,
          error: error,
          startTime: startTime,
          header: null,
          message: error,
        );

        return Response(
          503,
          body: 'Service Unavailable: $error',
          headers: {'content-type': 'text/plain'},
        );
      }

      triedEndpoints.add(endpoint.id);

      try {
        // 转发请求到上游端点（传递已读取的 bodyBytes）
        // 返回包含响应和实际请求头的包装对象
        final forwardedResponse = await _forwardRequest(
          request,
          endpoint,
          bodyBytes,
        );
        final response = forwardedResponse.response;
        final actualHeaders = forwardedResponse.actualHeaders;
        final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

        // 读取响应体
        final responseBodyBytes = await response.read().toList();
        final flattenedBytes = responseBodyBytes.expand((x) => x).toList();
        final rawResponseBody = utf8.decode(
          flattenedBytes,
          allowMalformed: true,
        );

        // 准备原始请求数据（用于日志记录）
        final rawRequestBody = utf8.decode(bodyBytes, allowMalformed: true);
        final rawHeaderString = jsonEncode(actualHeaders);

        // 转换实际请求头为 Map<String, dynamic>（用于日志显示）
        final headerMap = <String, dynamic>{};
        actualHeaders.forEach((key, value) {
          headerMap[key] = value;
        });

        // 尝试从原始请求中提取模型信息
        String? model;
        final requestJson = jsonDecode(rawRequestBody);
        if (requestJson is Map<String, dynamic>) {
          model = requestJson['model'] as String?;
        }

        // 尝试解析响应以提取 token 信息
        int? inputTokens;
        int? outputTokens;

        // 检查是否是流式响应（SSE 格式）
        final contentType = response.headers['content-type'] ?? '';
        final isStreaming =
            contentType.contains('text/event-stream') ||
            rawResponseBody.startsWith('event:');

        if (isStreaming) {
          // 流式响应：解析 SSE 格式
          final parsedData = _parseSSEResponse(rawResponseBody);
          // 如果从请求中没有提取到模型，尝试从响应中提取
          model ??= parsedData['model'];
          inputTokens = parsedData['inputTokens'];
          outputTokens = parsedData['outputTokens'];
        } else {
          // 非流式响应：解析 JSON
          final responseJson = jsonDecode(rawResponseBody);
          if (responseJson is Map<String, dynamic>) {
            // 如果从请求中没有提取到模型，尝试从响应中提取
            model ??= responseJson['model'] as String?;

            // 提取 usage 信息（Claude API）
            if (responseJson['usage'] != null) {
              final usage = responseJson['usage'] as Map<String, dynamic>;
              inputTokens = usage['input_tokens'] as int?;
              outputTokens = usage['output_tokens'] as int?;
            }
          }
        }

        // 根据状态码判断是否成功
        // 2xx 视为成功，4xx 视为客户端错误（不重试），5xx 视为服务器错误（可重试）
        final statusCode = response.statusCode;

        if (statusCode >= 200 && statusCode < 300) {
          // 2xx 成功
          _recordSuccess(
            endpoint: endpoint,
            path: request.url.path,
            method: request.method,
            statusCode: statusCode,
            responseTime: responseTime,
            header: headerMap,
            message: 'Request successful',
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            rawHeader: rawHeaderString,
            rawRequest: rawRequestBody,
            rawResponse: rawResponseBody,
          );

          // 重新创建响应（因为响应体已被读取）
          return Response(
            statusCode,
            body: flattenedBytes,
            headers: response.headers,
          );
        } else if (statusCode >= 400 && statusCode < 500) {
          // 4xx 客户端错误，不重试，直接返回
          _recordFailure(
            endpointId: endpoint.id,
            endpointName: endpoint.name,
            path: request.url.path,
            method: request.method,
            error: 'HTTP $statusCode',
            startTime: startTime,
            statusCode: statusCode,
            header: headerMap,
            message: 'Client error: HTTP $statusCode',
            rawHeader: rawHeaderString,
            rawRequest: rawRequestBody,
            rawResponse: rawResponseBody,
          );

          // 重新创建响应
          return Response(
            statusCode,
            body: flattenedBytes,
            headers: response.headers,
          );
        } else {
          // 5xx 服务器错误，记录失败并重试
          _recordFailure(
            endpointId: endpoint.id,
            endpointName: endpoint.name,
            path: request.url.path,
            method: request.method,
            error: 'HTTP $statusCode',
            startTime: startTime,
            statusCode: statusCode,
            header: headerMap,
            message: 'Server error: HTTP $statusCode',
            rawHeader: rawHeaderString,
            rawRequest: rawRequestBody,
            rawResponse: rawResponseBody,
          );

          // 如果还有重试次数，尝试其他端点
          if (attempt < config.maxRetries) {
            continue;
          }

          // 已达到最大重试次数，返回最后的错误响应
          return Response(
            statusCode,
            body: flattenedBytes,
            headers: response.headers,
          );
        }
      } catch (e) {
        // 记录失败（异常情况下没有实际的请求头，使用 null）
        final rawRequestBody = utf8.decode(bodyBytes, allowMalformed: true);

        _recordFailure(
          endpointId: endpoint.id,
          endpointName: endpoint.name,
          path: request.url.path,
          method: request.method,
          error: e.toString(),
          startTime: startTime,
          header: null,
          message: 'Exception: ${e.toString()}',
          rawHeader: null,
          rawRequest: rawRequestBody,
          rawResponse: null,
        );

        // 如果还有重试次数，继续尝试其他端点
        if (attempt < config.maxRetries) {
          continue;
        }

        // 已达到最大重试次数，返回错误
        return Response(
          502,
          body: 'Bad Gateway: $e',
          headers: {'content-type': 'text/plain'},
        );
      }
    }

    // 理论上不会到达这里
    return Response(
      500,
      body: 'Internal Server Error',
      headers: {'content-type': 'text/plain'},
    );
  }

  /// 转发请求到上游端点
  Future<_ForwardedResponse> _forwardRequest(
    Request request,
    Endpoint endpoint,
    List<int> bodyBytes,
  ) async {
    // 获取 Claude 配置
    final claudeConfig = endpoint.claudeConfig;
    final effectiveBaseUrl = claudeConfig.effectiveBaseUrl ?? endpoint.url;
    final effectiveAuthMode = claudeConfig.effectiveAuthMode;

    // 构建上游 URL（保留原始路径和查询参数）
    final upstreamUrl = Uri.parse(effectiveBaseUrl).replace(
      path: request.url.path,
      query: request.url.query.isEmpty ? null : request.url.query,
    );

    // 复制请求头（排除某些头）
    final headers = <String, String>{};
    request.headers.forEach((key, value) {
      final lowerKey = key.toLowerCase();
      // 排除这些头，因为它们会被自动设置
      if (lowerKey != 'host' &&
          lowerKey != 'content-length' &&
          lowerKey != 'transfer-encoding') {
        headers[key] = value;
      }
    });

    // 添加/替换认证头（用真实的 API Key 替换代理临时 token）
    final apiKey = claudeConfig.effectiveApiKey;
    String? effectiveApiKey = apiKey;

    // 检查是否为代理生成的临时 token，如果是则使用真实 API Key
    if (ClaudeCodeConfigManager.isProxyToken(apiKey)) {
      effectiveApiKey = _realApiKey;
    }

    if (effectiveApiKey != null && effectiveApiKey.isNotEmpty) {
      if (effectiveAuthMode == 'bearer_only') {
        // Bearer 认证模式（用于某些中转服务）
        // 替换客户端的临时 token
        headers['authorization'] = 'Bearer $effectiveApiKey';
      } else {
        // 标准 Anthropic 认证模式
        // 移除可能的 authorization 头，使用 x-api-key
        headers.remove('authorization');
        headers['x-api-key'] = effectiveApiKey;
        if (!headers.containsKey('anthropic-version')) {
          headers['anthropic-version'] = '2023-06-01';
        }
      }
    }

    // 添加自定义头
    if (endpoint.customHeaders != null) {
      headers.addAll(endpoint.customHeaders!);
    }

    // 保存实际使用的请求头（用于日志记录）
    final actualHeaders = Map<String, String>.from(headers);

    // 获取超时配置（如果有）
    final timeoutMs = claudeConfig.env.apiTimeoutMs;
    final timeoutDuration = timeoutMs != null
        ? Duration(milliseconds: timeoutMs)
        : Duration(seconds: config.requestTimeout);

    // 发送请求到上游
    final upstreamRequest = http.Request(request.method, upstreamUrl)
      ..headers.addAll(headers)
      ..bodyBytes = bodyBytes;

    final streamedResponse = await _httpClient
        .send(upstreamRequest)
        .timeout(timeoutDuration);

    // 读取响应体
    final responseBodyBytes = await streamedResponse.stream.toBytes();

    // 复制响应头（排除会自动设置的头）
    final responseHeaders = <String, String>{};
    streamedResponse.headers.forEach((key, value) {
      final lowerKey = key.toLowerCase();
      // 排除这些头，因为它们会被 shelf 自动处理
      if (lowerKey != 'content-length' &&
          lowerKey != 'transfer-encoding' &&
          lowerKey != 'connection') {
        responseHeaders[key] = value;
      }
    });

    // 返回包装对象，包含响应和实际请求头
    return _ForwardedResponse(
      response: Response(
        streamedResponse.statusCode,
        body: responseBodyBytes,
        headers: responseHeaders,
      ),
      actualHeaders: actualHeaders,
    );
  }

  /// 选择未尝试过的端点
  Endpoint? _selectUntried(Set<String> triedEndpoints) {
    final allEndpoints = getEndpoints();

    // 获取所有启用且健康的端点
    final availableEndpoints = allEndpoints.where((endpoint) {
      return endpoint.enabled &&
          healthChecker.isHealthy(endpoint.id) &&
          !triedEndpoints.contains(endpoint.id);
    }).toList();

    if (availableEndpoints.isEmpty) {
      return null;
    }

    // 如果只有一个，直接返回
    if (availableEndpoints.length == 1) {
      return availableEndpoints.first;
    }

    // 选择响应时间最快的
    Endpoint? bestEndpoint;
    double bestAvgResponseTime = double.infinity;

    for (final endpoint in availableEndpoints) {
      final avgResponseTime = loadBalancer.getAverageResponseTime(endpoint.id);
      if (avgResponseTime < bestAvgResponseTime) {
        bestAvgResponseTime = avgResponseTime;
        bestEndpoint = endpoint;
      }
    }

    return bestEndpoint;
  }

  // =========================
  // 统计记录
  // =========================

  /// 记录成功请求
  void _recordSuccess({
    required Endpoint endpoint,
    required String path,
    required String method,
    required int statusCode,
    required int responseTime,
    Map<String, dynamic>? header,
    String? message,
    String? model,
    int? inputTokens,
    int? outputTokens,
    String? rawHeader,
    String? rawRequest,
    String? rawResponse,
  }) {
    // 记录统计
    statsCollector.recordSuccess(
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      path: path,
      method: method,
      statusCode: statusCode,
      responseTime: responseTime,
      header: header,
      message: message,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      rawHeader: rawHeader,
      rawRequest: rawRequest,
      rawResponse: rawResponse,
    );

    // 更新负载均衡器
    loadBalancer.recordResponseTime(endpoint.id, responseTime);

    // 更新健康检查器（被动检查）
    healthChecker.recordRequestSuccess(endpoint.id);
  }

  /// 记录失败请求
  void _recordFailure({
    required String endpointId,
    required String endpointName,
    required String path,
    required String method,
    required String error,
    required int startTime,
    int? statusCode,
    Map<String, dynamic>? header,
    String? message,
    String? rawHeader,
    String? rawRequest,
    String? rawResponse,
  }) {
    final responseTime = DateTime.now().millisecondsSinceEpoch - startTime;

    // 记录统计
    statsCollector.recordFailure(
      endpointId: endpointId,
      endpointName: endpointName,
      path: path,
      method: method,
      error: error,
      statusCode: statusCode,
      responseTime: responseTime,
      header: header,
      message: message,
      rawHeader: rawHeader,
      rawRequest: rawRequest,
      rawResponse: rawResponse,
    );

    // 更新健康检查器（被动检查）
    healthChecker.recordRequestFailure(endpointId, error);
  }

  /// 解析 SSE（Server-Sent Events）格式的响应
  /// 从流式响应中提取模型、token 等信息
  Map<String, dynamic> _parseSSEResponse(String sseText) {
    String? model;
    int? inputTokens;
    int? outputTokens;

    // 按行分割
    final lines = sseText.split('\n');
    String? currentEvent;
    String? currentData;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.isEmpty) {
        // 空行表示事件结束，处理当前事件
        if (currentEvent != null && currentData != null) {
          _processSSEEvent(currentEvent, currentData, (m, it, ot) {
            if (m != null) model = m;
            if (it != null) inputTokens = it;
            if (ot != null) outputTokens = ot;
          });
        }
        currentEvent = null;
        currentData = null;
      } else if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        final dataContent = line.substring(5).trim();
        if (currentData == null) {
          currentData = dataContent;
        } else {
          currentData += '\n$dataContent';
        }
      }
    }

    // 处理最后一个事件（如果没有以空行结尾）
    if (currentEvent != null && currentData != null) {
      _processSSEEvent(currentEvent, currentData, (m, it, ot) {
        if (m != null) model = m;
        if (it != null) inputTokens = it;
        if (ot != null) outputTokens = ot;
      });
    }

    return {
      'model': model,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
    };
  }

  /// 处理单个 SSE 事件
  void _processSSEEvent(
    String event,
    String data,
    void Function(String?, int?, int?) callback,
  ) {
    final jsonData = jsonDecode(data);
    if (jsonData is! Map<String, dynamic>) return;

    if (event == 'message_start') {
      // message_start 包含模型信息和初始 usage
      final message = jsonData['message'] as Map<String, dynamic>?;
      if (message != null) {
        final model = message['model'] as String?;
        final usage = message['usage'] as Map<String, dynamic>?;
        if (usage != null) {
          final inputTokens = usage['input_tokens'] as int?;
          callback(model, inputTokens, null);
        } else {
          callback(model, null, null);
        }
      }
    } else if (event == 'message_delta') {
      // message_delta 包含最终的 usage 信息（特别是 output_tokens）
      final usage = jsonData['usage'] as Map<String, dynamic>?;
      if (usage != null) {
        final outputTokens = usage['output_tokens'] as int?;
        callback(null, null, outputTokens);
      }
    }
  }

  // =========================
  // 清理资源
  // =========================

  /// 清理资源
  Future<void> dispose() async {
    await stop();
    _httpClient.close();
  }
}
