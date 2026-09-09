import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const storedFormats = {
    'anthropic': EndpointApiFormat.anthropic,
    'openaiResponses': EndpointApiFormat.openaiResponses,
    'openaiChat': EndpointApiFormat.openaiChat,
  };

  for (final entry in storedFormats.entries) {
    test('${entry.key} JSON 读取和写回保持原有格式', () {
      final json = {
        'id': 'endpoint-1',
        'name': 'Endpoint',
        'note': 'Existing configuration',
        'enabled': true,
        'weight': 2,
        'authMode': 'bearer',
        'apiFormat': entry.key,
        'anthropicAuthToken': 'test-token',
        'anthropicBaseUrl': 'https://example.com/v1',
        'haikuModel': 'small-model',
        'sonnetModel': 'medium-model',
        'opusModel': 'large-model',
        'fableModel': 'fable-model',
      };

      final endpoint = EndpointEntity.fromJson(json);

      expect(endpoint.apiFormat, entry.value);
      expect(endpoint.authToken, 'test-token');
      expect(endpoint.baseUrl, 'https://example.com/v1');
      expect(endpoint.toJson(), json);
    });
  }

  test('缺失或未知协议值仍按 Anthropic 格式读取', () {
    for (final value in [null, 'openai', 'unknown-format']) {
      final endpoint = EndpointEntity.fromJson({
        'id': 'endpoint-1',
        'name': 'Endpoint',
        'apiFormat': value,
      });
      expect(endpoint.apiFormat, EndpointApiFormat.anthropic);
      expect(endpoint.authToken, isNull);
      expect(endpoint.baseUrl, isNull);
    }
  });
}
