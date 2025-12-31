import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/request_log_entity.dart';

/// Request Log Repository
///
/// Handles CRUD operations for request logs and statistics
class RequestLogRepository {
  final Database _database;

  RequestLogRepository(this._database);

  /// Clear all request logs
  Future<void> clearAll() async {
    await _database.laconic.table('request_logs').delete();
    // 回收数据库空间
    await _database.laconic.statement('VACUUM;');
  }

  /// Get all request logs with pagination
  Future<List<RequestLogEntity>> getAll({int? limit, int? offset}) async {
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

  /// Get daily request stats for charts
  Future<Map<String, int>> getDailyRequestStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    // 计算时区偏移（分钟）
    // 使用 '+N minutes' 修饰符，这是 SQLite 标准语法，跨平台兼容
    // 支持所有时区，包括半小时偏移（如 UTC+5:30）和 45 分钟偏移（如 UTC+5:45）
    final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    final offsetModifier = offsetMinutes >= 0
        ? '+$offsetMinutes minutes'
        : '$offsetMinutes minutes';

    final results = await _database.laconic
        .table('request_logs')
        .select([
          'date(timestamp / 1000, \'unixepoch\', \'$offsetModifier\') as date',
          'COUNT(id) as request_count',
        ])
        .whereBetween('timestamp', min: startTimestamp, max: endTimestamp)
        .groupBy('date')
        .orderBy('date')
        .get();

    final Map<String, int> dailyStats = {};
    for (final row in results) {
      final rowMap = row.toMap();
      final date = rowMap['date'] as String;
      final count = rowMap['request_count'] as int;
      dailyStats[date] = count;
    }

    return dailyStats;
  }

  /// Get daily request stats for heatmap
  Future<Map<String, int>> getDailySuccessRequestStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    // 计算时区偏移（分钟）
    // 使用 '+N minutes' 修饰符，这是 SQLite 标准语法，跨平台兼容
    // 支持所有时区，包括半小时偏移（如 UTC+5:30）和 45 分钟偏移（如 UTC+5:45）
    final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    final offsetModifier = offsetMinutes >= 0
        ? '+$offsetMinutes minutes'
        : '$offsetMinutes minutes';

    final results = await _database.laconic
        .table('request_logs')
        .select([
          'date(timestamp / 1000, \'unixepoch\', \'$offsetModifier\') as date',
          'COUNT(id) as request_count',
        ])
        .whereBetween('timestamp', min: startTimestamp, max: endTimestamp)
        .groupBy('date')
        .orderBy('date')
        .get();

    final Map<String, int> dailyStats = {};
    for (final row in results) {
      final rowMap = row.toMap();
      final date = rowMap['date'] as String;
      final count = rowMap['request_count'] as int;
      dailyStats[date] = count;
    }

    return dailyStats;
  }

  /// Get endpoint token stats for charts
  Future<Map<String, int>> getEndpointTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    final results = await _database.laconic
        .table('request_logs')
        .select([
          'endpoint_name',
          'SUM(COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)) as total_tokens',
        ])
        .whereBetween('timestamp', min: startTimestamp, max: endTimestamp)
        .groupBy('endpoint_name')
        .having('total_tokens', 0, operator: '>')
        .orderBy('total_tokens', direction: 'desc')
        .get();

    final Map<String, int> endpointTokenStats = {};
    for (final row in results) {
      final rowMap = row.toMap();
      final endpointName = rowMap['endpoint_name'] as String;
      final totalTokens = rowMap['total_tokens'] as int;
      endpointTokenStats[endpointName] = totalTokens;
    }

    return endpointTokenStats;
  }

  /// Get model date token stats for charts
  Future<Map<String, Map<String, int>>> getModelDateTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    // 计算时区偏移（分钟）
    // 使用 '+N minutes' 修饰符，这是 SQLite 标准语法，跨平台兼容
    // 支持所有时区，包括半小时偏移（如 UTC+5:30）和 45 分钟偏移（如 UTC+5:45）
    final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    final offsetModifier = offsetMinutes >= 0
        ? '+$offsetMinutes minutes'
        : '$offsetMinutes minutes';

    final results = await _database.laconic
        .table('request_logs')
        .select([
          'date(timestamp / 1000, \'unixepoch\', \'$offsetModifier\') as date',
          'COALESCE(model, \'unknown\') as model',
          'SUM(COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)) as total_tokens',
        ])
        .whereBetween('timestamp', min: startTimestamp, max: endTimestamp)
        .groupBy('date')
        .groupBy('model')
        .having('total_tokens', 0, operator: '>')
        .orderBy('date')
        .orderBy('model')
        .get();

    final Map<String, Map<String, int>> modelDateStats = {};
    for (final row in results) {
      final rowMap = row.toMap();
      final date = rowMap['date'] as String;
      final model = rowMap['model'] as String;
      final totalTokens = rowMap['total_tokens'] as int;

      modelDateStats.putIfAbsent(date, () => {});
      modelDateStats[date]![model] = totalTokens;
    }

    return modelDateStats;
  }

  /// Get total count of request logs
  Future<int> getTotalCount() async {
    final result = await _database.laconic.table('request_logs').select([
      'id',
    ]).count();
    return result;
  }

  /// Insert a new request log
  Future<void> insert(RequestLogEntity log) async {
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
        'model': log.model,
        'input_tokens': log.inputTokens,
        'output_tokens': log.outputTokens,
        'error_message': log.errorMessage,
      },
    ]);
  }

  /// Convert database row to RequestLog
  RequestLogEntity _fromRow(Map<String, dynamic> row) {
    return RequestLogEntity(
      id: row['id'] as String,
      timestamp: row['timestamp'] as int,
      endpointId: row['endpoint_id'] as String,
      endpointName: row['endpoint_name'] as String,
      path: row['path'] as String,
      method: row['method'] as String,
      statusCode: row['status_code'] as int?,
      responseTime: row['response_time'] as int?,
      model: row['model'] as String?,
      inputTokens: row['input_tokens'] as int?,
      outputTokens: row['output_tokens'] as int?,
      errorMessage: row['error_message'] as String?,
    );
  }
}
