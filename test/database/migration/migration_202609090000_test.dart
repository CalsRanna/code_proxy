import 'dart:io';

import 'package:code_proxy/database/migration/migration_202609090000.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laconic/laconic.dart';

void main() {
  late Directory directory;
  late Laconic laconic;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'endpoint_format_migration_',
    );
    laconic = Laconic.sqlite(SqliteConfig('${directory.path}/test.db'));
    await laconic.statement('CREATE TABLE migrations (name TEXT NOT NULL)');
    await laconic.statement('''
      CREATE TABLE endpoints (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        api_format TEXT NOT NULL,
        anthropic_auth_token TEXT,
        anthropic_base_url TEXT
      )
    ''');
  });

  tearDown(() async {
    laconic.close();
    await directory.delete(recursive: true);
  });

  test('仅更新旧 openai 值，保留其他数据且重复启动不会重复迁移', () async {
    final originalRows = [
      for (final format in [
        'openai',
        'anthropic',
        'openaiResponses',
        'openaiChat',
        'unknown',
      ])
        {
          'id': format,
          'name': 'Endpoint $format',
          'api_format': format,
          'anthropic_auth_token': 'test-token-$format',
          'anthropic_base_url': 'https://example.com/$format',
        },
    ];
    await laconic.table('endpoints').insert(originalRows);
    final migration = Migration202609090000();

    await migration.migrate(laconic);
    await migration.migrate(laconic);

    final rows = await laconic.table('endpoints').orderBy('id').get();
    final expected =
        originalRows
            .map(
              (row) => {
                ...row,
                'api_format': row['api_format'] == 'openai'
                    ? 'openaiChat'
                    : row['api_format'],
              },
            )
            .toList()
          ..sort((a, b) => a['id']!.compareTo(b['id']!));
    expect(rows.map((row) => row.toMap()).toList(), expected);
    final migrations = await laconic.table('migrations').get();
    expect(migrations.map((row) => row.toMap()).toList(), [
      {'name': Migration202609090000.name},
    ]);
  });

  test('新安装的空端点表也能完成迁移', () async {
    await Migration202609090000().migrate(laconic);

    expect(await laconic.table('endpoints').count(), 0);
    expect(
      await laconic
          .table('migrations')
          .where('name', Migration202609090000.name)
          .count(),
      1,
    );
  });
}
