import 'dart:async';
import 'dart:convert';

import 'package:code_proxy/model/chart_data.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/services/claude_code_config_manager.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/services/proxy_server/proxy_server_service.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';
import 'package:uuid/uuid.dart';

import 'base_view_model.dart';
import 'endpoints_view_model.dart';
import 'logs_view_model.dart';

class HomeViewModel extends BaseViewModel {
  final ClaudeCodeConfigManager _claudeCodeConfigManager;
  final RequestLogRepository _requestLogRepository;
  final SharedPreferences _prefs;

  final dailyTokenStats = signal<Map<String, int>>({});
  final chartData = signal<ChartData?>(null);

  ProxyServerService? _proxyServer;

  // SharedPreferences keys
  static const String _keyProxyAddress = 'proxy_address';
  static const String _keyProxyPort = 'proxy_port';
  static const String _keyMaxRetries = 'max_retries';

  HomeViewModel({
    required ClaudeCodeConfigManager claudeCodeConfigManager,
    required RequestLogRepository requestLogRepository,
    required SharedPreferences prefs,
  }) : _claudeCodeConfigManager = claudeCodeConfigManager,
       _requestLogRepository = requestLogRepository,
       _prefs = prefs;

  ListSignal<EndpointEntity> get endpoints => EndpointsViewModel.endpoints;

  // =========================
  // 清理资源
  // =========================

  @override
  void dispose() {
    // 停止代理服务器（异步操作，但 dispose 是同步的，所以不 await）
    _stopServer().catchError((error) {
      // 静默处理错误
    });

    // 清理所有信号
    chartData.dispose();
    dailyTokenStats.dispose();

    super.dispose();
  }

  /// 初始化
  Future<void> init() async {
    ensureNotDisposed();

    // 自动启动代理服务器
    await _autoStartServer();

    await _loadHeatmapData();
    await _loadChartData();
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

    // 注意：这里应该通过 EndpointsViewModel 来更新，但为了简单直接操作
    // 在实际应用中，应该调用 EndpointsViewModel.toggleEnabled(id)
    endpoints.value = endpoints.value.map((e) {
      return e.id == id ? updated : e;
    }).toList();

    // 更新代理服务器的端点列表（只传递已启用的端点）
    _proxyServer?.endpoints = endpoints.value.where((e) => e.enabled).toList();
  }

  /// 自动启动代理服务器
  Future<void> _autoStartServer() async {
    ensureNotDisposed();

    // 从 SharedPreferences 获取代理配置
    final address = _prefs.getString(_keyProxyAddress) ?? '127.0.0.1';
    final port = _prefs.getInt(_keyProxyPort) ?? 9000;
    final maxRetries = _prefs.getInt(_keyMaxRetries) ?? 3;

    final config = ProxyServerConfig(
      address: address,
      port: port,
      maxRetries: maxRetries,
    );

    // 更新 Claude Code 配置为代理模式
    final configUpdated = await _claudeCodeConfigManager.updateProxyConfig(
      proxyAddress: config.address,
      proxyPort: config.port,
    );

    if (!configUpdated) {
      throw Exception('无法更新 Claude Code 配置到代理模式');
    }

    // 启动代理服务器
    _proxyServer ??= ProxyServerService(
      config: config,
      onRequestCompleted: (endpoint, request, response) {
        handleRequestCompleted(
          _requestLogRepository,
          endpoint,
          request,
          response,
        );
      },
    );
    await _proxyServer?.start();
    // 只传递已启用的端点
    _proxyServer?.endpoints = endpoints.value.where((e) => e.enabled).toList();
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

      final stats = await _requestLogRepository.getDailySuccessRequestStats(
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

  /// 加载图表数据（最近7天）
  Future<void> _loadChartData() async {
    if (isDisposed) return;

    try {
      final now = DateTime.now();
      // 最近7天
      final startDate = now.subtract(const Duration(days: 7));
      final endDate = now;

      // 并行加载所有数据
      final results = await Future.wait([
        _requestLogRepository.getDailyRequestStats(
          startTimestamp: startDate.millisecondsSinceEpoch,
          endTimestamp: endDate.millisecondsSinceEpoch,
        ),
        _requestLogRepository.getEndpointTokenStats(
          startTimestamp: startDate.millisecondsSinceEpoch,
          endTimestamp: endDate.millisecondsSinceEpoch,
        ),
        _requestLogRepository.getModelDateTokenStats(
          startTimestamp: startDate.millisecondsSinceEpoch,
          endTimestamp: endDate.millisecondsSinceEpoch,
        ),
      ]);

      if (!isDisposed) {
        chartData.value = ChartData(
          dailyRequests: results[0] as Map<String, int>,
          endpointTokenUsage: results[1] as Map<String, int>,
          modelDateTokenUsage: results[2] as Map<String, Map<String, int>>,
        );
      }
    } catch (e) {
      // 静默失败，保持空数据
    }
  }

  /// 停止代理服务器
  Future<void> _stopServer() async {
    ensureNotDisposed();

    try {
      // 停止代理服务器
      await _proxyServer?.stop();
    } catch (e) {
      // 静默处理错误
    }
  }

  static void handleRequestCompleted(
    RequestLogRepository requestLogRepository,
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

      // 创建并保存日志到数据库（异步，不等待）
      final log = RequestLog(
        id: const Uuid().v4(), // 生成 UUID
        timestamp: DateTime.now().millisecondsSinceEpoch,
        endpointId: endpoint.id,
        endpointName: endpoint.name,
        path: request.path,
        method: request.method,
        statusCode: response.statusCode,
        responseTime: response.responseTime,
        success: success,
        error: success
            ? null
            : (response.statusCode > 0
                  ? 'HTTP ${response.statusCode}'
                  : response.body),
        level: success ? LogLevel.info : LogLevel.error,
        // 修复：使用请求头而不是响应头
        header: request.headers.map(
          (key, value) => MapEntry(key, value as dynamic),
        ),
        // 修复：添加消息字段
        message: success
            ? 'Request completed successfully'
            : 'Request failed with status ${response.statusCode}',
        model: model,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        rawHeader: jsonEncode(request.headers),
        rawRequest: request.body,
        rawResponse: response.body,
      );

      // 异步保存到数据库，成功后触发刷新信号
      requestLogRepository
          .insert(log)
          .then((_) {
            // 插入成功后，通知 LogsViewModel 刷新
            final logViewModel = GetIt.instance.get<LogsViewModel>();
            logViewModel.loadLogs();
          })
          .catchError((error) {
            // 静默处理错误
          });
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
