import 'dart:io';

import 'package:code_proxy/database/migration/migration_202512110000.dart';
import 'package:code_proxy/database/migration/migration_202512150000.dart';
import 'package:code_proxy/database/migration/migration_202512150001.dart';
import 'package:code_proxy/database/migration/migration_202512310000.dart';
import 'package:code_proxy/database/migration/migration_202601100000.dart';
import 'package:code_proxy/database/migration/migration_202602080000.dart';
import 'package:code_proxy/database/migration/migration_202603110000.dart';
import 'package:code_proxy/database/migration/migration_202603130000.dart';
import 'package:code_proxy/database/migration/migration_202604230000.dart';
import 'package:code_proxy/database/migration/migration_202605100000.dart';
import 'package:code_proxy/database/migration/migration_202608150000.dart';
import 'package:code_proxy/database/migration/migration_202608221000.dart';
import 'package:code_proxy/database/migration/migration_202609070000.dart';
import 'package:code_proxy/database/migration/migration_202609070001.dart';
import 'package:code_proxy/database/migration/migration_202609090000.dart';
import 'package:code_proxy/database/migration/migration_202609090001.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laconic/laconic.dart';

final _migrations = <(String, Future<void> Function(Laconic))>[
  (Migration202512110000.name, Migration202512110000().migrate),
  (Migration202512150000.name, Migration202512150000().migrate),
  (Migration202512150001.name, Migration202512150001().migrate),
  (Migration202512310000.name, Migration202512310000().migrate),
  (Migration202601100000.name, Migration202601100000().migrate),
  (Migration202602080000.name, Migration202602080000().migrate),
  (Migration202603110000.name, Migration202603110000().migrate),
  (Migration202603130000.name, Migration202603130000().migrate),
  (Migration202604230000.name, Migration202604230000().migrate),
  (Migration202605100000.name, Migration202605100000().migrate),
  (Migration202608150000.name, Migration202608150000().migrate),
  (Migration202608221000.name, Migration202608221000().migrate),
  (Migration202609070000.name, Migration202609070000().migrate),
  (Migration202609070001.name, Migration202609070001().migrate),
  (Migration202609090000.name, Migration202609090000().migrate),
  (Migration202609090001.name, Migration202609090001().migrate),
];

