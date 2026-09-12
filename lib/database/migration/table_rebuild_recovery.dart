import 'package:laconic/laconic.dart';

/// 恢复旧版非事务重建遗留的表；调用方必须在迁移事务内执行。
Future<void> recoverTableRebuild(Laconic laconic, String table) async {
  final staging = '${table}_new';
  final rows = await laconic.select(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?)",
    [table, staging],
  );
  final names = rows.map((row) => row['name']).toSet();
  if (names.contains(table)) {
    // 原表仍在：临时副本可由原表重新生成，避免再次复制时主键冲突。
    if (names.contains(staging)) {
      await laconic.statement('DROP TABLE $staging');
    }
  } else if (names.contains(staging)) {
    // DROP 已提交但 RENAME 未执行：临时表是唯一的数据副本。
    await laconic.statement('ALTER TABLE $staging RENAME TO $table');
  } else {
    throw StateError('Cannot recover missing table $table');
  }
}
