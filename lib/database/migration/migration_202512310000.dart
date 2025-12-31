import 'package:laconic/laconic.dart';

/// 数据库迁移 - 添加错误信息字段
///
/// 变更内容：
/// 1. 添加 error_message 列 (TEXT, 可为空)
class Migration202512310000 {
  static const name = 'migration_202512310000';

  Future<void> migrate(Laconic laconic) async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) {
      return;
    }

    // 添加 error_message 字段
    // TEXT 类型在 SQLite 中没有长度限制,最大可存储约 1GB 数据
    // 对于错误响应,通常在几 KB 范围内,完全满足需求
    await laconic.statement('''
      ALTER TABLE request_logs ADD COLUMN error_message TEXT
    ''');

    // 记录迁移完成
    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
