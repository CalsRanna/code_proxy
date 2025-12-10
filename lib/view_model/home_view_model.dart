import 'dart:async';
import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/proxy_server_state.dart';
import 'package:code_proxy/services/claude_code_config_manager.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:code_proxy/services/database_service.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_service.dart';
import 'package:code_proxy/services/stats_collector.dart';
import 'package:signals/signals.dart';

import 'base_view_model.dart';
import 'endpoints_view_model.dart';

class HomeViewModel extends BaseViewModel {
  final StatsCollector _statsCollector;
  final ConfigManager _configManager;
  final ClaudeCodeConfigManager _claudeCodeConfigManager;
  final DatabaseService _databaseService;

  final serverState = signal(const ProxyServerState());
  final dailyTokenStats = signal<Map<String, int>>({});

  /// 状态更新定时器
  Timer? _statusUpdateTimer;

  ProxyServerService? _proxyServer;

  HomeViewModel({
    required StatsCollector statsCollector,
    required ConfigManager configManager,
    required ClaudeCodeConfigManager claudeCodeConfigManager,
    required DatabaseService databaseService,
  }) : _statsCollector = statsCollector,
       _configManager = configManager,
       _claudeCodeConfigManager = claudeCodeConfigManager,
       _databaseService = databaseService;

  ListSignal<EndpointEntity> get endpoints => EndpointsViewModel.endpoints;

  // =========================
  // 清理资源
  // =========================

  @override
  void dispose() {
    _statusUpdateTimer?.cancel();
    // 停止代理服务器（异步操作，但 dispose 是同步的，所以不 await）
    _stopServer().catchError((error) {
      // 静默处理错误
    });
    super.dispose();
  }

  /// 初始化
  Future<void> init() async {
    ensureNotDisposed();

    // 自动启动代理服务器
    await _autoStartServer();

    _startStatusUpdates();
    await _loadHeatmapData();
  }

  // =========================
  // 服务器控制
  // =========================

