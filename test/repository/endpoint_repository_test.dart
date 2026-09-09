import 'dart:io';

import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/database/migration/migration_202609090000.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/repository/endpoint_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laconic/laconic.dart';

class _Database extends Fake implements Database {
  @override
  final Laconic laconic;

  _Database(this.laconic);
}

void main() {
  late Directory directory;
  late Laconic laconic;
  late EndpointRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('endpoint_repository_');
    laconic = Laconic.sqlite(SqliteConfig('${directory.path}/test.db'));
    repository = EndpointRepository(_Database(laconic));
    await laconic.statement('CREATE TABLE migrations (name TEXT NOT NULL)');
    await laconic.statement('''
      CREATE TABLE endpoints (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        note TEXT,
        enabled INTEGER DEFAULT 1,
        weight INTEGER DEFAULT 1,
        auth_mode TEXT DEFAULT 'preserve',
        api_format TEXT DEFAULT 'anthropic',
        anthropic_auth_token TEXT,
        anthropic_base_url TEXT,
        haiku_model TEXT,
        sonnet_model TEXT,
        opus_model TEXT,
        fable_model TEXT
      )
    ''');
  });

  tearDown(() async {
    laconic.close();
    await directory.delete(recursive: true);
  });

  test('已有 openai 端点迁移、读取和编辑后使用 openaiChat', () async {
    await laconic.table('endpoints').insert([
      {
        'id': 'legacy',
        'name': 'Existing endpoint',
        'api_format': 'openai',
        'anthropic_auth_token': 'old-token',
        'anthropic_base_url': 'https://old.example.com/v1',
      },
    ]);

    await Migration202609090000().migrate(laconic);
    final migratedRow = (await laconic.table('endpoints').get()).single.toMap();
    expect(migratedRow['api_format'], 'openaiChat');

    final existing = (await repository.getAll()).single;
    expect(existing.apiFormat, EndpointApiFormat.openaiChat);
    expect(existing.authToken, 'old-token');
    expect(existing.baseUrl, 'https://old.example.com/v1');

    await repository.update(
      existing.copyWith(
        authToken: 'updated-token',
        baseUrl: 'https://updated.example.com/v1',
      ),
    );

    final row = (await laconic.table('endpoints').get()).single.toMap();
    expect(row['api_format'], 'openaiChat');
    expect(row['anthropic_auth_token'], 'updated-token');
    expect(row['anthropic_base_url'], 'https://updated.example.com/v1');
    final updated = (await repository.getAll()).single;
    expect(updated.apiFormat, EndpointApiFormat.openaiChat);
    expect(updated.authToken, 'updated-token');
    expect(updated.baseUrl, 'https://updated.example.com/v1');
  });

  test('新建和克隆端点保留协议、认证及地址的存储格式', () async {
    const storedFormats = {
      EndpointApiFormat.anthropic: 'anthropic',
      EndpointApiFormat.openaiResponses: 'openaiResponses',
      EndpointApiFormat.openaiChat: 'openaiChat',
    };
    for (final entry in storedFormats.entries) {
      final endpoint = EndpointEntity(
        id: entry.value,
        name: 'New endpoint',
        apiFormat: entry.key,
        authToken: 'new-token',
        baseUrl: 'https://new.example.com/v1',
      );
      final clone = endpoint.clone(name: 'Cloned endpoint');
      expect(clone.id, isEmpty);
      await repository.insert(clone.copyWith(id: endpoint.id));

      final row =
          (await laconic.table('endpoints').where('id', endpoint.id).get())
              .single
              .toMap();
      expect(row['api_format'], entry.value);
      expect(row['anthropic_auth_token'], 'new-token');
      expect(row['anthropic_base_url'], 'https://new.example.com/v1');
    }
  });
}
