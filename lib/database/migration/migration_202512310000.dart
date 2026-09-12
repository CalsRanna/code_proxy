import 'package:laconic/laconic.dart';

/// 数据库迁移 - 添加错误信息字段
///
/// 变更内容：
/// 1. 添加 error_message 列 (TEXT, 可为空)
class Migration202512310000 {
  static const name = 'migration_202512310000';

  Future<void> migrate(Laconic laconic) => laconic.transaction(() async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    // 旧版可能已加列、尚未登记；只补齐缺失列，并原子提交迁移记录。
    final info = await laconic.select("PRAGMA table_info('request_logs')");
    final columns = info.map((row) => row['name']).toSet();
    if (!columns.contains('error_message')) {
      await laconic.statement(
        'ALTER TABLE request_logs ADD COLUMN error_message TEXT',
      );
    }
    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  });
}
