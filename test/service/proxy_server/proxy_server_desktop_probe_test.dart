import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/default_model_config_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_local_responder.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_service.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_circuit_breaker_registry.dart';
import 'package:code_proxy/service/proxy_server/routing/proxy_server_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

import '../../support/authenticated_http_client.dart';

const _modelConfig = DefaultModelConfig(
  haikuModel: 'configured-haiku',
  sonnetModel: 'configured-sonnet',
  opusModel: 'configured-opus',
);
const _probe = {
  'model': 'configured-haiku',
  'max_tokens': 1,
  'messages': [
    {'role': 'user', 'content': '.'},
  ],
};

void main() {
  setUp(() {
    DefaultModelConfigService.instance.replaceConfigForTesting(_modelConfig);
  });

  group('Desktop probe matching', () {
    late ProxyServerLocalResponder responder;
    late ProxyServerRouter router;
    late ProxyServerCircuitBreakerRegistry registry;
    final endpoint = EndpointEntity(id: 'endpoint', name: 'Endpoint');

    shelf.Response? respond(
      Object? body, {
      String method = 'POST',
      String path = '/v1/messages',
    }) {
      return responder.tryRespond(
        shelf.Request(method, Uri.parse('http://localhost$path')),
        utf8.encode(jsonEncode(body)),
      );
    }

    setUp(() {
      registry = ProxyServerCircuitBreakerRegistry(failureThreshold: 1);
      router = ProxyServerRouter(
        config: const ProxyServerConfig(),
        circuitBreakerRegistry: registry,
      )..setEndpoints([endpoint]);
      responder = ProxyServerLocalResponder(router);
    });

    test('returns a complete local message without a User-Agent', () async {
      final response = respond(_probe)!;
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'application/json');
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body.remove('id'), startsWith('msg_'));
      expect(body, {
        'type': 'message',
        'role': 'assistant',
        'model': 'configured-haiku',
        'content': [
          {'type': 'text', 'text': '.'},
        ],
        'stop_reason': 'end_turn',
        'stop_sequence': null,
        'usage': {'input_tokens': 0, 'output_tokens': 0},
      });
    });

    final otherRequests = <String, Object?>{
      'a real single-token message': {
        ..._probe,
        'messages': [
          {'role': 'user', 'content': 'Answer yes or no'},
        ],
      },
      'another model': {..._probe, 'model': 'configured-sonnet'},
      'another token limit': {..._probe, 'max_tokens': 2},
      'a string token limit': {..._probe, 'max_tokens': '1'},
      'explicit streaming': {..._probe, 'stream': true},
      'explicit non-streaming': {..._probe, 'stream': false},
      'system instructions': {..._probe, 'system': 'Reply briefly'},
      'tools': {..._probe, 'tools': <Object>[]},
      'extra message fields': {
        ..._probe,
        'messages': [
          {'role': 'user', 'content': '.', 'name': 'user'},
        ],
      },
      'an assistant message': {
        ..._probe,
        'messages': [
          {'role': 'assistant', 'content': '.'},
        ],
      },
      'conversation history': {
        ..._probe,
        'messages': [
          {'role': 'assistant', 'content': 'Hello'},
          {'role': 'user', 'content': '.'},
        ],
      },
      'content blocks': {
        ..._probe,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '.'},
            ],
          },
        ],
      },
      'missing model': {'max_tokens': 1, 'messages': _probe['messages']},
      'a non-object JSON body': <Object>[],
    };
    for (final entry in otherRequests.entries) {
      test('leaves ${entry.key} for forwarding', () {
        expect(respond(entry.value), isNull);
      });
    }

    test('only matches POST /v1/messages and valid JSON', () {
      expect(respond(_probe, method: 'GET'), isNull);
      expect(respond(_probe, path: '/v1/other'), isNull);
      final request = shelf.Request(
        'POST',
        Uri.parse('http://localhost/v1/messages'),
      );
      expect(responder.tryRespond(request, utf8.encode('{invalid')), isNull);
      expect(responder.tryRespond(request, [0xff]), isNull);
    });

    test('uses the current configured Haiku model', () {
      expect(respond(_probe)?.statusCode, 200);
      DefaultModelConfigService.instance.replaceConfigForTesting(
        const DefaultModelConfig(
          haikuModel: 'new-haiku',
          sonnetModel: 'configured-sonnet',
          opusModel: 'configured-opus',
        ),
      );
      expect(respond(_probe), isNull);
      expect(respond({..._probe, 'model': 'new-haiku'})?.statusCode, 200);
    });

    test('does not inspect or reset an enabled endpoint circuit breaker', () {
      router.recordFailure(endpoint);
      expect(registry.getOpenEndpointIds([endpoint.id]), {endpoint.id});
      expect(respond(_probe)?.statusCode, 200);
      expect(registry.getOpenEndpointIds([endpoint.id]), {endpoint.id});
    });
  });

  test('local probe and real forwarding', () async {
    var upstreamHits = 0;
    final statuses = <int>[];
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => upstream.close(force: true));
    upstream.listen((request) async {
      await request.drain<void>();
      upstreamHits++;
      request.response.statusCode = upstreamHits == 1 ? 503 : 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'upstream': true}));
      await request.response.close();
    });
    final service = ProxyServerService(
      authToken: testProxyAuthToken,
      config: ProxyServerConfig(
        port: 0,
        apiTimeoutMs: 3000,
        circuitBreakerFailureThreshold: 2,
      ),
      onRequestCompleted: (_, _, response) => statuses.add(response.statusCode),
    );
    addTearDown(service.stop);
    service.endpoints = [
      EndpointEntity(
        id: 'endpoint',
        name: 'Endpoint',
        anthropicBaseUrl: 'http://127.0.0.1:${upstream.port}',
        anthropicAuthToken: 'upstream-token',
        haikuModel: 'mapped-upstream-haiku',
      ),
    ];
    await service.start();
    final client = http.Client();
    addTearDown(client.close);
    final uri = Uri.parse('http://127.0.0.1:${service.boundPort}/v1/messages');
    const headers = {
      'x-api-key': testProxyAuthToken,
      'content-type': 'application/json',
      'user-agent': 'An unrelated client',
    };

    final local = await client.post(
      uri,
      headers: headers,
      body: jsonEncode(_probe),
    );
    expect(local.statusCode, 200);
    expect(jsonDecode(local.body)['model'], 'configured-haiku');
    expect(upstreamHits, 0);
    expect(statuses, isEmpty);
    expect(service.getOpenCircuitBreakerEndpointIds(['endpoint']), isEmpty);

    final unauthorized = await client.post(uri, body: jsonEncode(_probe));
    expect(unauthorized.statusCode, 401);
    expect(upstreamHits, 0);
    expect(statuses, isEmpty);

    final real = await client.post(
      uri,
      headers: headers,
      body: jsonEncode({
        ..._probe,
        'messages': [
          {'role': 'user', 'content': 'Hello'},
        ],
      }),
    );
    expect(real.statusCode, 200);
    expect(jsonDecode(real.body)['upstream'], true);
    expect(upstreamHits, 2);
    expect(statuses, [503, 200]);

    for (final endpoints in [
      <EndpointEntity>[],
      [EndpointEntity(id: 'disabled', name: 'Disabled', enabled: false)],
    ]) {
      service.endpoints = endpoints;
      final unavailable = await client.post(
        uri,
        headers: headers,
        body: jsonEncode(_probe),
      );
      expect(unavailable.statusCode, 503);
      expect(
        jsonDecode(unavailable.body)['error']['message'],
        'No enabled endpoints',
      );
      expect(upstreamHits, 2);
      expect(statuses, [503, 200]);
    }
  });
}
