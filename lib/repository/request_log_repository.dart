import 'dart:convert';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/request_log.dart';

/// Request Log Repository
///
/// Handles CRUD operations for request logs and statistics
class RequestLogRepository {
  final Database _database;

  RequestLogRepository(this._database);

  /// Insert a new request log
  Future<void> insert(RequestLog log) async {
    final headerJson = log.header != null ? jsonEncode(log.header!) : null;

    await _database.laconic.table('request_logs').insert([
      {
        'id': log.id,
        'timestamp': log.timestamp,
        'endpoint_id': log.endpointId,
        'endpoint_name': log.endpointName,
        'path': log.path,
        'method': log.method,
        'status_code': log.statusCode,
        'response_time': log.responseTime,
        'success': log.success ? 1 : 0,
        'error': log.error,
        'level': log.level.name,
        'header': headerJson,
        'message': log.message,
        'model': log.model,
        'input_tokens': log.inputTokens,
        'output_tokens': log.outputTokens,
        'raw_header': log.rawHeader,
        'raw_request': log.rawRequest,
        'raw_response': log.rawResponse,
      },
    ]);
  }

  /// Get all request logs with pagination
  Future<List<RequestLog>> getAll({int? limit, int? offset}) async {
    var query = _database.laconic
        .table('request_logs')
        .orderBy('timestamp', direction: 'desc');

    if (limit != null) {
      query = query.limit(limit);
    }
    if (offset != null) {
      query = query.offset(offset);
    }

    final results = await query.get();
    return results.map((r) => _fromRow(r.toMap())).toList();
  }

  /// Get total count of request logs
  Future<int> getTotalCount() async {
    final result = await _database.laconic.table('request_logs').select([
      'id',
    ]).count();
    return result;
  }

  /// Get daily request stats for charts
  Future<Map<String, int>> getDailyRequestStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    final query = '''
      SELECT
        date(timestamp / 1000, 'unixepoch', 'localtime') as date,
        COUNT(*) as request_count
      FROM request_logs
      WHERE timestamp >= ? AND timestamp <= ?
      GROUP BY date
      ORDER BY date
    ''';

    final results = await _database.laconic.select(query, [
      startTimestamp,
      endTimestamp,
    ]);

    final Map<String, int> dailyStats = {};
    for (final row in results) {
      final date = row['date'] as String;
      final count = row['request_count'] as int;
      dailyStats[date] = count;
    }

    return dailyStats;
  }

  /// Get daily success rate stats for charts
  Future<Map<String, double>> getDailySuccessRateStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
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

    final results = await _database.laconic.select(query, [
      startTimestamp,
      endTimestamp,
    ]);

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

  /// Get endpoint response time stats for charts
  Future<Map<String, List<int>>> getEndpointResponseTimeStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
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

    final results = await _database.laconic.select(query, [
      startTimestamp,
      endTimestamp,
    ]);

    final Map<String, List<int>> endpointStats = {};
    for (final row in results) {
      final endpointName = row['endpoint_name'] as String;
      final responseTime = row['response_time'] as int;
      endpointStats.putIfAbsent(endpointName, () => []).add(responseTime);
    }

    return endpointStats;
  }

  /// Get endpoint token stats for charts
  Future<Map<String, int>> getEndpointTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
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

    final results = await _database.laconic.select(query, [
      startTimestamp,
      endTimestamp,
    ]);

    final Map<String, int> endpointTokenStats = {};
    for (final row in results) {
      final endpointName = row['endpoint_name'] as String;
      final totalTokens = row['total_tokens'] as int;
      endpointTokenStats[endpointName] = totalTokens;
    }

    return endpointTokenStats;
  }

  /// Get model date token stats for charts
  Future<Map<String, Map<String, int>>> getModelDateTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
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

    final results = await _database.laconic.select(query, [
      startTimestamp,
      endTimestamp,
    ]);

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

  /// Get logs by endpoint ID
  Future<List<RequestLog>> getByEndpoint(
    String endpointId, {
    int? limit,
  }) async {
    var query = _database.laconic
        .table('request_logs')
        .where('endpoint_id', endpointId)
        .orderBy('timestamp', direction: 'desc');

    if (limit != null) {
      query = query.limit(limit);
    }

    final results = await query.get();
    return results.map((r) => _fromRow(r.toMap())).toList();
  }

  /// Get logs by level
  Future<List<RequestLog>> getByLevel(LogLevel level, {int? limit}) async {
    var query = _database.laconic
        .table('request_logs')
        .where('level', level.name)
        .orderBy('timestamp', direction: 'desc');

    if (limit != null) {
      query = query.limit(limit);
    }

    final results = await query.get();
    return results.map((r) => _fromRow(r.toMap())).toList();
  }

  /// Get logs by time range
  Future<List<RequestLog>> getByTimeRange(
    int startTimestamp,
    int endTimestamp, {
    int? limit,
  }) async {
    var query = _database.laconic
        .table('request_logs')
        .where('timestamp', startTimestamp)
        .where('timestamp', endTimestamp)
        .orderBy('timestamp', direction: 'desc');

    if (limit != null) {
      query = query.limit(limit);
    }

    final results = await query.get();
    return results.map((r) => _fromRow(r.toMap())).toList();
  }

  /// Delete logs before timestamp
  Future<int> deleteBeforeTimestamp(int timestamp) async {
    final query = '''
      SELECT COUNT(*) as count FROM request_logs WHERE timestamp < ?
    ''';

    final countResult = await _database.laconic.select(query, [timestamp]);
    final count = countResult.first['count'] as int;

    await _database.laconic.statement(
      'DELETE FROM request_logs WHERE timestamp < ?',
      [timestamp],
    );

    return count;
  }

  /// Clear all request logs
  Future<void> clearAll() async {
    await _database.laconic.table('request_logs').delete();
  }

  /// Get daily token stats for heatmap
  Future<Map<String, int>> getDailyTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
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

    final results = await _database.laconic.select(query, [
      startTimestamp,
      endTimestamp,
    ]);

    final Map<String, int> dailyStats = {};
    for (final row in results) {
      final date = row['date'] as String;
      final tokens = row['total_tokens'] as int;
      dailyStats[date] = tokens;
    }

    return dailyStats;
  }

  /// Get daily success request stats for heatmap
  Future<Map<String, int>> getDailySuccessRequestStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
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

    final results = await _database.laconic.select(query, [
      startTimestamp,
      endTimestamp,
    ]);

    final Map<String, int> dailyStats = {};
    for (final row in results) {
      final date = row['date'] as String;
      final count = row['request_count'] as int;
      dailyStats[date] = count;
    }

    return dailyStats;
  }

  /// Convert database row to RequestLog
  RequestLog _fromRow(Map<String, dynamic> row) {
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
          ? Map<String, dynamic>.from(jsonDecode(headerStr))
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

  /// Convert string to LogLevel
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
}
