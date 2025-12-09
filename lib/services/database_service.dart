import 'dart:convert';
import 'package:code_proxy/model/endpoint.dart';
import 'package:code_proxy/model/proxy_config.dart';
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
        url TEXT NOT NULL,
        category TEXT NOT NULL,
        notes TEXT,
        icon TEXT,
        icon_color TEXT,
        weight INTEGER DEFAULT 1,
        enabled INTEGER DEFAULT 1,
        sort_index INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        api_key TEXT,
        auth_mode TEXT DEFAULT 'standard',
        custom_headers TEXT,
        settings_config TEXT
      )
    ''');

    // 为已存在的表添加新列（如果缺失）
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN api_key TEXT');
    } catch (_) {
      // 列已存在，忽略错误
    }
    try {
      _db.execute(
        'ALTER TABLE endpoints ADD COLUMN auth_mode TEXT DEFAULT \'standard\'',
      );
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN custom_headers TEXT');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE endpoints ADD COLUMN settings_config TEXT');
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
        ) VALUES (1, '127.0.0.1', 7890, 3, 300, 30, 10, '/health', 3, 1, 1000, 10)
      ''');
    }
  }

  // =========================
  // 端点 CRUD 操作
  // =========================

  /// 获取所有端点
  Future<List<Endpoint>> getAllEndpoints() async {
    _ensureInitialized();

    final results = _db.select(
      'SELECT * FROM endpoints ORDER BY sort_index ASC',
    );
    return results.map((row) => _endpointFromRow(row)).toList();
  }

  /// 根据 ID 获取端点
  Future<Endpoint?> getEndpointById(String id) async {
    _ensureInitialized();

    final results = _db.select('SELECT * FROM endpoints WHERE id = ?', [id]);
    if (results.isEmpty) return null;

    return _endpointFromRow(results.first);
  }

  /// 插入端点
  Future<void> insertEndpoint(Endpoint endpoint) async {
    _ensureInitialized();

    // 将 Map 和 List 转换为 JSON 字符串
    final customHeadersJson = endpoint.customHeaders != null
        ? _encodeJson(endpoint.customHeaders!)
        : null;
    final settingsConfigJson = endpoint.settingsConfig != null
        ? _encodeJson(endpoint.settingsConfig!)
        : null;

    _db.execute(
      '''
      INSERT INTO endpoints (
        id, name, url, category, notes, icon, icon_color,
        weight, enabled, sort_index, created_at, updated_at,
        api_key, auth_mode, custom_headers, settings_config
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        endpoint.id,
        endpoint.name,
        endpoint.url,
        endpoint.category,
        endpoint.notes,
        endpoint.icon,
        endpoint.iconColor,
        endpoint.weight,
        endpoint.enabled ? 1 : 0,
        endpoint.sortIndex,
        endpoint.createdAt,
        endpoint.updatedAt,
        endpoint.apiKey,
        endpoint.authMode,
        customHeadersJson,
        settingsConfigJson,
      ],
    );
  }

  /// 更新端点
  Future<void> updateEndpoint(Endpoint endpoint) async {
    _ensureInitialized();

    // 将 Map 和 List 转换为 JSON 字符串
    final customHeadersJson = endpoint.customHeaders != null
        ? _encodeJson(endpoint.customHeaders!)
        : null;
    final settingsConfigJson = endpoint.settingsConfig != null
        ? _encodeJson(endpoint.settingsConfig!)
        : null;

    _db.execute(
      '''
      UPDATE endpoints SET
        name = ?, url = ?, category = ?, notes = ?, icon = ?,
        icon_color = ?, weight = ?, enabled = ?, sort_index = ?,
        updated_at = ?, api_key = ?, auth_mode = ?, custom_headers = ?,
        settings_config = ?
      WHERE id = ?
      ''',
      [
        endpoint.name,
        endpoint.url,
        endpoint.category,
        endpoint.notes,
        endpoint.icon,
        endpoint.iconColor,
        endpoint.weight,
        endpoint.enabled ? 1 : 0,
        endpoint.sortIndex,
        endpoint.updatedAt,
        endpoint.apiKey,
        endpoint.authMode,
        customHeadersJson,
        settingsConfigJson,
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
  Future<ProxyConfig> getProxyConfig() async {
    _ensureInitialized();

    final results = _db.select('SELECT * FROM proxy_config WHERE id = 1');
    if (results.isEmpty) {
      // 返回默认配置
      return const ProxyConfig();
    }

    return _proxyConfigFromRow(results.first);
  }

  /// 保存代理配置
  Future<void> saveProxyConfig(ProxyConfig config) async {
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
        config.listenAddress,
        config.listenPort,
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
  Endpoint _endpointFromRow(Row row) {
    // 解析 JSON 字段
    final customHeadersStr = row['custom_headers'] as String?;
    final settingsConfigStr = row['settings_config'] as String?;

    return Endpoint(
      id: row['id'] as String,
      name: row['name'] as String,
      url: row['url'] as String,
      category: row['category'] as String,
      notes: row['notes'] as String?,
      icon: row['icon'] as String?,
      iconColor: row['icon_color'] as String?,
      weight: row['weight'] as int,
      enabled: (row['enabled'] as int) == 1,
      sortIndex: row['sort_index'] as int,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      apiKey: row['api_key'] as String?,
      authMode: row['auth_mode'] as String? ?? 'standard',
      customHeaders: customHeadersStr != null
          ? Map<String, String>.from(_decodeJson(customHeadersStr))
          : null,
      settingsConfig: settingsConfigStr != null
          ? Map<String, dynamic>.from(_decodeJson(settingsConfigStr))
          : null,
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
  ProxyConfig _proxyConfigFromRow(Row row) {
    return ProxyConfig(
      listenAddress: row['listen_address'] as String,
      listenPort: row['listen_port'] as int,
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
