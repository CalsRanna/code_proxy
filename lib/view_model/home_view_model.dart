import 'dart:async';
import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/model/health_status.dart';
import 'package:code_proxy/model/proxy_server_state.dart';
import 'package:code_proxy/services/claude_code_config_manager.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:code_proxy/services/database_service.dart';
import 'package:code_proxy/services/health_checker.dart';
import 'package:code_proxy/services/proxy_server.dart';
import 'package:code_proxy/services/stats_collector.dart';
import 'package:signals/signals.dart';
import 'base_view_model.dart';

/// 主页 ViewModel
/// 管理代理服务器状态和端点列表
class HomeViewModel extends BaseViewModel {
  final ProxyServer _proxyServer;
  final HealthChecker _healthChecker;
  final StatsCollector _statsCollector;
  final ConfigManager _configManager;
  final ClaudeCodeConfigManager _claudeCodeConfigManager;
  final DatabaseService _databaseService;

  /// 响应式状态
  final isServerRunning = signal(false);
  final serverState = signal(const ProxyServerState());
  final healthStatuses = signal<Map<String, HealthStatus>>({});
  final dailyTokenStats = signal<Map<String, int>>({});

  /// 端点列表（使用 ConfigManager 的全局 signal）
  ListSignal<Endpoint> get endpoints => _configManager.endpoints;

  /// 状态更新定时器
  Timer? _statusUpdateTimer;

  HomeViewModel({
    required ProxyServer proxyServer,
    required HealthChecker healthChecker,
    required StatsCollector statsCollector,
    required ConfigManager configManager,
    required ClaudeCodeConfigManager claudeCodeConfigManager,
    required DatabaseService databaseService,
  }) : _proxyServer = proxyServer,
       _healthChecker = healthChecker,
       _statsCollector = statsCollector,
       _configManager = configManager,
       _claudeCodeConfigManager = claudeCodeConfigManager,
       _databaseService = databaseService;

  /// 初始化
  Future<void> init() async {
    ensureNotDisposed();

    // 检测服务器是否已运行
    final isRunning = _proxyServer.isRunning;
    if (isRunning) {
      // 如果服务器已运行，更新按钮状态
      isServerRunning.value = true;
      _updateServerState();
    } else {
      // 如果服务器未运行，自动启动
      try {
        await startServer();
      } catch (e) {
        // 如果自动启动失败，静默处理，用户可以手动启动
      }
    }

    _startStatusUpdates();
    await _loadHeatmapData();
  }

  // =========================
  // 服务器控制
  // =========================

  /// 启动代理服务器
  Future<void> startServer() async {
    ensureNotDisposed();

    try {
      // 获取代理配置
      final config = await _configManager.loadProxyConfig();

      // 1. 切换 Claude Code 配置到代理模式
      final configSwitched = await _claudeCodeConfigManager.switchToProxy(
        proxyAddress: config.listenAddress,
        proxyPort: config.listenPort,
      );

      if (!configSwitched) {
        throw Exception('无法切换 Claude Code 配置到代理模式');
      }

      // 2. 启动代理服务器
      await _proxyServer.start();
      isServerRunning.value = true;
      _updateServerState();
    } catch (e) {
      // 如果启动失败，尝试恢复配置
      await _claudeCodeConfigManager.switchFromProxy();
      rethrow;
    }
  }

  /// 停止代理服务器
  Future<void> stopServer() async {
    ensureNotDisposed();

    try {
      // 1. 停止代理服务器
      await _proxyServer.stop();
      isServerRunning.value = false;
      _updateServerState();

      // 2. 恢复 Claude Code 原始配置
      final configRestored = await _claudeCodeConfigManager.switchFromProxy();

      if (!configRestored) {
      } else {}
    } catch (e) {
      // 即使停止失败，也尝试恢复配置
      await _claudeCodeConfigManager.switchFromProxy();
      rethrow;
    }
  }

  // =========================
  // 端点管理
  // =========================

  /// 切换端点启用状态
  Future<void> toggleEndpointEnabled(String id) async {
    ensureNotDisposed();

    final endpoint = endpoints.value.firstWhere((e) => e.id == id);
    final updated = Endpoint(
      id: endpoint.id,
      name: endpoint.name,
      url: endpoint.url,
      category: endpoint.category,
      notes: endpoint.notes,
      icon: endpoint.icon,
      iconColor: endpoint.iconColor,
      weight: endpoint.weight,
      enabled: !endpoint.enabled,
      sortIndex: endpoint.sortIndex,
      createdAt: endpoint.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    // 使用 ConfigManager 保存，它会自动更新全局 signal
    await _configManager.saveEndpoint(updated);
  }

  // =========================
  // 状态更新
  // =========================

  /// 加载热度图数据（最近52周）
  Future<void> _loadHeatmapData() async {
    if (isDisposed) return;

    try {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 52 * 7));

      final stats = await _databaseService.getDailySuccessRequestStats(
        startTimestamp: startDate.millisecondsSinceEpoch,
        endTimestamp: now.millisecondsSinceEpoch,
      );

      if (!isDisposed) {
        dailyTokenStats.value = stats;
      }
    } catch (e) {
      // 静默失败，保持空数据
    }
  }

  /// 启动状态定时更新（每 2 秒）
  void _startStatusUpdates() {
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        _updateServerState();
        // 每分钟更新一次热度图数据
        if (DateTime.now().second == 0) {
          _loadHeatmapData();
        }
      },
    );
  }

  /// 更新服务器状态
  void _updateServerState() {
    if (isDisposed) return;

    final running = _proxyServer.isRunning;
    final startedAt = _proxyServer.startedAt;
    final uptimeSeconds = startedAt != null
        ? ((DateTime.now().millisecondsSinceEpoch - startedAt) / 1000).floor()
        : 0;

    final totalRequests = _statsCollector.totalRequests;
    final successRequests = _statsCollector.successRequests;
    final failedRequests = _statsCollector.failedRequests;
    final successRate = _statsCollector.successRate;

    serverState.value = ProxyServerState(
      running: running,
      listenAddress: running ? '127.0.0.1' : null,
      listenPort: running ? 7890 : null,
      startedAt: startedAt,
      uptimeSeconds: uptimeSeconds,
      totalRequests: totalRequests,
      successRequests: successRequests,
      failedRequests: failedRequests,
      successRate: successRate,
      activeConnections: _proxyServer.activeConnections,
    );

    // 更新健康状态
    healthStatuses.value = _healthChecker.getAllHealthStatuses();
  }

  // =========================
  // 清理资源
  // =========================

  @override
  void dispose() {
    _statusUpdateTimer?.cancel();
    super.dispose();
  }
}
