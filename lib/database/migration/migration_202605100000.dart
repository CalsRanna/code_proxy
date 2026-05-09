import 'package:laconic/laconic.dart';

/// 数据库迁移 - 移除 endpoints 表的 anthropic_model 和 anthropic_small_fast_model 列
///
/// ANTHROPIC_MODEL 和 ANTHROPIC_SMALL_FAST_MODEL 环境变量已不再使用：
/// - ANTHROPIC_MODEL: 移除后 Claude Code 直接发送真实模型 ID，代理端透传
/// - ANTHROPIC_SMALL_FAST_MODEL: Claude Code 已弃用，由 ANTHROPIC_DEFAULT_HAIKU_MODEL 替代
class Migration202605100000 {
  static const name = 'migration_202605100000';

  Future<void> migrate(Laconic laconic) async {
    final count =
        await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    final tableInfo = await laconic.select("PRAGMA table_info('endpoints')");
    final columns = tableInfo.map((r) => r['name'] as String).toSet();

    if (!columns.contains('anthropic_model') &&
        !columns.contains('anthropic_small_fast_model')) {
      await laconic.table('migrations').insert([
        {'name': name},
      ]);
      return;
    }

    await laconic.statement('DROP TABLE IF EXISTS endpoints_new');

    await laconic.statement('''
      CREATE TABLE endpoints_new (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        note TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        weight INTEGER NOT NULL DEFAULT 1,
        anthropic_auth_token TEXT,
        anthropic_base_url TEXT,
        anthropic_default_haiku_model TEXT,
        anthropic_default_sonnet_model TEXT,
        anthropic_default_opus_model TEXT
      )
    ''');

    await laconic.statement('''
      INSERT INTO endpoints_new (
        id, name, note, enabled, weight,
        anthropic_auth_token, anthropic_base_url,
        anthropic_default_haiku_model, anthropic_default_sonnet_model, anthropic_default_opus_model
      )
      SELECT
        id, name, note, enabled, weight,
        anthropic_auth_token, anthropic_base_url,
        anthropic_default_haiku_model, anthropic_default_sonnet_model, anthropic_default_opus_model
      FROM endpoints
    ''');

    await laconic.statement('BEGIN TRANSACTION');
    try {
      await laconic.statement('DROP TABLE endpoints');
      await laconic.statement(
          'ALTER TABLE endpoints_new RENAME TO endpoints');
      await laconic.table('migrations').insert([
        {'name': name},
      ]);
      await laconic.statement('COMMIT');
    } catch (e) {
      await laconic.statement('ROLLBACK');
      rethrow;
    }
  }
}
