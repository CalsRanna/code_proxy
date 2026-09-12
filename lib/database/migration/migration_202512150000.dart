import 'package:laconic/laconic.dart';

class Migration202512150000 {
  static const name = 'migration_202512150000';

  Future<void> migrate(Laconic laconic) => laconic.transaction(() async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    // 旧版可能已加列、尚未登记；只补齐缺失列，并原子提交迁移记录。
    final info = await laconic.select("PRAGMA table_info('endpoints')");
    final columns = info.map((row) => row['name']).toSet();
    if (!columns.contains('forbidden')) {
      await laconic.statement(
        'ALTER TABLE endpoints ADD COLUMN forbidden INTEGER DEFAULT 0',
      );
    }
    if (!columns.contains('forbidden_until')) {
      await laconic.statement(
        'ALTER TABLE endpoints ADD COLUMN forbidden_until INTEGER',
      );
    }
    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  });
}
