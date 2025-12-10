import 'package:code_proxy/database/database.dart';
import 'package:code_proxy/model/endpoint_entity.dart';

/// Endpoint Repository
///
/// Handles CRUD operations for API endpoints
/// Provides business logic for endpoint management
class EndpointRepository {
  final Database _database;

  EndpointRepository(this._database);

  /// Get all endpoints
  Future<List<EndpointEntity>> getAll() async {
    final results = await _database.laconic
        .table('endpoints')
        .orderBy('created_at', direction: 'asc')
        .get();

    return results.map((r) => _fromRow(r.toMap())).toList();
  }

  /// Get endpoint by ID
  Future<EndpointEntity?> getById(String id) async {
    try {
      final result = await _database.laconic
          .table('endpoints')
          .where('id', id)
          .first();

      return _fromRow(result.toMap());
    } catch (e) {
      return null;
    }
  }

  /// Insert a new endpoint
  Future<void> insert(EndpointEntity endpoint) async {
    await _database.laconic.table('endpoints').insert([
      {
        'id': endpoint.id,
        'name': endpoint.name,
        'note': endpoint.note,
        'enabled': endpoint.enabled ? 1 : 0,
        'weight': endpoint.weight,
        'created_at': endpoint.createdAt,
        'updated_at': endpoint.updatedAt,
        'anthropic_auth_token': endpoint.anthropicAuthToken,
        'anthropic_base_url': endpoint.anthropicBaseUrl,
        'api_timeout_ms': endpoint.apiTimeoutMs,
        'anthropic_model': endpoint.anthropicModel,
        'anthropic_small_fast_model': endpoint.anthropicSmallFastModel,
        'anthropic_default_haiku_model': endpoint.anthropicDefaultHaikuModel,
        'anthropic_default_sonnet_model': endpoint.anthropicDefaultSonnetModel,
        'anthropic_default_opus_model': endpoint.anthropicDefaultOpusModel,
        'claude_code_disable_nonessential_traffic':
            endpoint.claudeCodeDisableNonessentialTraffic ? 1 : 0,
      },
    ]);
  }

  /// Update an existing endpoint
  Future<void> update(EndpointEntity endpoint) async {
    await _database.laconic.table('endpoints').where('id', endpoint.id).update({
      'name': endpoint.name,
      'note': endpoint.note,
      'enabled': endpoint.enabled ? 1 : 0,
      'weight': endpoint.weight,
      'updated_at': endpoint.updatedAt,
      'anthropic_auth_token': endpoint.anthropicAuthToken,
      'anthropic_base_url': endpoint.anthropicBaseUrl,
      'api_timeout_ms': endpoint.apiTimeoutMs,
      'anthropic_model': endpoint.anthropicModel,
      'anthropic_small_fast_model': endpoint.anthropicSmallFastModel,
      'anthropic_default_haiku_model': endpoint.anthropicDefaultHaikuModel,
      'anthropic_default_sonnet_model': endpoint.anthropicDefaultSonnetModel,
      'anthropic_default_opus_model': endpoint.anthropicDefaultOpusModel,
      'claude_code_disable_nonessential_traffic':
          endpoint.claudeCodeDisableNonessentialTraffic ? 1 : 0,
    });
  }

  /// Delete an endpoint by ID
  Future<void> delete(String id) async {
    await _database.laconic.table('endpoints').where('id', id).delete();
  }

  /// Clear all endpoints
  Future<void> clearAll() async {
    await _database.laconic.table('endpoints').delete();
  }

  /// Get enabled endpoints only
  Future<List<EndpointEntity>> getEnabled() async {
    final results = await _database.laconic
        .table('endpoints')
        .where('enabled', 1)
        .orderBy('weight', direction: 'desc')
        .get();

    return results.map((r) => _fromRow(r.toMap())).toList();
  }

  /// Convert database row to EndpointEntity
  EndpointEntity _fromRow(Map<String, dynamic> row) {
    return EndpointEntity(
      id: row['id'] as String,
      name: row['name'] as String,
      note: row['note'] as String?,
      enabled: (row['enabled'] as int) == 1,
      weight: row['weight'] as int,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      anthropicAuthToken: row['anthropic_auth_token'] as String?,
      anthropicBaseUrl: row['anthropic_base_url'] as String?,
      apiTimeoutMs: row['api_timeout_ms'] as int?,
      anthropicModel: row['anthropic_model'] as String?,
      anthropicSmallFastModel: row['anthropic_small_fast_model'] as String?,
      anthropicDefaultHaikuModel: row['anthropic_default_haiku_model'] as String?,
      anthropicDefaultSonnetModel: row['anthropic_default_sonnet_model'] as String?,
      anthropicDefaultOpusModel: row['anthropic_default_opus_model'] as String?,
      claudeCodeDisableNonessentialTraffic:
          (row['claude_code_disable_nonessential_traffic'] as int?) == 1,
    );
  }
}
