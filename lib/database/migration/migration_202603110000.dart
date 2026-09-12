import 'package:laconic/laconic.dart';

/// 数据库迁移 - 添加缓存 token 字段
///
/// 变更内容：
/// 1. 添加 cache_creation_input_tokens 列 (INTEGER, 可为空)
/// 2. 添加 cache_read_input_tokens 列 (INTEGER, 可为空)
class Migration202603110000 {
  static const name = 'migration_202603110000';

  Future<void> migrate(Laconic laconic) => laconic.transaction(() async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    // 旧版可能已加列、尚未登记；只补齐缺失列，并原子提交迁移记录。
    final info = await laconic.select("PRAGMA table_info('request_logs')");
    final columns = info.map((row) => row['name']).toSet();
    if (!columns.contains('cache_creation_input_tokens')) {
      await laconic.statement(
        'ALTER TABLE request_logs ADD COLUMN cache_creation_input_tokens INTEGER',
      );
    }
    if (!columns.contains('cache_read_input_tokens')) {
      await laconic.statement(
        'ALTER TABLE request_logs ADD COLUMN cache_read_input_tokens INTEGER',
      );
    }
    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  });
}
