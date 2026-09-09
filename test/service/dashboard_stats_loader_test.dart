import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/dashboard_stats_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laconic/laconic.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late Laconic laconic;
  late RequestLogRepository repository;

  /// 固定参考时刻：测试断言与窗口计算完全确定，不随运行日期漂移。
  final now = DateTime(2026, 9, 7, 12, 0);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dashboard_stats_loader');
    dbPath = '${tempDir.path}/test.db';
    laconic = Laconic.sqlite(SqliteConfig(dbPath));
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
        cache_read_input_tokens INTEGER,
        ttft_ms INTEGER
      )
    ''');

    // 覆盖各时间窗口的数据：
    // - A/B：15 天窗口内（今天/昨天）
    // - C：今年但 15 天窗口外（只进热力图）
    // - D：去年（只进全历史聚合/总费用）
    // - E：今天但失败（不计 token/消息，只计活跃天数）
    await _insert(
      repository,
      'A',
      DateTime(2026, 9, 7, 12, 0),
      endpoint: 'ep-1',
      model: 'm1',
      statusCode: 200,
      inputTokens: 20,
      outputTokens: 10,
      cacheCreationInputTokens: 20,
      cacheReadInputTokens: 50,
    );
    await _insert(
      repository,
      'B',
      DateTime(2026, 9, 6, 9, 0),
      endpoint: 'ep-1',
      model: 'm2',
      statusCode: 200,
      inputTokens: 5,
      outputTokens: 5,
    );
    await _insert(
      repository,
      'C',
      DateTime(2026, 1, 5, 10, 0),
      endpoint: 'ep-1',
      model: 'm1',
      statusCode: 200,
      inputTokens: 7,
      outputTokens: 3,
    );
    await _insert(
      repository,
      'D',
      DateTime(2025, 12, 31, 23, 0),
      endpoint: 'ep-2',
      model: 'm3',
      statusCode: 200,
      inputTokens: 100,
      outputTokens: 100,
    );
    await _insert(
      repository,
      'E',
      DateTime(2026, 9, 7, 11, 0),
      endpoint: 'ep-2',
      model: 'm1',
      statusCode: 500,
      inputTokens: 999,
      outputTokens: 999,
    );
  });

  tearDown(() async {
    laconic.close();
    await tempDir.delete(recursive: true);
  });

  test('各时间窗口的聚合结果正确', () async {
    final result = await DashboardStatsLoader().load(dbPath, now: now);

    // 概览（全表、无时间窗口）：messages 仅 2xx 的 v1/messages；
    // 失败请求不计 token/消息，只计活跃天数
    expect(result.overview.messages, 4);
    expect(result.overview.totalTokens, 320);
    expect(result.overview.activeDays, 4);
    // 仅 2xx 请求参与命中率：分子 = 全部 cache_read 之和，
    // 分母 = cache_read + input 之和
    expect(result.overview.cacheHitRate, closeTo(50 / 182, 1e-9));

    // 折线图：15 天窗口（08-23 ~ 09-07），失败请求也计入请求数
    expect(result.dailyRequests, {'2026-09-06': 1, '2026-09-07': 2});

    // 热力图：全年（含窗口外的 01-05）
    expect(result.heatmapRequests, {
      '2026-01-05': 1,
      '2026-09-06': 1,
      '2026-09-07': 2,
    });

    // 模型日期统计：15 天窗口
    expect(result.recentModelTokens.map((s) => s.date).toSet(), {
      '2026-09-06',
      '2026-09-07',
    });
    final todayM1 = result.recentModelTokens.singleWhere(
      (s) => s.date == '2026-09-07' && s.model == 'm1',
    );
    expect(todayM1.input, 20);
    expect(todayM1.output, 10);
    expect(todayM1.cacheCreation, 20);
    expect(todayM1.cacheRead, 50);
    expect(todayM1.total, 100);

    // 全历史：多出窗口外的 01-05 与去年 12-31（失败请求仍不计入）
    final allDates = result.allModelTokens.map((s) => s.date).toSet();
    expect(allDates, {'2026-01-05', '2026-09-06', '2026-09-07', '2025-12-31'});
    final lastYear = result.allModelTokens.singleWhere((s) => s.model == 'm3');
    expect(lastYear.input, 100);
    expect(lastYear.output, 100);
  });
}

Future<void> _insert(
  RequestLogRepository repository,
  String id,
  DateTime timestamp, {
  required String endpoint,
  required String model,
  required int statusCode,
  int inputTokens = 0,
  int outputTokens = 0,
  int cacheCreationInputTokens = 0,
  int cacheReadInputTokens = 0,
}) async {
  await repository.insert(
    RequestLogEntity(
      id: id,
      timestamp: timestamp.millisecondsSinceEpoch,
      endpointName: endpoint,
      path: 'v1/messages',
      method: 'POST',
      statusCode: statusCode,
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cacheCreationInputTokens: cacheCreationInputTokens,
      cacheReadInputTokens: cacheReadInputTokens,
    ),
  );
}
