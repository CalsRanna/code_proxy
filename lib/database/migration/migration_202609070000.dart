import 'package:laconic/laconic.dart';

/// 数据库迁移 - 为 endpoints 表添加 fable_model 列
///
/// 端点级模型映射新增 Fable 族(与 haiku/sonnet/opus 同构,用于模型发现
/// 入口 → 端点实际模型的映射)。
class Migration202609070000 {
  static const name = 'migration_202609070000';

  Future<void> migrate(Laconic laconic) async {
    final count =
        await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    final tableInfo = await laconic.select("PRAGMA table_info('endpoints')");
    final columns = tableInfo.map((r) => r['name'] as String).toSet();

    if (!columns.contains('fable_model')) {
      await laconic.statement(
        "ALTER TABLE endpoints ADD COLUMN fable_model TEXT",
      );
    }

    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
