import 'dart:convert';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/proxy_server_config_entity.dart';
import 'package:code_proxy/model/request_log.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// 数据库服务
/// 使用 laconic + sqlite3 管理 SQLite 数据库
class DatabaseService {
  late Database _db;
  bool _initialized = false;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    // 获取应用文档目录
    final docDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(docDir.path, 'code_proxy.db');

    // 打开数据库
    _db = sqlite3.open(dbPath);

    // 创建表
    await _createTables();

    _initialized = true;
  }

  /// 创建数据库表
  Future<void> _createTables() async {
    // 创建端点表
    _db.execute('''
      CREATE TABLE IF NOT EXISTS endpoints (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        note TEXT,
        enabled INTEGER DEFAULT 1,
        weight INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        anthropic_auth_token TEXT,
        anthropic_base_url TEXT,
        api_timeout_ms INTEGER,
        anthropic_model TEXT,
        anthropic_small_fast_model TEXT,
        anthropic_default_haiku_model TEXT,
        anthropic_default_sonnet_model TEXT,
        anthropic_default_opus_model TEXT,
        claude_code_disable_nonessential_traffic INTEGER DEFAULT 0
      )
    ''');

    // 为已存在的表添加新列（如果缺失）
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN note TEXT');
    } catch (_) {
      // 列已存在，忽略错误
    }
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN anthropic_auth_token TEXT');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN anthropic_base_url TEXT');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN api_timeout_ms INTEGER');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN anthropic_model TEXT');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN anthropic_small_fast_model TEXT');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN anthropic_default_haiku_model TEXT');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN anthropic_default_sonnet_model TEXT');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN anthropic_default_opus_model TEXT');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN claude_code_disable_nonessential_traffic INTEGER DEFAULT 0');
    } catch (_) {}

    // 创建代理配置表
    _db.execute('''
      CREATE TABLE IF NOT EXISTS proxy_config (
        id INTEGER PRIMARY KEY,
        listen_address TEXT NOT NULL,
        listen_port INTEGER NOT NULL,
        max_retries INTEGER DEFAULT 3,
        request_timeout INTEGER DEFAULT 300,
        health_check_interval INTEGER DEFAULT 30,
        health_check_timeout INTEGER DEFAULT 10,
        health_check_path TEXT DEFAULT '/health',
        consecutive_failure_threshold INTEGER DEFAULT 3,
        enable_logging INTEGER DEFAULT 1,
        max_log_entries INTEGER DEFAULT 1000,
        response_time_window_size INTEGER DEFAULT 10
      )
    ''');

    // 创建端点统计表（可选，用于持久化统计数据）
    _db.execute('''
      CREATE TABLE IF NOT EXISTS endpoint_stats (
        endpoint_id TEXT PRIMARY KEY,
        total_requests INTEGER DEFAULT 0,
        success_requests INTEGER DEFAULT 0,
        failed_requests INTEGER DEFAULT 0,
        last_request_at INTEGER,
        FOREIGN KEY (endpoint_id) REFERENCES endpoints(id) ON DELETE CASCADE
      )
    ''');

    // 创建请求日志表
    _db.execute('''
      CREATE TABLE IF NOT EXISTS request_logs (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        endpoint_id TEXT NOT NULL,
        endpoint_name TEXT NOT NULL,
        path TEXT NOT NULL,
        method TEXT NOT NULL,
        status_code INTEGER,
        response_time INTEGER,
        success INTEGER NOT NULL,
        error TEXT,
        level TEXT NOT NULL,
        header TEXT,
        message TEXT,
        model TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        raw_header TEXT,
        raw_request TEXT,
        raw_response TEXT,
        FOREIGN KEY (endpoint_id) REFERENCES endpoints(id) ON DELETE CASCADE
      )
    ''');

    // 为日志表创建索引以提高查询性能
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_request_logs_timestamp
      ON request_logs(timestamp DESC)
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_request_logs_endpoint_id
      ON request_logs(endpoint_id)
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_request_logs_level
      ON request_logs(level)
    ''');

    // 插入默认代理配置（如果不存在）
    final configCount = _db.select(
      'SELECT COUNT(*) as count FROM proxy_config',
    );
    if (configCount.first['count'] == 0) {
      _db.execute('''
        INSERT INTO proxy_config (
          id, listen_address, listen_port, max_retries, request_timeout,
          health_check_interval, health_check_timeout, health_check_path,
          consecutive_failure_threshold, enable_logging, max_log_entries,
          response_time_window_size
        ) VALUES (1, '127.0.0.1', 9000, 3, 300, 30, 10, '/health', 3, 1, 1000, 10)
      ''');
    }
  }

  // =========================
  // 端点 CRUD 操作
  // =========================

  /// 获取所有端点
  Future<List<EndpointEntity>> getAllEndpoints() async {
    _ensureInitialized();

    final results = _db.select(
      'SELECT * FROM endpoints ORDER BY created_at ASC',
    );
    return results.map((row) => _endpointFromRow(row)).toList();
  }

  /// 根据 ID 获取端点
  Future<EndpointEntity?> getEndpointById(String id) async {
    _ensureInitialized();

    final results = _db.select('SELECT * FROM endpoints WHERE id = ?', [id]);
    if (results.isEmpty) return null;

    return _endpointFromRow(results.first);
  }

  /// 插入端点
  Future<void> insertEndpoint(EndpointEntity endpoint) async {
    _ensureInitialized();

    _db.execute(
      '''
      INSERT INTO endpoints (
        id, name, note, enabled, weight, created_at, updated_at,
        anthropic_auth_token, anthropic_base_url, api_timeout_ms,
        anthropic_model, anthropic_small_fast_model, anthropic_default_haiku_model,
        anthropic_default_sonnet_model, anthropic_default_opus_model,
        claude_code_disable_nonessential_traffic
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        endpoint.id,
        endpoint.name,
        endpoint.note,
        endpoint.enabled ? 1 : 0,
        endpoint.weight,
        endpoint.createdAt,
        endpoint.updatedAt,
        endpoint.anthropicAuthToken,
        endpoint.anthropicBaseUrl,
        endpoint.apiTimeoutMs,
        endpoint.anthropicModel,
        endpoint.anthropicSmallFastModel,
        endpoint.anthropicDefaultHaikuModel,
        endpoint.anthropicDefaultSonnetModel,
        endpoint.anthropicDefaultOpusModel,
        endpoint.claudeCodeDisableNonessentialTraffic ? 1 : 0,
      ],
    );
  }

  /// 更新端点
  Future<void> updateEndpoint(EndpointEntity endpoint) async {
    _ensureInitialized();

    _db.execute(
      '''
      UPDATE endpoints SET
        name = ?, note = ?, enabled = ?, weight = ?, updated_at = ?,
        anthropic_auth_token = ?, anthropic_base_url = ?, api_timeout_ms = ?,
        anthropic_model = ?, anthropic_small_fast_model = ?,
        anthropic_default_haiku_model = ?, anthropic_default_sonnet_model = ?,
        anthropic_default_opus_model = ?, claude_code_disable_nonessential_traffic = ?
      WHERE id = ?
      ''',
      [
        endpoint.name,
        endpoint.note,
        endpoint.enabled ? 1 : 0,
        endpoint.weight,
        endpoint.updatedAt,
        endpoint.anthropicAuthToken,
        endpoint.anthropicBaseUrl,
        endpoint.apiTimeoutMs,
        endpoint.anthropicModel,
        endpoint.anthropicSmallFastModel,
        endpoint.anthropicDefaultHaikuModel,
        endpoint.anthropicDefaultSonnetModel,
        endpoint.anthropicDefaultOpusModel,
        endpoint.claudeCodeDisableNonessentialTraffic ? 1 : 0,
        endpoint.id,
      ],
    );
  }

  /// 删除端点
  Future<void> deleteEndpoint(String id) async {
    _ensureInitialized();

    _db.execute('DELETE FROM endpoints WHERE id = ?', [id]);
  }

  /// 清空所有端点
  Future<void> clearAllEndpoints() async {
    _ensureInitialized();

    _db.execute('DELETE FROM endpoints');
  }

  // =========================
  // 代理配置操作
  // =========================

  /// 获取代理配置
  Future<ProxyServerConfigEntity> getProxyConfig() async {
    _ensureInitialized();

    final results = _db.select('SELECT * FROM proxy_config WHERE id = 1');
    if (results.isEmpty) {
      // 返回默认配置
      return const ProxyServerConfigEntity();
    }

    return _proxyConfigFromRow(results.first);
  }

  /// 保存代理配置
  Future<void> saveProxyConfig(ProxyServerConfigEntity config) async {
    _ensureInitialized();

    _db.execute(
      '''
      UPDATE proxy_config SET
        listen_address = ?, listen_port = ?, max_retries = ?,
        request_timeout = ?, health_check_interval = ?,
        health_check_timeout = ?, health_check_path = ?,
        consecutive_failure_threshold = ?, enable_logging = ?,
        max_log_entries = ?, response_time_window_size = ?
      WHERE id = 1
      ''',
      [
        config.address,
        config.port,
        config.maxRetries,
        config.requestTimeout,
        config.healthCheckInterval,
        config.healthCheckTimeout,
        config.healthCheckPath,
        config.consecutiveFailureThreshold,
        config.enableLogging ? 1 : 0,
        config.maxLogEntries,
        config.responseTimeWindowSize,
      ],
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

  /// 从数据库行创建 Endpoint 对象
  EndpointEntity _endpointFromRow(Row row) {
    return EndpointEntity(
      id: row['id'] as String,
      name: row['name'] as String,
      note: row['note'] as String?,
      enabled: (row['enabled'] as int) == 1,
      weight: row['weight'] as int,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      anthropicAuthToken: row['anthropic_auth_token'] as String?,
      anthropicBaseUrl: row['anthropic_base_url'] as String?,
      apiTimeoutMs: row['api_timeout_ms'] as int?,
      anthropicModel: row['anthropic_model'] as String?,
      anthropicSmallFastModel: row['anthropic_small_fast_model'] as String?,
      anthropicDefaultHaikuModel:
          row['anthropic_default_haiku_model'] as String?,
      anthropicDefaultSonnetModel:
          row['anthropic_default_sonnet_model'] as String?,
      anthropicDefaultOpusModel: row['anthropic_default_opus_model'] as String?,
      claudeCodeDisableNonessentialTraffic:
          (row['claude_code_disable_nonessential_traffic'] as int?) == 1,
    );
  }

  /// JSON 编码
  String _encodeJson(dynamic data) {
    return jsonEncode(data);
  }

  /// JSON 解码
  dynamic _decodeJson(String jsonStr) {
    try {
      return jsonDecode(jsonStr);
    } catch (e) {
      return {};
    }
  }

  /// 从数据库行创建 ProxyConfig 对象
  ProxyServerConfigEntity _proxyConfigFromRow(Row row) {
    return ProxyServerConfigEntity(
      address: row['listen_address'] as String,
      port: row['listen_port'] as int,
      maxRetries: row['max_retries'] as int,
      requestTimeout: row['request_timeout'] as int,
      healthCheckInterval: row['health_check_interval'] as int,
      healthCheckTimeout: row['health_check_timeout'] as int,
      healthCheckPath: row['health_check_path'] as String,
      consecutiveFailureThreshold: row['consecutive_failure_threshold'] as int,
      enableLogging: (row['enable_logging'] as int) == 1,
      maxLogEntries: row['max_log_entries'] as int,
      responseTimeWindowSize: row['response_time_window_size'] as int,
    );
  }

  // =========================
  // 请求日志操作
  // =========================

  /// 插入请求日志
  Future<void> insertRequestLog(RequestLog log) async {
    _ensureInitialized();

    // 将 Map 转换为 JSON 字符串
    final headerJson = log.header != null ? _encodeJson(log.header!) : null;

    _db.execute(
      '''
      INSERT INTO request_logs (
        id, timestamp, endpoint_id, endpoint_name, path, method,
        status_code, response_time, success, error, level,
        header, message, model, input_tokens, output_tokens,
        raw_header, raw_request, raw_response
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        log.id,
        log.timestamp,
        log.endpointId,
        log.endpointName,
        log.path,
        log.method,
        log.statusCode,
        log.responseTime,
        log.success ? 1 : 0,
        log.error,
        log.level.name,
        headerJson,
        log.message,
        log.model,
        log.inputTokens,
        log.outputTokens,
        log.rawHeader,
        log.rawRequest,
        log.rawResponse,
      ],
    );
  }

  /// 获取所有日志（分页）
  Future<List<RequestLog>> getAllRequestLogs({int? limit, int? offset}) async {
    _ensureInitialized();

    String query = 'SELECT * FROM request_logs ORDER BY timestamp DESC';

    if (limit != null) {
      query += ' LIMIT $limit';
      if (offset != null) {
        query += ' OFFSET $offset';
      }
    }

    final results = _db.select(query);
    return results.map((row) => _requestLogFromRow(row)).toList();
  }

  /// 获取日志总数
  Future<int> getRequestLogTotalCount() async {
    _ensureInitialized();
    final results = _db.select('SELECT COUNT(*) as count FROM request_logs');
    return results.first['count'] as int;
  }

  /// 获取每日请求量统计（用于趋势图）
  Future<Map<String, int>> getDailyRequestStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();

    final query = '''
      SELECT
        date(timestamp / 1000, 'unixepoch', 'localtime') as date,
        COUNT(*) as request_count
      FROM request_logs
      WHERE timestamp >= ? AND timestamp <= ?
      GROUP BY date
      ORDER BY date
    ''';

    final results = _db.select(query, [startTimestamp, endTimestamp]);

    final Map<String, int> dailyStats = {};
    for (final row in results) {
      final date = row['date'] as String;
      final count = row['request_count'] as int;
      dailyStats[date] = count;
    }

    return dailyStats;
  }

  /// 获取每日成功率统计（用于趋势图）
  Future<Map<String, double>> getDailySuccessRateStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();

    final query = '''
      SELECT
        date(timestamp / 1000, 'unixepoch', 'localtime') as date,
        SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as success_count,
        COUNT(*) as total_count
      FROM request_logs
      WHERE timestamp >= ? AND timestamp <= ?
      GROUP BY date
      ORDER BY date
    ''';

    final results = _db.select(query, [startTimestamp, endTimestamp]);

    final Map<String, double> dailyStats = {};
    for (final row in results) {
      final date = row['date'] as String;
      final success = row['success_count'] as int;
      final total = row['total_count'] as int;
      final rate = total > 0 ? (success / total) * 100.0 : 0.0;
      dailyStats[date] = rate;
    }

    return dailyStats;
  }

  /// 获取端点响应时间统计（用于饼图或柱状图）
  Future<Map<String, List<int>>> getEndpointResponseTimeStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();

    final query = '''
      SELECT
        endpoint_name,
        response_time
      FROM request_logs
      WHERE timestamp >= ? AND timestamp <= ?
        AND success = 1
        AND response_time IS NOT NULL
      ORDER BY timestamp DESC
      LIMIT 1000
    ''';

    final results = _db.select(query, [startTimestamp, endTimestamp]);

    final Map<String, List<int>> endpointStats = {};
    for (final row in results) {
      final endpointName = row['endpoint_name'] as String;
      final responseTime = row['response_time'] as int;
      endpointStats.putIfAbsent(endpointName, () => []).add(responseTime);
    }

    return endpointStats;
  }

  /// 获取按端点的Token使用统计（用于饼图）
  Future<Map<String, int>> getEndpointTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();

    final query = '''
      SELECT
        endpoint_name,
        SUM(input_tokens + output_tokens) as total_tokens
      FROM request_logs
      WHERE timestamp >= ? AND timestamp <= ?
        AND (input_tokens IS NOT NULL OR output_tokens IS NOT NULL)
      GROUP BY endpoint_name
      ORDER BY total_tokens DESC
    ''';

    final results = _db.select(query, [startTimestamp, endTimestamp]);

    final Map<String, int> endpointTokenStats = {};
    for (final row in results) {
      final endpointName = row['endpoint_name'] as String;
      final totalTokens = row['total_tokens'] as int;
      endpointTokenStats[endpointName] = totalTokens;
    }

    return endpointTokenStats;
  }

  /// 获取按模型和日期的Token使用统计（用于柱状图）
  Future<Map<String, Map<String, int>>> getModelDateTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();

    final query = '''
      SELECT
        date(timestamp / 1000, 'unixepoch', 'localtime') as date,
        COALESCE(model, 'unknown') as model,
        SUM(input_tokens + output_tokens) as total_tokens
      FROM request_logs
      WHERE timestamp >= ? AND timestamp <= ?
        AND (input_tokens IS NOT NULL OR output_tokens IS NOT NULL)
      GROUP BY date, model
      ORDER BY date, model
    ''';

    final results = _db.select(query, [startTimestamp, endTimestamp]);

    final Map<String, Map<String, int>> modelDateStats = {};
    for (final row in results) {
      final date = row['date'] as String;
      final model = row['model'] as String;
      final totalTokens = row['total_tokens'] as int;

      modelDateStats.putIfAbsent(date, () => {});
      modelDateStats[date]![model] = totalTokens;
    }

    return modelDateStats;
  }

  /// 根据端点 ID 获取日志
  Future<List<RequestLog>> getRequestLogsByEndpoint(
    String endpointId, {
    int? limit,
  }) async {
    _ensureInitialized();

    String query = '''
      SELECT * FROM request_logs
      WHERE endpoint_id = ?
      ORDER BY timestamp DESC
    ''';

    if (limit != null) {
      query += ' LIMIT $limit';
    }

    final results = _db.select(query, [endpointId]);
    return results.map((row) => _requestLogFromRow(row)).toList();
  }

  /// 根据日志级别获取日志
  Future<List<RequestLog>> getRequestLogsByLevel(
    LogLevel level, {
    int? limit,
  }) async {
    _ensureInitialized();

    String query = '''
      SELECT * FROM request_logs
      WHERE level = ?
      ORDER BY timestamp DESC
    ''';

    if (limit != null) {
      query += ' LIMIT $limit';
    }

    final results = _db.select(query, [level.name]);
    return results.map((row) => _requestLogFromRow(row)).toList();
  }

  /// 根据时间范围获取日志
  Future<List<RequestLog>> getRequestLogsByTimeRange(
    int startTimestamp,
    int endTimestamp, {
    int? limit,
  }) async {
    _ensureInitialized();

    String query = '''
      SELECT * FROM request_logs
      WHERE timestamp >= ? AND timestamp <= ?
      ORDER BY timestamp DESC
    ''';

    if (limit != null) {
      query += ' LIMIT $limit';
    }

    final results = _db.select(query, [startTimestamp, endTimestamp]);
    return results.map((row) => _requestLogFromRow(row)).toList();
  }

  /// 获取日志总数
  Future<int> getRequestLogCount() async {
    _ensureInitialized();

    final results = _db.select('SELECT COUNT(*) as count FROM request_logs');
    return results.first['count'] as int;
  }

  /// 删除指定时间之前的日志
  Future<int> deleteRequestLogsBeforeTimestamp(int timestamp) async {
    _ensureInitialized();

    final countResult = _db.select(
      'SELECT COUNT(*) as count FROM request_logs WHERE timestamp < ?',
      [timestamp],
    );
    final count = countResult.first['count'] as int;

    _db.execute('DELETE FROM request_logs WHERE timestamp < ?', [timestamp]);

    return count;
  }

  /// 清空所有日志
  Future<void> clearAllRequestLogs() async {
    _ensureInitialized();

    _db.execute('DELETE FROM request_logs');
  }

  /// 从数据库行创建 RequestLog 对象
  RequestLog _requestLogFromRow(Row row) {
    // 解析 JSON 字段
    final headerStr = row['header'] as String?;

    return RequestLog(
      id: row['id'] as String,
      timestamp: row['timestamp'] as int,
      endpointId: row['endpoint_id'] as String,
      endpointName: row['endpoint_name'] as String,
      path: row['path'] as String,
      method: row['method'] as String,
      statusCode: row['status_code'] as int?,
      responseTime: row['response_time'] as int?,
      success: (row['success'] as int) == 1,
      error: row['error'] as String?,
      level: _logLevelFromString(row['level'] as String),
      header: headerStr != null
          ? Map<String, dynamic>.from(_decodeJson(headerStr))
          : null,
      message: row['message'] as String?,
      model: row['model'] as String?,
      inputTokens: row['input_tokens'] as int?,
      outputTokens: row['output_tokens'] as int?,
      rawHeader: row['raw_header'] as String?,
      rawRequest: row['raw_request'] as String?,
      rawResponse: row['raw_response'] as String?,
    );
  }

  /// 将字符串转换为 LogLevel
  LogLevel _logLevelFromString(String value) {
    switch (value) {
      case 'info':
        return LogLevel.info;
      case 'warning':
        return LogLevel.warning;
      case 'error':
        return LogLevel.error;
      default:
        return LogLevel.info;
    }
  }

  /// 获取每日token统计（用于热度图）
  /// 返回Map，key为日期字符串（YYYY-MM-DD），value为当天的总token数
  Future<Map<String, int>> getDailyTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();

    final query = '''
      SELECT
        date(timestamp / 1000, 'unixepoch', 'localtime') as date,
        SUM(COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)) as total_tokens
      FROM request_logs
      WHERE timestamp >= ? AND timestamp <= ?
        AND success = 1
      GROUP BY date
      ORDER BY date
    ''';

    final results = _db.select(query, [startTimestamp, endTimestamp]);

    final Map<String, int> dailyStats = {};
    for (final row in results) {
      final date = row['date'] as String;
      final tokens = row['total_tokens'] as int;
      dailyStats[date] = tokens;
    }

    return dailyStats;
  }

  /// 获取每日成功请求数统计（用于热度图）
  /// 返回Map，key为日期字符串（YYYY-MM-DD），value为当天的成功请求数
  Future<Map<String, int>> getDailySuccessRequestStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    _ensureInitialized();

    final query = '''
      SELECT
        date(timestamp / 1000, 'unixepoch', 'localtime') as date,
        COUNT(*) as request_count
      FROM request_logs
      WHERE timestamp >= ? AND timestamp <= ?
        AND success = 1
      GROUP BY date
      ORDER BY date
    ''';

    final results = _db.select(query, [startTimestamp, endTimestamp]);

    final Map<String, int> dailyStats = {};
    for (final row in results) {
      final date = row['date'] as String;
      final count = row['request_count'] as int;
      dailyStats[date] = count;
    }

    return dailyStats;
  }

  /// 关闭数据库
  void dispose() {
    if (_initialized) {
      _db.dispose();
      _initialized = false;
    }
  }
}
