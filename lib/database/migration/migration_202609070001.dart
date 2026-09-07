import 'package:laconic/laconic.dart';

/// 数据库迁移 - 端点模型映射列重命名:去掉 anthropic_default_ 前缀
///
/// v2 大版本统一端点级模型映射列名为无前缀(haiku_model 等),与全局
/// default_model.yaml 的新键(haiku_model 等)平行。旧列名仍保留的存量库
/// 自动 RENAME 迁移;已是新列名的库跳过(幂等)。
///
/// 注意:不依赖 m1(202605100000)的 DROP+重建时序——该迁移在旧列名
/// anthropic_default_haiku_model 等存在时用 RENAME 覆盖,否则跳过。
class Migration202609070001 {
  static const name = 'migration_202609070001';

  Future<void> migrate(Laconic laconic) async {
    final count =
        await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    final tableInfo = await laconic.select("PRAGMA table_info('endpoints')");
    final columns = tableInfo.map((r) => r['name'] as String).toSet();

    // 旧列名 → 新列名(仅当旧列存在且新列不存在时 RENAME)
    const renames = {
      'anthropic_default_haiku_model': 'haiku_model',
      'anthropic_default_sonnet_model': 'sonnet_model',
      'anthropic_default_opus_model': 'opus_model',
      'anthropic_default_fable_model': 'fable_model',
    };

    for (final entry in renames.entries) {
      final oldCol = entry.key;
      final newCol = entry.value;
      if (columns.contains(oldCol) && !columns.contains(newCol)) {
        await laconic.statement(
          'ALTER TABLE endpoints RENAME COLUMN $oldCol TO $newCol',
        );
      }
    }

    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
