import 'package:laconic/laconic.dart';

class Migration202512110000 {
  static const name = 'migration_202512110000';

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
        anthropic_auth_token TEXT,
        anthropic_base_url TEXT,
        anthropic_model TEXT,
        anthropic_small_fast_model TEXT,
        anthropic_default_haiku_model TEXT,
        anthropic_default_sonnet_model TEXT,
        anthropic_default_opus_model TEXT
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
