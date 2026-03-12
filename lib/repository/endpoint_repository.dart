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
        'anthropic_auth_token': endpoint.anthropicAuthToken,
        'anthropic_base_url': endpoint.anthropicBaseUrl,
        'anthropic_model': endpoint.anthropicModel,
        'anthropic_small_fast_model': endpoint.anthropicSmallFastModel,
        'anthropic_default_haiku_model': endpoint.anthropicDefaultHaikuModel,
        'anthropic_default_sonnet_model': endpoint.anthropicDefaultSonnetModel,
        'anthropic_default_opus_model': endpoint.anthropicDefaultOpusModel,
      },
    ]);
  }

  /// Update an existing endpoint.
  /// `clearForbidden` is only used when the user manually re-enables an endpoint.
  Future<void> update(
    EndpointEntity endpoint, {
    bool clearForbidden = false,
  }) async {
    await _database.laconic.table('endpoints').where('id', endpoint.id).update({
      'name': endpoint.name,
      'note': endpoint.note,
      'enabled': endpoint.enabled ? 1 : 0,
      'weight': endpoint.weight,
      'anthropic_auth_token': endpoint.anthropicAuthToken,
      'anthropic_base_url': endpoint.anthropicBaseUrl,
      'anthropic_model': endpoint.anthropicModel,
      'anthropic_small_fast_model': endpoint.anthropicSmallFastModel,
      'anthropic_default_haiku_model': endpoint.anthropicDefaultHaikuModel,
      'anthropic_default_sonnet_model': endpoint.anthropicDefaultSonnetModel,
      'anthropic_default_opus_model': endpoint.anthropicDefaultOpusModel,
      'forbidden': clearForbidden ? 0 : (endpoint.forbidden ? 1 : 0),
      'forbidden_until': clearForbidden ? null : endpoint.forbiddenUntil,
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
        .orderBy('weight', direction: 'asc')
        .get();

    return results.map((r) => _fromRow(r.toMap())).toList();
  }

  /// Mark endpoint as temporarily forbidden
  Future<void> forbid(String id, int durationMs) async {
    final disableUntil = DateTime.now().millisecondsSinceEpoch + durationMs;
    await _database.laconic.table('endpoints').where('id', id).update({
      'forbidden': 1,
      'forbidden_until': disableUntil,
    });
  }

  /// Remove forbidden status from endpoint
  Future<void> unforbid(String id) async {
    await _database.laconic.table('endpoints').where('id', id).update({
      'forbidden': 0,
      'forbidden_until': null,
    });
  }

  /// Check if forbidden status is expired and restore if needed
  Future<bool> checkAndRestoreExpired(String id) async {
    final endpoint = await getById(id);
    if (endpoint == null) return false;

    if (endpoint.forbidden && endpoint.forbiddenUntil != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= endpoint.forbiddenUntil!) {
        await unforbid(id);
        return true;
      }
    }
    return false;
  }

  /// Convert database row to EndpointEntity
  EndpointEntity _fromRow(Map<String, dynamic> row) {
    return EndpointEntity(
      id: row['id'] as String,
      name: row['name'] as String,
      note: row['note'] as String?,
      enabled: (row['enabled'] as int) == 1,
      weight: row['weight'] as int,
      anthropicAuthToken: row['anthropic_auth_token'] as String?,
      anthropicBaseUrl: row['anthropic_base_url'] as String?,
      anthropicModel: row['anthropic_model'] as String?,
      anthropicSmallFastModel: row['anthropic_small_fast_model'] as String?,
      anthropicDefaultHaikuModel:
          row['anthropic_default_haiku_model'] as String?,
      anthropicDefaultSonnetModel:
          row['anthropic_default_sonnet_model'] as String?,
      anthropicDefaultOpusModel: row['anthropic_default_opus_model'] as String?,
      forbidden: (row['forbidden'] as int?) == 1,
      forbiddenUntil: row['forbidden_until'] as int?,
    );
  }
}
