import 'package:laconic/laconic.dart';

/// 数据库迁移 - 清理 endpoints 表多余字段
///
/// 变更内容：
/// 移除以下非标准字段：
/// - created_at
/// - updated_at
/// - api_timeout_ms
/// - claude_code_disable_nonessential_traffic
class Migration202601100000 {
  static const name = 'migration_202601100000';

  Future<void> migrate(Laconic laconic) async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) {
      return;
    }

    // 检查是否存在需要清理的字段
    final tableInfo = await laconic.select("PRAGMA table_info('endpoints')");
    final columns = tableInfo.map((r) => r['name'] as String).toSet();

    // 如果不存在多余字段，跳过迁移
    if (!columns.contains('created_at') && !columns.contains('updated_at')) {
      await laconic.table('migrations').insert([
        {'name': name},
      ]);
      return;
    }

    // SQLite 不支持 DROP COLUMN，需要重建表
    // 1. 创建新表（标准结构）
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
        anthropic_default_opus_model TEXT,
        forbidden INTEGER DEFAULT 0,
        forbidden_until INTEGER
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
        anthropic_default_opus_model,
        forbidden,
        forbidden_until
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
        anthropic_default_opus_model,
        COALESCE(forbidden, 0),
        forbidden_until
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