  /// 切换端点启用状态
  Future<void> toggleEndpointEnabled(String id) async {
    ensureNotDisposed();

    final endpoint = endpoints.value.firstWhere((e) => e.id == id);
    final updated = endpoint.copyWith(
      enabled: !endpoint.enabled,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    // 使用 ConfigManager 保存，它会自动更新全局 signal
    await _configManager.saveEndpoint(updated);
  }

  /// 自动启动代理服务器
  Future<void> _autoStartServer() async {
    ensureNotDisposed();

    // 获取代理配置
    final config = await _configManager.loadProxyConfig();

    // 检查当前配置是否已经指向代理服务器
    final isAlreadyPointingToProxy = await _claudeCodeConfigManager
        .isPointingToProxy(proxyAddress: config.address, proxyPort: 9000);

    if (!isAlreadyPointingToProxy) {
      // 如果当前配置不指向代理，切换配置
      final configSwitched = await _claudeCodeConfigManager.switchToProxy(
        proxyAddress: config.address,
        proxyPort: config.port,
      );

      if (!configSwitched) {
        throw Exception('无法切换 Claude Code 配置到代理模式');
      }
    }

    // 启动代理服务器
    _proxyServer ??= ProxyServerService(
      config: config,
      onRequestCompleted: (endpoint, request, response) {
        handleRequestCompleted(_statsCollector, endpoint, request, response);
      },
    );
    await _proxyServer?.start();
    _proxyServer?.endpoints = endpoints.value;
    _updateServerState();
  }

  // =========================
  // 端点管理
  // =========================

  /// 加载热度图数据（全年数据：从今年1月1日到12月31日）
  Future<void> _loadHeatmapData() async {
    if (isDisposed) return;

    try {
      final now = DateTime.now();
      // 从今年1月1日开始
      final startDate = DateTime(now.year, 1, 1);
      // 到今年12月31日结束
      final endDate = DateTime(now.year, 12, 31);

      final stats = await _databaseService.getDailySuccessRequestStats(
        startTimestamp: startDate.millisecondsSinceEpoch,
        endTimestamp: endDate.millisecondsSinceEpoch,
      );

      if (!isDisposed) {
        dailyTokenStats.value = stats;
      }
    } catch (e) {
      // 静默失败，保持空数据
    }
  }

  // =========================
  // 状态更新
  // =========================

  /// 启动状态定时更新（每 2 秒）
  void _startStatusUpdates() {
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _updateServerState();
      // 每分钟更新一次热度图数据
      if (DateTime.now().second == 0) {
        _loadHeatmapData();
      }
    });
  }

  /// 停止代理服务器
  Future<void> _stopServer() async {
    ensureNotDisposed();

    try {
      // 停止代理服务器
      await _proxyServer?.stop();
      _updateServerState();

      // 恢复 Claude Code 原始配置（如果有备份）
      await _claudeCodeConfigManager.switchFromProxy();
    } catch (e) {
      // 即使停止失败，也尝试恢复配置
      await _claudeCodeConfigManager.switchFromProxy();
    }
  }

  /// 更新服务器状态
  void _updateServerState() {
    if (isDisposed) return;

    final totalRequests = _statsCollector.totalRequests;
    final successRequests = _statsCollector.successRequests;
    final failedRequests = _statsCollector.failedRequests;
    final successRate = _statsCollector.successRate;

    serverState.value = ProxyServerState(
      listenAddress: '127.0.0.1',
      listenPort: 9000,
      totalRequests: totalRequests,
      successRequests: successRequests,
      failedRequests: failedRequests,
      successRate: successRate,
    );
  }

  static void handleRequestCompleted(
    StatsCollector statsCollector,
    EndpointEntity endpoint,
    ProxyServerRequest request,
    ProxyServerResponse response,
  ) {
    try {
      final success = response.statusCode >= 200 && response.statusCode < 300;
      String? model;
      int? inputTokens;
      int? outputTokens;

      // 从请求中解析 model（更可靠）
      if (request.body.isNotEmpty) {
        try {
          final requestJson = jsonDecode(request.body);
          if (requestJson is Map<String, dynamic>) {
            model = requestJson['model'] as String?;
          }
        } catch (_) {
          // 解析失败，忽略
        }
      }

      // 检测是否是 SSE 响应
      final contentType = response.headers['content-type'] ?? '';
      final isSSE = contentType.contains('text/event-stream');

      // 从响应中解析 token 信息
      if (success && response.body.isNotEmpty) {
        try {
          if (isSSE) {
            // SSE 格式：解析多个 data: {...} 块
            final tokens = _parseSSETokens(response.body);
            inputTokens = tokens['input'];
            outputTokens = tokens['output'];
          } else {
            // 普通 JSON 格式
            final responseJson = jsonDecode(response.body);
            if (responseJson is Map<String, dynamic>) {
              // 提取 usage 信息
              final usage = responseJson['usage'];
              if (usage is Map<String, dynamic>) {
                inputTokens = usage['input_tokens'] as int?;
                outputTokens = usage['output_tokens'] as int?;
              }
            }
          }
        } catch (_) {
          // 解析失败，忽略
        }
      }

      // 记录请求到 StatsCollector
      if (success) {
        statsCollector.recordSuccess(
          endpointId: endpoint.id,
          endpointName: endpoint.name,
          path: request.path,
          method: request.method,
          statusCode: response.statusCode,
          responseTime: response.responseTime,
          header: Map<String, dynamic>.from(response.headers),
          model: model,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          rawHeader: response.headers.toString(),
          rawRequest: request.body,
          rawResponse: response.body,
        );
      } else {
        statsCollector.recordFailure(
          endpointId: endpoint.id,
          endpointName: endpoint.name,
          path: request.path,
          method: request.method,
          statusCode: response.statusCode,
          responseTime: response.responseTime,
          error: response.statusCode > 0
              ? 'HTTP ${response.statusCode}'
              : response.body,
          header: Map<String, dynamic>.from(response.headers),
          model: model,
          inputTokens: inputTokens,
          outputTokens: outputTokens,
          rawHeader: response.headers.toString(),
          rawRequest: request.body,
          rawResponse: response.body,
        );
      }
    } catch (e) {
      // 记录失败，静默处理
    }
  }

  /// 解析 SSE 格式的响应，提取 Token 信息
  /// SSE 格式示例（Anthropic API）：
  /// data: {"type":"content_block_delta","delta":{"text":"Hello"},"usage":{"input_tokens":10}}
  /// data: {"type":"message_stop","usage":{"output_tokens":20}}
  static Map<String, dynamic> _parseSSETokens(String sseBody) {
    int totalInput = 0;
    int totalOutput = 0;

    // 解析 SSE 格式：data: {...}
    final lines = sseBody.split('\n');
    for (var line in lines) {
      if (line.startsWith('data: ')) {
        try {
          final jsonStr = line.substring(6).trim(); // 移除 "data: "

          // 跳过特殊标记（如 [DONE]）
          if (jsonStr.isEmpty || jsonStr == '[DONE]') {
            continue;
          }

          final json = jsonDecode(jsonStr);

          if (json is Map<String, dynamic>) {
            // 提取并累加 tokens (Anthropic API 格式)
            final usage = json['usage'];
            if (usage is Map<String, dynamic>) {
              totalInput += (usage['input_tokens'] as int? ?? 0);
              totalOutput += (usage['output_tokens'] as int? ?? 0);
            }
          }
        } catch (_) {
          // 解析失败，跳过这一行
        }
      }
    }

    return {
      'input': totalInput > 0 ? totalInput : null,
      'output': totalOutput > 0 ? totalOutput : null,
    };
  }
}