void main() {
  late Directory dir;
  late String path;
  late Laconic db;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('migration-recovery-');
    path = '${dir.path}/test.db';
    db = Laconic.sqlite(SqliteConfig(path));
    await db.statement('CREATE TABLE migrations (name TEXT NOT NULL)');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> reopen() async {
    await db.close();
    db = Laconic.sqlite(SqliteConfig(path));
  }

  Future<void> prepare(int index) async {
    for (final migration in _migrations.take(index)) {
      await migration.$2(db);
    }
    if (index == 4) {
      await db.statement('ALTER TABLE endpoints ADD COLUMN created_at INTEGER');
    }
  }

  Future<String> schema(String table) async =>
      (await db.select(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
            [table],
          )).single['sql']
          as String;

  Future<void> rejectLedger() => db.statement("""
    CREATE TRIGGER reject_migration BEFORE INSERT ON migrations
    BEGIN SELECT RAISE(ABORT, 'injected failure before commit'); END
  """);

  for (final (index, table) in [
    (1, 'endpoints'),
    (3, 'request_logs'),
    (5, 'request_logs'),
    (6, 'request_logs'),
  ]) {
    final migration = _migrations[index];
    test('${migration.$1} 加列未登记的旧状态可重新打开并恢复', () async {
      await prepare(index);
      await migration.$2(db);
      final expectedSchema = await schema(table);
      await db.table('migrations').where('name', migration.$1).delete();
      // 双列迁移只完成第一列时也应可恢复。
      if (index == 1) {
        await db.statement('ALTER TABLE endpoints DROP COLUMN forbidden_until');
      }
      if (index == 6) {
        await db.statement(
          'ALTER TABLE request_logs DROP COLUMN cache_read_input_tokens',
        );
      }
      await reopen();
      await migration.$2(db);
      await migration.$2(db);
      // SQLite DROP COLUMN 会调整空白，比较字段信息而非 DDL 文本。
      final columns = await db.select("PRAGMA table_info('$table')");
      for (final row in columns) {
        expect(expectedSchema, contains(row['name'] as String));
      }
      if (index == 1) {
        expect(columns.map((r) => r['name']), contains('forbidden_until'));
      }
      if (index == 6) {
        expect(
          columns.map((r) => r['name']),
          contains('cache_read_input_tokens'),
        );
      }
      expect(
        await db.table('migrations').where('name', migration.$1).count(),
        1,
      );
    });

    test('${migration.$1} 登记失败时回滚所有加列', () async {
      await prepare(index);
      final original = await schema(table);
      await rejectLedger();
      await expectLater(migration.$2(db), throwsA(anything));
      await reopen();
      expect(await schema(table), original);
      expect(
        await db.table('migrations').where('name', migration.$1).count(),
        0,
      );
      await db.statement('DROP TRIGGER reject_migration');
      await migration.$2(db);
    });
  }

  for (final (index, table) in [
    (2, 'request_logs'),
    (4, 'endpoints'),
    (7, 'endpoints'),
  ]) {
    final migration = _migrations[index];
    final seed = table == 'endpoints'
        ? <String, Object?>{
            'id': 'saved',
            'name': 'Saved endpoint',
            'anthropic_auth_token': 'secret',
            'weight': 7,
          }
        : <String, Object?>{
            'id': 'saved',
            'timestamp': 1,
            'endpoint_id': 'ep',
            'endpoint_name': 'Saved endpoint',
            'path': 'v1/messages',
            'method': 'POST',
            'success': 1,
            'level': 'info',
            'input_tokens': 123,
          };
    for (final stage in ['create', 'copy', 'drop', 'rename']) {
      test('${migration.$1} 在 $stage 后中断的旧数据库可恢复且不丢数据', () async {
        await prepare(index);
        await db.table(table).insert([seed]);
        final originalSchema = await schema(table);
        await migration.$2(db);
        final expectedRows = (await db.table(table).get())
            .map((r) => r.toMap())
            .toList();
        await db.table('migrations').where('name', migration.$1).delete();
        if (stage != 'rename') {
          await db.statement('ALTER TABLE $table RENAME TO ${table}_new');
          if (stage == 'create' || stage == 'copy') {
            await db.statement(originalSchema);
            await db.table(table).insert([seed]);
            if (stage == 'create') await db.table('${table}_new').delete();
          }
        }
        await reopen();
        await migration.$2(db);
        await migration.$2(db);
        expect(
          (await db.table(table).get()).map((r) => r.toMap()).toList(),
          expectedRows,
        );
        expect(
          await db.select("SELECT name FROM sqlite_master WHERE name=?", [
            '${table}_new',
          ]),
          isEmpty,
        );
        expect(
          await db.table('migrations').where('name', migration.$1).count(),
          1,
        );
        // 恢复后继续整个版本链，验证后续迁移仍可启动。
        for (final later in _migrations.skip(index + 1)) {
          await later.$2(db);
        }
        expect(await db.table(table).count(), 1);
      });
    }

    test('${migration.$1} DROP/RENAME 后登记失败也能回滚到原表', () async {
      await prepare(index);
      await db.table(table).insert([seed]);
      final original = await schema(table);
      final rows = (await db.table(table).get()).map((r) => r.toMap()).toList();
      await rejectLedger();
      await expectLater(migration.$2(db), throwsA(anything));
      await reopen();
      expect(await schema(table), original);
      expect(
        (await db.table(table).get()).map((r) => r.toMap()).toList(),
        rows,
      );
      expect(
        await db.select("SELECT name FROM sqlite_master WHERE name=?", [
          '${table}_new',
        ]),
        isEmpty,
      );
      expect(
        await db.table('migrations').where('name', migration.$1).count(),
        0,
      );
      await db.statement('DROP TRIGGER reject_migration');
      await migration.$2(db);
    });
  }

  test('空数据库完整迁移链可重复执行', () async {
    for (var pass = 0; pass < 2; pass++) {
      for (final migration in _migrations) {
        await migration.$2(db);
      }
      await reopen();
    }
    expect(await db.table('migrations').count(), _migrations.length);
    expect(await db.table('endpoints').count(), 0);
    expect(await db.table('request_logs').count(), 0);
  });
}
