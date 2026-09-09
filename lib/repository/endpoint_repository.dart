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
        'anthropic_auth_token': endpoint.authToken,
        'anthropic_base_url': endpoint.baseUrl,
        'haiku_model': endpoint.haikuModel,
        'sonnet_model': endpoint.sonnetModel,
        'opus_model': endpoint.opusModel,
        'fable_model': endpoint.fableModel,
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
      'anthropic_auth_token': endpoint.authToken,
      'anthropic_base_url': endpoint.baseUrl,
      'haiku_model': endpoint.haikuModel,
      'sonnet_model': endpoint.sonnetModel,
      'opus_model': endpoint.opusModel,
      'fable_model': endpoint.fableModel,
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
      authToken: row['anthropic_auth_token'] as String?,
      baseUrl: row['anthropic_base_url'] as String?,
      haikuModel: row['haiku_model'] as String?,
      sonnetModel: row['sonnet_model'] as String?,
      opusModel: row['opus_model'] as String?,
      fableModel: row['fable_model'] as String?,
    );
  }
}
