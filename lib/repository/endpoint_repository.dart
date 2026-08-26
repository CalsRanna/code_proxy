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
        .orderBy('weight', direction: 'asc')
        .get();

    return results.map((r) => _fromRow(r.toMap())).toList();
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
        'auth_mode': endpoint.authMode.name,
        'api_format': endpoint.apiFormat.name,
        'anthropic_auth_token': endpoint.anthropicAuthToken,
        'anthropic_base_url': endpoint.anthropicBaseUrl,
        'anthropic_default_haiku_model': endpoint.anthropicDefaultHaikuModel,
        'anthropic_default_sonnet_model': endpoint.anthropicDefaultSonnetModel,
        'anthropic_default_opus_model': endpoint.anthropicDefaultOpusModel,
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
      'auth_mode': endpoint.authMode.name,
      'api_format': endpoint.apiFormat.name,
      'anthropic_auth_token': endpoint.anthropicAuthToken,
      'anthropic_base_url': endpoint.anthropicBaseUrl,
      'anthropic_default_haiku_model': endpoint.anthropicDefaultHaikuModel,
      'anthropic_default_sonnet_model': endpoint.anthropicDefaultSonnetModel,
      'anthropic_default_opus_model': endpoint.anthropicDefaultOpusModel,
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

  /// Convert database row to EndpointEntity
  EndpointEntity _fromRow(Map<String, dynamic> row) {
    return EndpointEntity(
      id: row['id'] as String,
      name: row['name'] as String,
      note: row['note'] as String?,
      enabled: (row['enabled'] as int) == 1,
      weight: row['weight'] as int,
      authMode: EndpointAuthMode.values.firstWhere(
        (mode) => mode.name == row['auth_mode'],
        orElse: () => EndpointAuthMode.preserve,
      ),
      apiFormat: apiFormatFromString(row['api_format'] as String?),
      anthropicAuthToken: row['anthropic_auth_token'] as String?,
      anthropicBaseUrl: row['anthropic_base_url'] as String?,
      anthropicDefaultHaikuModel:
          row['anthropic_default_haiku_model'] as String?,
      anthropicDefaultSonnetModel:
          row['anthropic_default_sonnet_model'] as String?,
      anthropicDefaultOpusModel: row['anthropic_default_opus_model'] as String?,
    );
  }
}
