import 'package:laconic/laconic.dart';

/// 数据库迁移 - 删除 endpoints 表的 forbidden 和 forbidden_until 列
///
/// 变更内容：
/// 断路器状态改为纯内存管理，不再持久化到数据库。
/// 移除 forbidden 和 forbidden_until 列。
class Migration202603130000 {
  static const name = 'migration_202603130000';

  Future<void> migrate(Laconic laconic) async {
    final count =
        await laconic.table('migrations').where('name', name).count();
    if (count > 0) {
      return;
    }

    // 检查是否存在需要删除的字段
    final tableInfo = await laconic.select("PRAGMA table_info('endpoints')");
    final columns = tableInfo.map((r) => r['name'] as String).toSet();

    if (!columns.contains('forbidden') &&
        !columns.contains('forbidden_until')) {
      await laconic.table('migrations').insert([
        {'name': name},
      ]);
      return;
    }

    // SQLite 不支持 DROP COLUMN（3.35.0 之前），需要重建表
    // 1. 创建新表（不含 forbidden 和 forbidden_until）
    await laconic.statement('''
      CREATE TABLE IF NOT EXISTS endpoints_new (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        note TEXT,
        enabled INTEGER DEFAULT 1,
        weight INTEGER DEFAULT 1,
        anthropic_auth_token TEXT,
        anthropic_base_url TEXT,
        anthropic_model TEXT,
        anthropic_small_fast_model TEXT,
        anthropic_default_haiku_model TEXT,
        anthropic_default_sonnet_model TEXT,
        anthropic_default_opus_model TEXT
      )
    ''');

    // 2. 复制数据
    await laconic.statement('''
      INSERT INTO endpoints_new (
        id,
        name,
        note,
        enabled,
        weight,
        anthropic_auth_token,
        anthropic_base_url,
        anthropic_model,
        anthropic_small_fast_model,
        anthropic_default_haiku_model,
        anthropic_default_sonnet_model,
        anthropic_default_opus_model
      )
      SELECT
        id,
        name,
        note,
        enabled,
        weight,
        anthropic_auth_token,
        anthropic_base_url,
        anthropic_model,
        anthropic_small_fast_model,
        anthropic_default_haiku_model,
        anthropic_default_sonnet_model,
        anthropic_default_opus_model
      FROM endpoints
    ''');

    // 3. 删除旧表
    await laconic.statement('DROP TABLE endpoints');

    // 4. 重命名新表
    await laconic.statement('ALTER TABLE endpoints_new RENAME TO endpoints');

    // 记录迁移完成
    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
