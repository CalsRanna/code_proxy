import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laconic/laconic.dart';

void main() {
  late Laconic laconic;
  late RequestLogRepository repository;

  setUp(() async {
    laconic = Laconic.sqlite(const SqliteConfig(':memory:'));
    Database.instance.laconic = laconic;
    repository = RequestLogRepository(Database.instance);

    await laconic.statement('''
      CREATE TABLE request_logs (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        endpoint_name TEXT NOT NULL,
        path TEXT NOT NULL,
        method TEXT NOT NULL,
        status_code INTEGER,
        response_time INTEGER,
        model TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        error_message TEXT,
        origin_model TEXT,
        cache_creation_input_tokens INTEGER,
        cache_read_input_tokens INTEGER
      )
    ''');
  });

  tearDown(() => laconic.close());

  test('概览统计：成功消息请求计入消息与 token，失败请求只计活跃天', () async {
    // 同一天（本地时区）内的 3 条消息请求：2 成功 1 失败
    final dayStart = DateTime.now();
    final t0 = DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day,
      10,
    ).millisecondsSinceEpoch;

    await repository.insert(
      RequestLogEntity(
        id: 'ok-1',
        timestamp: t0,
        endpointName: 'Anthropic',
        path: 'v1/messages',
        method: 'POST',
        statusCode: 200,
        inputTokens: 20,
        outputTokens: 10,
        cacheCreationInputTokens: 5,
        cacheReadInputTokens: 100,
      ),
    );
    await repository.insert(
      RequestLogEntity(
        id: 'ok-2',
        timestamp: t0,
        endpointName: 'Anthropic',
        path: 'v1/messages',
        method: 'POST',
        statusCode: 200,
        inputTokens: 0,
        outputTokens: 0,
      ),
    );
    await repository.insert(
      RequestLogEntity(
        id: 'fail-1',
        timestamp: t0,
        endpointName: 'Anthropic',
        path: 'v1/messages',
        method: 'POST',
        statusCode: 429,
        inputTokens: 1,
        outputTokens: 0,
      ),
    );
    // 本地应答路径：不计入消息
    await repository.insert(
      RequestLogEntity(
        id: 'count-1',
        timestamp: t0,
        endpointName: 'Anthropic',
        path: 'v1/messages/count_tokens',
        method: 'POST',
        statusCode: 200,
      ),
    );

    final stats = await repository.getOverviewStats();
    expect(stats.messages, 2);
    expect(stats.totalTokens, 20 + 10 + 5 + 100);
    expect(stats.activeDays, 1);
    // 命中率只算成功请求：cache_read 100 / (cache_read 100 + input 20)
    expect(stats.cacheHitRate, closeTo(100 / 120, 0.0001));
  });

  test('概览统计：活跃天按本地日期去重，token 只汇总成功请求', () async {
    final dayStart = DateTime.now();
    final t0 = DateTime(
      dayStart.year,
      dayStart.month,
      dayStart.day,
      10,
    ).millisecondsSinceEpoch;
    final t1 = t0 + const Duration(days: 1).inMilliseconds;
    final t2 = t0 + const Duration(days: 2).inMilliseconds;

    await repository.insert(
      RequestLogEntity(
        id: 'day0',
        timestamp: t0,
        endpointName: 'Anthropic',
        path: 'v1/messages',
        method: 'POST',
        statusCode: 200,
        inputTokens: 10,
      ),
    );
    await repository.insert(
      RequestLogEntity(
        id: 'day1',
        timestamp: t1,
        endpointName: 'Anthropic',
        path: 'v1/messages',
        method: 'POST',
        statusCode: 500,
      ),
    );
    await repository.insert(
      RequestLogEntity(
        id: 'day2',
        timestamp: t2,
        endpointName: 'Anthropic',
        path: 'v1/messages',
        method: 'POST',
        statusCode: 200,
        outputTokens: 30,
      ),
    );

    final stats = await repository.getOverviewStats();
    expect(stats.messages, 2);
    expect(stats.totalTokens, 10 + 30);
    expect(stats.activeDays, 3);
    // 无任何缓存读取 → 命中率为 0
    expect(stats.cacheHitRate, 0.0);
  });
}
