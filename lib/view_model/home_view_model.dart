import 'dart:async';
import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/model/proxy_server_state.dart';
import 'package:code_proxy/services/claude_code_config_manager.dart';
import 'package:code_proxy/services/config_manager.dart';
import 'package:code_proxy/services/database_service.dart';
import 'package:code_proxy/services/proxy_server.dart';
import 'package:code_proxy/services/stats_collector.dart';
import 'package:signals/signals.dart';
import 'base_view_model.dart';

/// 主页 ViewModel
/// 管理代理服务器状态和端点列表
class HomeViewModel extends BaseViewModel {
  final ProxyServer _proxyServer;
  final StatsCollector _statsCollector;
  final ConfigManager _configManager;
  final ClaudeCodeConfigManager _claudeCodeConfigManager;
  final DatabaseService _databaseService;

  /// 响应式状态
  final isServerRunning = signal(false);
  final serverState = signal(const ProxyServerState());
  final dailyTokenStats = signal<Map<String, int>>({});

  /// 端点列表（使用 ConfigManager 的全局 signal）
  ListSignal<Endpoint> get endpoints => _configManager.endpoints;

  /// 状态更新定时器
  Timer? _statusUpdateTimer;

  HomeViewModel({
    required ProxyServer proxyServer,
    required StatsCollector statsCollector,
    required ConfigManager configManager,
    required ClaudeCodeConfigManager claudeCodeConfigManager,
    required DatabaseService databaseService,
  }) : _proxyServer = proxyServer,
       _statsCollector = statsCollector,
       _configManager = configManager,
       _claudeCodeConfigManager = claudeCodeConfigManager,
       _databaseService = databaseService;

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

  /// 自动启动代理服务器
  Future<void> _autoStartServer() async {
    ensureNotDisposed();

    try {
      // 获取代理配置
      final config = await _configManager.loadProxyConfig();

      // 检查当前配置是否已经指向代理服务器
      final isAlreadyPointingToProxy = await _claudeCodeConfigManager.isPointingToProxy(
        proxyAddress: config.listenAddress,
        proxyPort: config.listenPort,
      );

      if (!isAlreadyPointingToProxy) {
        // 如果当前配置不指向代理，切换配置
        final configSwitched = await _claudeCodeConfigManager.switchToProxy(
          proxyAddress: config.listenAddress,
          proxyPort: config.listenPort,
        );

        if (!configSwitched) {
          throw Exception('无法切换 Claude Code 配置到代理模式');
        }
      }

      // 启动代理服务器
      await _proxyServer.start();
      isServerRunning.value = true;
      _updateServerState();
    } catch (e) {
      // 启动失败，确保服务器处于停止状态
      isServerRunning.value = false;
      rethrow;
    }
  }

  /// 停止代理服务器
  Future<void> _stopServer() async {
    ensureNotDisposed();

    try {
      // 停止代理服务器
      await _proxyServer.stop();
      isServerRunning.value = false;
      _updateServerState();

      // 恢复 Claude Code 原始配置（如果有备份）
      await _claudeCodeConfigManager.switchFromProxy();
    } catch (e) {
      // 即使停止失败，也尝试恢复配置
      await _claudeCodeConfigManager.switchFromProxy();
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
  }

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
}
