import 'package:laconic/laconic.dart';

class Migration202412110000 {
  static const name = 'migration_202412110000';

  Future<void> migrate(Laconic laconic) async {
    final count = await laconic.table('migrations').where('name', name).count();
    if (count > 0) return;

    // Create endpoints table
    await laconic.statement('''
      CREATE TABLE IF NOT EXISTS endpoints (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        note TEXT,
        enabled INTEGER DEFAULT 1,
        weight INTEGER DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        anthropic_auth_token TEXT,
        anthropic_base_url TEXT,
        api_timeout_ms INTEGER,
        anthropic_model TEXT,
        anthropic_small_fast_model TEXT,
        anthropic_default_haiku_model TEXT,
        anthropic_default_sonnet_model TEXT,
        anthropic_default_opus_model TEXT,
        claude_code_disable_nonessential_traffic INTEGER DEFAULT 0
      )
    ''');

    // Create request_logs table
    await laconic.statement('''
      CREATE TABLE IF NOT EXISTS request_logs (
        id TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        endpoint_id TEXT NOT NULL,
        endpoint_name TEXT NOT NULL,
        path TEXT NOT NULL,
        method TEXT NOT NULL,
        status_code INTEGER,
        response_time INTEGER,
        success INTEGER NOT NULL,
        error TEXT,
        level TEXT NOT NULL,
        header TEXT,
        message TEXT,
        model TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        raw_header TEXT,
        raw_request TEXT,
        raw_response TEXT,
        FOREIGN KEY (endpoint_id) REFERENCES endpoints(id) ON DELETE CASCADE
      )
    ''');

    // Create indexes for request_logs
    await laconic.statement('''
      CREATE INDEX IF NOT EXISTS idx_request_logs_timestamp
      ON request_logs(timestamp DESC)
    ''');

    await laconic.statement('''
      CREATE INDEX IF NOT EXISTS idx_request_logs_endpoint_id
      ON request_logs(endpoint_id)
    ''');

    await laconic.statement('''
      CREATE INDEX IF NOT EXISTS idx_request_logs_level
      ON request_logs(level)
    ''');

    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
