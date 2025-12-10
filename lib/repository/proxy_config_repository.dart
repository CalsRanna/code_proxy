import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/proxy_server_config_entity.dart';

/// Proxy Config Repository
///
/// Handles CRUD operations for proxy server configuration
class ProxyConfigRepository {
  final Database _database;

  ProxyConfigRepository(this._database);

  /// Get proxy configuration
  Future<ProxyServerConfigEntity> get() async {
    try {
      final result = await _database.laconic
          .table('proxy_config')
          .where('id', 1)
          .first();

      return _fromRow(result.toMap());
    } catch (e) {
      return const ProxyServerConfigEntity();
    }
  }

  /// Save proxy configuration
  Future<void> save(ProxyServerConfigEntity config) async {
    await _database.laconic.table('proxy_config').where('id', 1).update({
      'listen_address': config.address,
      'listen_port': config.port,
      'max_retries': config.maxRetries,
      'request_timeout': config.requestTimeout,
      'health_check_interval': config.healthCheckInterval,
      'health_check_timeout': config.healthCheckTimeout,
      'health_check_path': config.healthCheckPath,
      'consecutive_failure_threshold': config.consecutiveFailureThreshold,
      'enable_logging': config.enableLogging ? 1 : 0,
      'max_log_entries': config.maxLogEntries,
      'response_time_window_size': config.responseTimeWindowSize,
    });
  }

  /// Convert database row to ProxyServerConfigEntity
  ProxyServerConfigEntity _fromRow(Map<String, dynamic> row) {
    return ProxyServerConfigEntity(
      address: row['listen_address'] as String,
      port: row['listen_port'] as int,
      maxRetries: row['max_retries'] as int,
      requestTimeout: row['request_timeout'] as int,
      healthCheckInterval: row['health_check_interval'] as int,
      healthCheckTimeout: row['health_check_timeout'] as int,
      healthCheckPath: row['health_check_path'] as String,
      consecutiveFailureThreshold: row['consecutive_failure_threshold'] as int,
      enableLogging: (row['enable_logging'] as int) == 1,
      maxLogEntries: row['max_log_entries'] as int,
      responseTimeWindowSize: row['response_time_window_size'] as int,
    );
  }
}
