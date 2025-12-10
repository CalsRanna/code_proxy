import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/proxy_server_config_entity.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:code_proxy/repository/proxy_config_repository.dart';
import 'package:code_proxy/repository/request_log_repository.dart';

/// 数据库服务（包装仓库层以保持向后兼容）
///
/// 内部使用 Repository 模式，提供统一的数据库操作接口
class DatabaseService {
  final EndpointRepository _endpointRepository;
  final ProxyConfigRepository _proxyConfigRepository;
  final RequestLogRepository _requestLogRepository;

  bool _initialized = false;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  DatabaseService({
    required EndpointRepository endpointRepository,
    required ProxyConfigRepository proxyConfigRepository,
    required RequestLogRepository requestLogRepository,
  })
      : _endpointRepository = endpointRepository,
        _proxyConfigRepository = proxyConfigRepository,
        _requestLogRepository = requestLogRepository;

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
  }

  // =========================
  // 端点 CRUD 操作
  // =========================

  /// 获取所有端点
  Future<List<EndpointEntity>> getAllEndpoints() async {
    _ensureInitialized();
    return await _endpointRepository.getAll();
  }

  /// 根据 ID 获取端点
  Future<EndpointEntity?> getEndpointById(String id) async {
    _ensureInitialized();
    return await _endpointRepository.getById(id);
  }

  /// 插入端点
  Future<void> insertEndpoint(EndpointEntity endpoint) async {
    _ensureInitialized();
    await _endpointRepository.insert(endpoint);
  }

  /// 更新端点
  Future<void> updateEndpoint(EndpointEntity endpoint) async {
    _ensureInitialized();
    await _endpointRepository.update(endpoint);
  }

  /// 删除端点
  Future<void> deleteEndpoint(String id) async {
    _ensureInitialized();
    await _endpointRepository.delete(id);
  }

  /// 清空所有端点
  Future<void> clearAllEndpoints() async {
    _ensureInitialized();
    await _endpointRepository.clearAll();
  }

  // =========================
  // 代理配置操作
  // =========================

  /// 获取代理配置
  Future<ProxyServerConfigEntity> getProxyConfig() async {
    _ensureInitialized();
    return await _proxyConfigRepository.get();
  }

  /// 保存代理配置
  Future<void> saveProxyConfig(ProxyServerConfigEntity config) async {
    _ensureInitialized();
    await _proxyConfigRepository.save(config);
  }

  // =========================
  // 请求日志操作
  // =========================

  /// 插入请求日志
  Future<void> insertRequestLog(RequestLog log) async {
    _ensureInitialized();
    await _requestLogRepository.insert(log);
  }

  /// 获取所有日志（分页）
  Future<List<RequestLog>> getAllRequestLogs({int? limit, int? offset}) async {
    _ensureInitialized();
    return await _requestLogRepository.getAll(limit: limit, offset: offset);
  }

  /// 获取日志总数
  Future<int> getRequestLogTotalCount() async {
    _ensureInitialized();
    return await _requestLogRepository.getTotalCount();
  }

  /// 获取每日请求量统计（用于趋势图）
  Future<Map<String, int>> getDailyRequestStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();
    return await _requestLogRepository.getDailyRequestStats(
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
    );
  }

  /// 获取每日成功率统计（用于趋势图）
  Future<Map<String, double>> getDailySuccessRateStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();
    return await _requestLogRepository.getDailySuccessRateStats(
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
    );
  }

  /// 获取端点响应时间统计（用于饼图或柱状图）
  Future<Map<String, List<int>>> getEndpointResponseTimeStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();
    return await _requestLogRepository.getEndpointResponseTimeStats(
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
    );
  }

  /// 获取按端点的Token使用统计（用于饼图）
  Future<Map<String, int>> getEndpointTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();
    return await _requestLogRepository.getEndpointTokenStats(
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
    );
  }

  /// 获取按模型和日期的Token使用统计（用于柱状图）
  Future<Map<String, Map<String, int>>> getModelDateTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();
    return await _requestLogRepository.getModelDateTokenStats(
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
    );
  }

  /// 根据端点 ID 获取日志
  Future<List<RequestLog>> getRequestLogsByEndpoint(
    String endpointId, {
    int? limit,
  }) async {
    _ensureInitialized();
    return await _requestLogRepository.getByEndpoint(endpointId, limit: limit);
  }

  /// 根据日志级别获取日志
  Future<List<RequestLog>> getRequestLogsByLevel(
    LogLevel level, {
    int? limit,
  }) async {
    _ensureInitialized();
    return await _requestLogRepository.getByLevel(level, limit: limit);
  }

  /// 根据时间范围获取日志
  Future<List<RequestLog>> getRequestLogsByTimeRange(
    int startTimestamp,
    int endTimestamp, {
    int? limit,
  }) async {
    _ensureInitialized();
    return await _requestLogRepository.getByTimeRange(
      startTimestamp,
      endTimestamp,
      limit: limit,
    );
  }

  /// 获取日志总数
  Future<int> getRequestLogCount() async {
    _ensureInitialized();
    return await _requestLogRepository.getTotalCount();
  }

  /// 删除指定时间之前的日志
  Future<int> deleteRequestLogsBeforeTimestamp(int timestamp) async {
    _ensureInitialized();
    return await _requestLogRepository.deleteBeforeTimestamp(timestamp);
  }

  /// 清空所有日志
  Future<void> clearAllRequestLogs() async {
    _ensureInitialized();
    await _requestLogRepository.clearAll();
  }

  /// 获取每日token统计（用于热度图）
  Future<Map<String, int>> getDailyTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();
    return await _requestLogRepository.getDailyTokenStats(
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
    );
  }

  /// 获取每日成功请求数统计（用于热度图）
  Future<Map<String, int>> getDailySuccessRequestStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();
    return await _requestLogRepository.getDailySuccessRequestStats(
      startTimestamp: startTimestamp,
      endTimestamp: endTimestamp,
    );
  }

  // =========================
  // 辅助方法
  // =========================

  /// 确保数据库已初始化
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('DatabaseService not initialized. Call init() first.');
    }
  }

  /// 关闭数据库
  void dispose() {
    if (_initialized) {
      _initialized = false;
    }
  }
}
