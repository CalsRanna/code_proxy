import 'dart:collection';
import 'package:code_proxy/model/endpoint_stats.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/services/database_service.dart';
import 'package:uuid/uuid.dart';

/// 统计收集器
/// 负责收集和管理请求统计信息和日志
class StatsCollector {
  final int maxLogEntries;
  final DatabaseService? databaseService;
  final Uuid _uuid = const Uuid();

  /// 端点统计映射 (endpointId -> EndpointStats)
  final Map<String, EndpointStats> _endpointStats = {};

  /// 请求日志环形缓冲区
  final Queue<RequestLog> _requestLogs = Queue();

  /// 全局统计
  int _totalRequests = 0;
  int _successRequests = 0;
  int _failedRequests = 0;

  StatsCollector({this.maxLogEntries = 1000, this.databaseService});

  // =========================
  // 记录请求
  // =========================

  /// 记录成功请求
  void recordSuccess({
    required String endpointId,
    required String endpointName,
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
    _recordRequest(
      endpointId: endpointId,
      endpointName: endpointName,
      path: path,
      method: method,
      statusCode: statusCode,
      responseTime: responseTime,
      success: true,
      error: null,
      level: LogLevel.info,
      header: header,
      message: message,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      rawHeader: rawHeader,
      rawRequest: rawRequest,
      rawResponse: rawResponse,
    );
  }

  /// 记录失败请求
  void recordFailure({
    required String endpointId,
    required String endpointName,
    required String path,
    required String method,
    required String error,
    int? statusCode,
    int? responseTime,
    Map<String, dynamic>? header,
    String? message,
    String? rawHeader,
    String? rawRequest,
    String? rawResponse,
  }) {
    _recordRequest(
      endpointId: endpointId,
      endpointName: endpointName,
      path: path,
      method: method,
      statusCode: statusCode,
      responseTime: responseTime,
      success: false,
      error: error,
      level: LogLevel.error,
      header: header,
      message: message,
      model: null,
      inputTokens: null,
      outputTokens: null,
      rawHeader: rawHeader,
      rawRequest: rawRequest,
      rawResponse: rawResponse,
    );
  }

  /// 内部记录请求方法
  void _recordRequest({
    required String endpointId,
    required String endpointName,
    required String path,
    required String method,
    required bool success,
    int? statusCode,
    int? responseTime,
    String? error,
    required LogLevel level,
    Map<String, dynamic>? header,
    String? message,
    String? model,
    int? inputTokens,
    int? outputTokens,
    String? rawHeader,
    String? rawRequest,
    String? rawResponse,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 更新全局统计
    _totalRequests++;
    if (success) {
      _successRequests++;
    } else {
      _failedRequests++;
    }

    // 更新端点统计（仅当有响应时间时）
    if (responseTime != null) {
      final stats = _endpointStats.putIfAbsent(
        endpointId,
        () => EndpointStats(endpointId: endpointId),
      );

      _endpointStats[endpointId] = stats.updateWithRequest(
        success: success,
        responseTime: responseTime,
        maxWindowSize: maxLogEntries,
      );
    }

    // 添加日志
    final log = RequestLog(
      id: _uuid.v4(),
      timestamp: now,
      endpointId: endpointId,
      endpointName: endpointName,
      path: path,
      method: method,
      statusCode: statusCode,
      responseTime: responseTime,
      success: success,
      error: error,
      level: level,
      header: header,
      message: message,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      rawHeader: rawHeader,
      rawRequest: rawRequest,
      rawResponse: rawResponse,
    );

    _addLog(log);

    // 将日志保存到数据库
    if (databaseService != null && databaseService!.isInitialized) {
      databaseService!.insertRequestLog(log).catchError((error) {});
    }
  }

  /// 添加日志到环形缓冲区
  void _addLog(RequestLog log) {
    _requestLogs.add(log);

    // 保持日志数量限制
    while (_requestLogs.length > maxLogEntries) {
      _requestLogs.removeFirst();
    }
  }

  // =========================
  // 获取统计信息
  // =========================

  /// 获取所有端点的统计信息
  Map<String, EndpointStats> getAllEndpointStats() {
    return Map.unmodifiable(_endpointStats);
  }

  /// 获取指定端点的统计信息
  EndpointStats? getEndpointStats(String endpointId) {
    return _endpointStats[endpointId];
  }

  /// 获取全局总请求数
  int get totalRequests => _totalRequests;

  /// 获取全局成功请求数
  int get successRequests => _successRequests;

  /// 获取全局失败请求数
  int get failedRequests => _failedRequests;

  /// 获取全局成功率 (0-100)
  double get successRate {
    if (_totalRequests == 0) return 0.0;
    return (_successRequests / _totalRequests) * 100.0;
  }

  // =========================
  // 日志管理
  // =========================

  /// 获取所有日志（从新到旧）
  List<RequestLog> getAllLogs() {
    return _requestLogs.toList().reversed.toList();
  }

  /// 获取指定端点的日志
  List<RequestLog> getLogsByEndpoint(String endpointId) {
    return _requestLogs
        .where((log) => log.endpointId == endpointId)
        .toList()
        .reversed
        .toList();
  }

  /// 获取指定级别的日志
  List<RequestLog> getLogsByLevel(LogLevel level) {
    return _requestLogs
        .where((log) => log.level == level)
        .toList()
        .reversed
        .toList();
  }

  /// 获取最近 N 条日志
  List<RequestLog> getRecentLogs(int count) {
    final logs = _requestLogs.toList().reversed.toList();
    return logs.take(count).toList();
  }

  /// 清空所有日志（内存 + 数据库）
  Future<void> clearLogs() async {
    _requestLogs.clear();

    // 同时清空数据库中的日志
    if (databaseService != null && databaseService!.isInitialized) {
      await databaseService!.clearAllRequestLogs();
    }
  }

  /// 清空指定端点的统计信息
  void clearEndpointStats(String endpointId) {
    _endpointStats.remove(endpointId);
  }

  /// 重置所有统计信息（不清空日志）
  void resetStats() {
    _endpointStats.clear();
    _totalRequests = 0;
    _successRequests = 0;
    _failedRequests = 0;
  }

  /// 重置所有数据（统计 + 日志）
  void resetAll() {
    resetStats();
    clearLogs();
  }
}
