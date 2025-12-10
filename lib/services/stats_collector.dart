import 'package:code_proxy/model/endpoint_stats.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/services/database_service.dart';

/// 统计收集器
/// 负责收集和管理请求统计信息（不再缓存日志）
class StatsCollector {
  final DatabaseService? databaseService;

  /// 端点统计映射 (endpointId -> EndpointStats)
  final Map<String, EndpointStats> _endpointStats = {};

  /// 全局统计
  int _totalRequests = 0;
  int _successRequests = 0;
  int _failedRequests = 0;

  StatsCollector({this.databaseService});

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
      header: header,
      message: message,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
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
    String? model,
    int? inputTokens,
    int? outputTokens,
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
      header: header,
      message: message,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }

  /// 内部记录请求方法（只更新统计，不缓存日志）
  void _recordRequest({
    required String endpointId,
    required String endpointName,
    required String path,
    required String method,
    required bool success,
    int? statusCode,
    int? responseTime,
    String? error,
    Map<String, dynamic>? header,
    String? message,
    String? model,
    int? inputTokens,
    int? outputTokens,
  }) {
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
        maxWindowSize: 100, // 固定窗口大小用于统计
      );
    }

    // 创建日志对象并保存到数据库（不缓存到内存）
    final log = RequestLog(
      id: '', // 不需要ID，由数据库生成
      timestamp: DateTime.now().millisecondsSinceEpoch,
      endpointId: endpointId,
      endpointName: endpointName,
      path: path,
      method: method,
      statusCode: statusCode,
      responseTime: responseTime,
      success: success,
      error: error,
      level: success ? LogLevel.info : LogLevel.error,
      header: header,
      message: message,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      rawHeader: null, // 不缓存到内存
      rawRequest: null,
      rawResponse: null,
    );

    // 将日志保存到数据库（异步，不等待）
    if (databaseService != null && databaseService!.isInitialized) {
      databaseService!.insertRequestLog(log).catchError((error) {});
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
  // 统计操作
  // =========================

  /// 清空指定端点的统计信息
  void clearEndpointStats(String endpointId) {
    _endpointStats.remove(endpointId);
  }

  /// 重置所有统计信息
  void resetStats() {
    _endpointStats.clear();
    _totalRequests = 0;
    _successRequests = 0;
    _failedRequests = 0;
  }
}
