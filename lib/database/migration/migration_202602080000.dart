import 'package:laconic/laconic.dart';

/// 数据库迁移 - 添加原始模型字段
///
/// 变更内容：
/// 1. 添加 origin_model 列 (TEXT, 可为空)
///    用于存储客户端发来的原始模型名称（映射前），便于分析客户端模型使用偏好
class Migration202602080000 {
  static const name = 'migration_202602080000';

  Future<void> migrate(Laconic laconic) => laconic.transaction(() async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    // 旧版可能已加列、尚未登记；只补齐缺失列，并原子提交迁移记录。
    final info = await laconic.select("PRAGMA table_info('request_logs')");
    final columns = info.map((row) => row['name']).toSet();
    if (!columns.contains('origin_model')) {
      await laconic.statement(
        'ALTER TABLE request_logs ADD COLUMN origin_model TEXT',
      );
    }
    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  });
}
