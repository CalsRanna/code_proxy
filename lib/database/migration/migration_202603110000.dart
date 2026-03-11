import 'package:laconic/laconic.dart';

/// 数据库迁移 - 添加缓存 token 字段
///
/// 变更内容：
/// 1. 添加 cache_creation_input_tokens 列 (INTEGER, 可为空)
/// 2. 添加 cache_read_input_tokens 列 (INTEGER, 可为空)
class Migration202603110000 {
  static const name = 'migration_202603110000';

  Future<void> migrate(Laconic laconic) async {
    final count =
        await laconic.table('migrations').where('name', name).count();
    if (count > 0) {
      return;
    }

    await laconic.statement('''
      ALTER TABLE request_logs ADD COLUMN cache_creation_input_tokens INTEGER
    ''');

    await laconic.statement('''
      ALTER TABLE request_logs ADD COLUMN cache_read_input_tokens INTEGER
    ''');

    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
