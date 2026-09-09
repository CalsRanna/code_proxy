import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/request_log_entity.dart';

/// Dashboard 聚合查询 SQL 的唯一来源。
///
/// 后台 isolate 的 DashboardStatsLoader 从这里取 SQL 执行；
/// request_logs 表结构或统计口径变更时只需修改此处。
class DashboardAggregationSql {
  /// SQLite `date()` 的时区修饰符，把 UTC 毫秒时间戳折算到本机当地日期。
  ///
  /// 用 `'+N minutes'` 而非 `'localtime'`：前者是标准语法、跨平台一致，
  /// 且支持半小时（UTC+5:30）与 45 分钟（UTC+5:45）这类非整时偏移。
  static String localDateModifier() {
    final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    return offsetMinutes >= 0
        ? '+$offsetMinutes minutes'
        : '$offsetMinutes minutes';
  }

  /// 每日请求数（折线图与热力图共用，仅时间段不同）。
  static String dailyRequestStats(String localOffsetModifier) =>
      '''
    SELECT date(timestamp / 1000, 'unixepoch', '$localOffsetModifier') as date,
           COUNT(id) as request_count
    FROM request_logs
    WHERE timestamp BETWEEN ? AND ?
    GROUP BY date
    ORDER BY date
  ''';

  /// 按「本地日期 + 模型」聚合的 token 用量（仅 2xx 成功请求）。
  ///
  /// `total > 0` 的过滤留给调用方：费用计算不需要过滤而图表需要，
  /// 放在 SQL 里就得为两种需求各开一条查询。
  static String modelDateTokenStats(String localOffsetModifier) =>
      '''
    SELECT date(timestamp / 1000, 'unixepoch', '$localOffsetModifier') as date,
           COALESCE(model, 'unknown') as model,
           SUM(COALESCE(input_tokens, 0)) as input,
           SUM(COALESCE(output_tokens, 0)) as output,
           SUM(COALESCE(cache_creation_input_tokens, 0)) as cache_creation,
           SUM(COALESCE(cache_read_input_tokens, 0)) as cache_read
    FROM request_logs
    WHERE timestamp BETWEEN ? AND ? AND status_code = 200
    GROUP BY date, model
    ORDER BY date, model
  ''';

  /// 概览统计：消息数、token 总量、活跃天数、缓存命中率，四合一聚合。
  ///
  /// - messages：成功的 `/v1/messages` 请求数（count_tokens、models 等
  ///   本地应答路径不计入）
  /// - totalTokens：SUM 四类 token，仅 2xx 成功请求（失败请求的 usage
  ///   不可靠，与 token 图表口径一致）
  /// - activeDays：有任意请求（含失败）的本地去重日期数，与热力图口径一致
  /// - cacheHitRate：cache_read / (cache_read + input)，仅 2xx 成功请求；
  ///   分子乘 1.0 强制浮点除法（SQLite 整数除法会截断为 0）。
  static String overviewStats(String localOffsetModifier) =>
      '''
    SELECT COUNT(DISTINCT date(timestamp / 1000, 'unixepoch', '$localOffsetModifier')) AS active_days,
           COUNT(CASE WHEN path = 'v1/messages' AND status_code = 200 THEN 1 END) AS messages,
           COALESCE(SUM(CASE WHEN status_code = 200 THEN
             COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0) +
             COALESCE(cache_creation_input_tokens, 0) + COALESCE(cache_read_input_tokens, 0)
           END), 0) AS total_tokens,
           COALESCE(
             SUM(CASE WHEN status_code = 200 THEN COALESCE(cache_read_input_tokens, 0) END) * 1.0 /
             NULLIF(SUM(CASE WHEN status_code = 200 THEN
               COALESCE(cache_read_input_tokens, 0) + COALESCE(input_tokens, 0)
             END), 0),
             0
           ) AS cache_hit_rate
    FROM request_logs
  ''';
}

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
        'ttft_ms': log.ttftMs,
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
      ttftMs: row['ttft_ms'] as int?,
      errorMessage: row['error_message'] as String?,
    );
  }
}
