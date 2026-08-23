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

  test('端点与模型统计只汇总一次互斥 token 分类', () async {
    final timestamp = DateTime(2026, 8, 23, 12).millisecondsSinceEpoch;
    for (final endpoint in ['Anthropic', 'OpenAI']) {
      await repository.insert(
        RequestLogEntity(
          id: endpoint,
          timestamp: timestamp,
          endpointName: endpoint,
          path: '/v1/messages',
          method: 'POST',
          statusCode: 200,
          model: 'same-model',
          inputTokens: 20,
          outputTokens: 10,
          cacheCreationInputTokens: 20,
          cacheReadInputTokens: 50,
        ),
      );
    }

    final endpointStats = await repository.getEndpointTokenStats(
      startTimestamp: timestamp - 1,
      endTimestamp: timestamp + 1,
    );
    expect(endpointStats, {'Anthropic': 100, 'OpenAI': 100});

    final modelStats = await repository.getModelDateTokenStats(
      startTimestamp: timestamp - 1,
      endTimestamp: timestamp + 1,
    );
    final date = modelStats.values.single['same-model']!;
    expect(date, {
      'total': 200,
      'input': 40,
      'output': 20,
      'cache_read': 100,
      'cache_creation': 40,
    });

    final costBreakdown = await repository.getDailyModelTokenBreakdown(
      startTimestamp: timestamp - 1,
      endTimestamp: timestamp + 1,
    );
    expect(costBreakdown.single, containsPair('input', 40));
    expect(costBreakdown.single, containsPair('output', 20));
    expect(costBreakdown.single, containsPair('cache_creation', 40));
    expect(costBreakdown.single, containsPair('cache_read', 100));
  });
}
