import 'package:laconic/laconic.dart';

/// 数据库迁移 - 移除 request_logs 的 endpoint_id 列及索引
///
/// 变更内容：
/// 1. 移除 endpoint_id 列（无外键约束，删除端点后变孤立数据，且无查询引用）
/// 2. 移除 idx_request_logs_endpoint_id 索引
/// endpoint_name 已冗余存储端点名称，endpoint_id 不再有实际用途
class Migration202604230000 {
  static const name = 'migration_202604230000';

  Future<void> migrate(Laconic laconic) async {
    final count =
        await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    final tableInfo =
        await laconic.select("PRAGMA table_info('request_logs')");
    final columns = tableInfo.map((r) => r['name'] as String).toSet();

    if (!columns.contains('endpoint_id')) {
      // endpoint_id 列已不存在，说明迁移已完成
      await laconic.table('migrations').insert([
        {'name': name},
      ]);
      return;
    }

    // SQLite 不支持 DROP COLUMN，需要重建表
    // 清理可能残留的临时表
    await laconic.statement('DROP TABLE IF EXISTS request_logs_new');

    // 1. 创建新表（不含 endpoint_id）
    await laconic.statement('''
      CREATE TABLE request_logs_new (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        endpoint_name TEXT NOT NULL,
        path TEXT NOT NULL,
        method TEXT NOT NULL,
        status_code INTEGER,
        response_time INTEGER,
        model TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        error_message TEXT,
        origin_model TEXT,
        cache_creation_input_tokens INTEGER,
        cache_read_input_tokens INTEGER
      )
    ''');

    // 2. 复制数据（不含 endpoint_id）
    await laconic.statement('''
      INSERT INTO request_logs_new (
        id,
        timestamp,
        endpoint_name,
        path,
        method,
        status_code,
        response_time,
        model,
        input_tokens,
        output_tokens,
        error_message,
        origin_model,
        cache_creation_input_tokens,
        cache_read_input_tokens
      )
      SELECT
        id,
        timestamp,
        endpoint_name,
        path,
        method,
        status_code,
        response_time,
        model,
        input_tokens,
        output_tokens,
        error_message,
        origin_model,
        cache_creation_input_tokens,
        cache_read_input_tokens
      FROM request_logs
    ''');

    // 3. 在事务中执行不可逆操作，确保原子性
    await laconic.statement('BEGIN TRANSACTION');
    try {
      await laconic.statement('DROP TABLE request_logs');
      await laconic.statement(
          'ALTER TABLE request_logs_new RENAME TO request_logs');
      // 重建时间戳索引（不再重建 endpoint_id 索引）
      await laconic.statement('''
        CREATE INDEX IF NOT EXISTS idx_request_logs_timestamp
        ON request_logs(timestamp DESC)
      ''');
      await laconic.table('migrations').insert([
        {'name': name},
      ]);
      await laconic.statement('COMMIT');
    } catch (e) {
      await laconic.statement('ROLLBACK');
      rethrow;
    }
  }
}