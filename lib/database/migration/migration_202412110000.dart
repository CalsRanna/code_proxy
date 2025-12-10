import 'package:laconic/laconic.dart';

class Migration202412110000 {
  static const name = 'migration_202412110000';

  Future<void> migrate(Laconic laconic) async {
    final count = await laconic
        .table('migrations')
        .where('name', name)
        .count();
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

    // Create proxy_config table
    await laconic.statement('''
      CREATE TABLE IF NOT EXISTS proxy_config (
        id INTEGER PRIMARY KEY,
        listen_address TEXT NOT NULL,
        listen_port INTEGER NOT NULL,
        max_retries INTEGER DEFAULT 3,
        request_timeout INTEGER DEFAULT 300,
        health_check_interval INTEGER DEFAULT 30,
        health_check_timeout INTEGER DEFAULT 10,
        health_check_path TEXT DEFAULT '/health',
        consecutive_failure_threshold INTEGER DEFAULT 3,
        enable_logging INTEGER DEFAULT 1,
        max_log_entries INTEGER DEFAULT 1000,
        response_time_window_size INTEGER DEFAULT 10
      )
    ''');

    // Create endpoint_stats table
    await laconic.statement('''
      CREATE TABLE IF NOT EXISTS endpoint_stats (
        endpoint_id TEXT PRIMARY KEY,
        total_requests INTEGER DEFAULT 0,
        success_requests INTEGER DEFAULT 0,
        failed_requests INTEGER DEFAULT 0,
        last_request_at INTEGER,
        FOREIGN KEY (endpoint_id) REFERENCES endpoints(id) ON DELETE CASCADE
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

    // Insert default proxy config
    await laconic.statement(
      '''
      INSERT OR IGNORE INTO proxy_config (
        id, listen_address, listen_port, max_retries, request_timeout,
        health_check_interval, health_check_timeout, health_check_path,
        consecutive_failure_threshold, enable_logging, max_log_entries,
        response_time_window_size
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        1,
        '127.0.0.1',
        9000,
        3,
        300,
        30,
        10,
        '/health',
        3,
        1,
        1000,
        10,
      ],
    );

    await laconic.table('migrations').insert([
      {'name': name},
    ]);
  }
}
