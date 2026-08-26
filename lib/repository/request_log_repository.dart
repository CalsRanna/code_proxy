import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/model_date_token_stat.dart';
import 'package:code_proxy/model/request_log_entity.dart';

/// Request Log Repository
///
/// Handles CRUD operations for request logs and statistics
class RequestLogRepository {
  final Database _database;

  RequestLogRepository(this._database);

  /// Clear all request logs
  ///
  /// 不执行 VACUUM：它在大库上会同步阻塞数秒，而代理与 UI 共用同一个
  /// isolate。DELETE 释放的页面会被 SQLite 重用，日常使用无需回收物理空间；
  /// 若确需收缩文件，应做成设置页里的显式操作，而不是挂在清空流程上。
  Future<void> clearAll() async {
    await _database.laconic.table('request_logs').delete();
  }

  /// Get all request logs with pagination
  ///
  /// [statusCodeFilter]: null=全部, 200=仅成功, -1=仅失败(非200)
  Future<List<RequestLogEntity>> getAll({
    int? limit,
    int? offset,
    int? statusCodeFilter,
  }) async {
    var query = _database.laconic
        .table('request_logs')
        .orderBy('timestamp', direction: 'desc');

    if (statusCodeFilter == 200) {
      query = query.where('status_code', 200);
    } else if (statusCodeFilter == -1) {
      query = query.where('status_code', 200, comparator: '!=');
    }

    if (limit != null) {
      query = query.limit(limit);
    }
    if (offset != null) {
      query = query.offset(offset);
    }

    final results = await query.get();
    return results.map((r) => _fromRow(r.toMap())).toList();
  }

  /// SQLite `date()` 的时区修饰符，把 UTC 毫秒时间戳折算到本机当地日期。
  ///
  /// 用 `'+N minutes'` 而非 `'localtime'`：前者是标准语法、跨平台一致，
  /// 且支持半小时（UTC+5:30）与 45 分钟（UTC+5:45）这类非整时偏移。
  static String _localDateModifier() {
    final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    return offsetMinutes >= 0
        ? '+$offsetMinutes minutes'
        : '$offsetMinutes minutes';
  }

  /// Get daily request stats for charts
  Future<Map<String, int>> getDailyRequestStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    final offsetModifier = _localDateModifier();

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
          'SUM(COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0) + COALESCE(cache_creation_input_tokens, 0) + COALESCE(cache_read_input_tokens, 0)) as total_tokens',
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

  /// 按「本地日期 + 模型」聚合的 token 用量（仅 2xx 成功请求）。
  ///
  /// Token 柱状图与费用计算共用此结果 —— 两者此前各跑一条 `GROUP BY
  /// (date, model)` 的 SUM 查询，字段与过滤条件几乎相同，只是返回形状不同，
  /// dashboard 一次加载会把同一份聚合算两遍。
  ///
  /// `total > 0` 的过滤留给调用方（见 [ModelDateTokenStat.total]）：
  /// 费用计算不需要过滤，图表需要，放在 SQL 里就得为两种需求各开一条查询。
  Future<List<ModelDateTokenStat>> getModelDateTokenStats({
    required int startTimestamp,
    required int endTimestamp,
  }) async {
    final offsetModifier = _localDateModifier();

    final results = await _database.laconic.select(
      '''
      SELECT date(timestamp / 1000, 'unixepoch', '$offsetModifier') as date,
             COALESCE(model, 'unknown') as model,
             SUM(COALESCE(input_tokens, 0)) as input,
             SUM(COALESCE(output_tokens, 0)) as output,
             SUM(COALESCE(cache_creation_input_tokens, 0)) as cache_creation,
             SUM(COALESCE(cache_read_input_tokens, 0)) as cache_read
      FROM request_logs
      WHERE timestamp BETWEEN ? AND ? AND status_code = 200
      GROUP BY date, model
      ORDER BY date, model
    ''',
      [startTimestamp, endTimestamp],
    );

    return results.map((row) {
      final rowMap = row.toMap();
      return ModelDateTokenStat(
        date: rowMap['date'] as String,
        model: rowMap['model'] as String,
        input: rowMap['input'] as int,
        output: rowMap['output'] as int,
        cacheCreation: rowMap['cache_creation'] as int,
        cacheRead: rowMap['cache_read'] as int,
      );
    }).toList();
  }

  /// Get total count of request logs
  ///
  /// [statusCodeFilter]: null=全部, 200=仅成功, -1=仅失败(非200)
  Future<int> getTotalCount({int? statusCodeFilter}) async {
    var query = _database.laconic.table('request_logs').select(['id']);

    if (statusCodeFilter == 200) {
      query = query.where('status_code', 200);
    } else if (statusCodeFilter == -1) {
      query = query.where('status_code', 200, comparator: '!=');
    }

    final result = await query.count();
    return result;
  }

  /// Insert a new request log
  Future<void> insert(RequestLogEntity log) async {
    await _database.laconic.table('request_logs').insert([
      {
        'id': log.id,
        'timestamp': log.timestamp,
        'endpoint_name': log.endpointName,
        'path': log.path,
        'method': log.method,
        'status_code': log.statusCode,
        'response_time': log.responseTime,
        'model': log.model,
        'origin_model': log.originalModel,
        'input_tokens': log.inputTokens,
        'output_tokens': log.outputTokens,
        'cache_creation_input_tokens': log.cacheCreationInputTokens,
        'cache_read_input_tokens': log.cacheReadInputTokens,
        'error_message': log.errorMessage,
      },
    ]);
  }

  /// Convert database row to RequestLog
  RequestLogEntity _fromRow(Map<String, dynamic> row) {
    return RequestLogEntity(
      id: row['id'] as String,
      timestamp: row['timestamp'] as int,
      endpointName: row['endpoint_name'] as String,
      path: row['path'] as String,
      method: row['method'] as String,
      statusCode: row['status_code'] as int?,
      responseTime: row['response_time'] as int?,
      model: row['model'] as String?,
      originalModel: row['origin_model'] as String?,
      inputTokens: row['input_tokens'] as int?,
      outputTokens: row['output_tokens'] as int?,
      cacheCreationInputTokens: row['cache_creation_input_tokens'] as int?,
      cacheReadInputTokens: row['cache_read_input_tokens'] as int?,
      errorMessage: row['error_message'] as String?,
    );
  }
}
