import 'package:laconic/laconic.dart';

/// 数据库迁移 - 将原始数据迁移到文件
///
/// 变更内容：
/// 1. 移除 raw_header, raw_request, raw_response 列
/// 2. 添加 log_file_path 列
class Migration202512150001 {
  static const name = 'migration_202512150001';

  Future<void> migrate(Laconic laconic) async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) {
      return;
    }

    // SQLite 不支持 DROP COLUMN，需要重建表
    // 步骤：
    // 1. 创建新表（不含旧字段）
    // 2. 复制数据
    // 3. 删除旧表
    // 4. 重命名新表

    // 1. 创建新表
    await laconic.statement('''
      CREATE TABLE IF NOT EXISTS request_logs_new (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        endpoint_id TEXT NOT NULL,
        endpoint_name TEXT NOT NULL,
        path TEXT NOT NULL,
        method TEXT NOT NULL,
        status_code INTEGER,
        response_time INTEGER,
        model TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER
      )
    ''');

    // 2. 复制数据（不包含 raw_header, raw_request, raw_response）
    await laconic.statement('''
      INSERT INTO request_logs_new (
        id,
        timestamp,
        endpoint_id,
        endpoint_name,
        path,
        method,
        status_code,
        response_time,
        model,
        input_tokens,
        output_tokens
      )
      SELECT
        id,
        timestamp,
        endpoint_id,
        endpoint_name,
        path,
        method,
        status_code,
        response_time,
        model,
        input_tokens,
        output_tokens
      FROM request_logs
    ''');

    // 3. 删除旧表
    await laconic.statement('DROP TABLE request_logs');

    // 4. 重命名新表
    await laconic.statement(
      'ALTER TABLE request_logs_new RENAME TO request_logs',
    );

    // 5. 重建索引
    await laconic.statement('''
      CREATE INDEX IF NOT EXISTS idx_request_logs_timestamp
      ON request_logs(timestamp DESC)
    ''');

    await laconic.statement('''
      CREATE INDEX IF NOT EXISTS idx_request_logs_endpoint_id
      ON request_logs(endpoint_id)
    ''');

    // 记录迁移完成
    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
