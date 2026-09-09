import 'dart:io';

import 'package:code_proxy/database/migration/migration_202609090001.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laconic/laconic.dart';

void main() {
  late Directory directory;
  late Laconic laconic;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ttft_migration_');
    laconic = Laconic.sqlite(SqliteConfig('${directory.path}/test.db'));
    await laconic.statement('CREATE TABLE migrations (name TEXT NOT NULL)');
    await laconic.statement('''
      CREATE TABLE request_logs (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        endpoint_name TEXT NOT NULL,
        path TEXT NOT NULL,
        method TEXT NOT NULL,
        status_code INTEGER,
        response_time INTEGER
      )
    ''');
  });

  tearDown(() async {
    laconic.close();
    await directory.delete(recursive: true);
  });

  Future<Set<String>> columns() async {
    final info = await laconic.select("PRAGMA table_info('request_logs')");
    return info.map((r) => r['name'] as String).toSet();
  }

  test('添加 ttft_ms 列，历史行为 NULL，重复执行不报错', () async {
    await laconic.table('request_logs').insert([
      {
        'id': 'log-1',
        'timestamp': 1,
        'endpoint_name': 'ep',
        'path': 'v1/messages',
        'method': 'POST',
        'status_code': 200,
        'response_time': 1234,
      },
    ]);
    final migration = Migration202609090001();

    await migration.migrate(laconic);
    await migration.migrate(laconic);

    expect(await columns(), contains('ttft_ms'));
    final row = (await laconic.table('request_logs').get()).single.toMap();
    expect(row['ttft_ms'], isNull);
    expect(row['response_time'], 1234);
    final migrations = await laconic.table('migrations').get();
    expect(migrations.map((row) => row.toMap()).toList(), [
      {'name': Migration202609090001.name},
    ]);
  });

  test('列已存在但迁移未登记时只补登记，不重复加列', () async {
    await laconic.statement(
      'ALTER TABLE request_logs ADD COLUMN ttft_ms INTEGER',
    );

    await Migration202609090001().migrate(laconic);

    expect(await columns(), contains('ttft_ms'));
    expect(
      await laconic
          .table('migrations')
          .where('name', Migration202609090001.name)
          .count(),
      1,
    );
  });
}
