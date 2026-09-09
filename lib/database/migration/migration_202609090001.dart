import 'package:laconic/laconic.dart';

/// 数据库迁移 - 为 request_logs 添加首字用时列
///
/// 变更内容：
/// 1. 添加 ttft_ms 列 (INTEGER, 可为空)：流式响应中首个内容 delta 到达时刻
///    相对发送时刻的毫秒数；历史记录与非流式响应为 NULL。
class Migration202609090001 {
  static const name = 'migration_202609090001';

  Future<void> migrate(Laconic laconic) async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    // 列已存在（例如迁移登记丢失后重跑）时跳过 ALTER，避免 duplicate column。
    final tableInfo = await laconic.select("PRAGMA table_info('request_logs')");
    final columns = tableInfo.map((r) => r['name'] as String).toSet();
    if (!columns.contains('ttft_ms')) {
      await laconic.statement(
        'ALTER TABLE request_logs ADD COLUMN ttft_ms INTEGER',
      );
    }

    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
