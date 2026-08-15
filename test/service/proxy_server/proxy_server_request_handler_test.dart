import 'dart:convert';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

void main() {
  group('ProxyServerRequestHandler auth mode', () {
    const endpointToken = 'sk-endpoint-token';
    final handler = ProxyServerRequestHandler(const ProxyServerConfig());

    tearDownAll(handler.close);

    http.Request buildRequest(
      EndpointAuthMode authMode, {
      Map<String, String>? clientHeaders,
    }) {
      final endpoint = EndpointEntity(
        id: 'ep-1',
        name: 'Test Endpoint',
        authMode: authMode,
        anthropicAuthToken: endpointToken,
        anthropicBaseUrl: 'https://api.example.com',
      );
      final shelfRequest = shelf.Request(
        'POST',
        Uri.parse('http://localhost:9000/v1/messages'),
        headers: clientHeaders ?? const {},
      );
      final body = utf8.encode(
        jsonEncode({
          'model': 'claude-opus-5',
          'max_tokens': 100,
          'messages': [
            {'role': 'user', 'content': 'Hello'},
          ],
        }),
      );
      return handler.prepareRequest(shelfRequest, endpoint, body);
    }

    Map<String, String> authHeadersOf(http.Request request) {
      return {
        if (request.headers.containsKey('x-api-key'))
          'x-api-key': request.headers['x-api-key']!,
        if (request.headers.containsKey('authorization'))
          'authorization': request.headers['authorization']!,
      };
    }

    const clientBearer = {'authorization': 'Bearer cp-client-token'};
    const clientXApiKey = {'x-api-key': 'cp-client-token'};

    test('preserve: 客户端带 Bearer → 转发 Bearer 端点 token', () {
      final request = buildRequest(
        EndpointAuthMode.preserve,
        clientHeaders: clientBearer,
      );
      expect(authHeadersOf(request), {
        'authorization': 'Bearer $endpointToken',
      });
    });

    test('preserve: 客户端带 x-api-key → 转发 x-api-key 端点 token', () {
      final request = buildRequest(
        EndpointAuthMode.preserve,
        clientHeaders: clientXApiKey,
      );
      expect(authHeadersOf(request), {
        'x-api-key': endpointToken,
      });
    });

    test('preserve: 客户端无认证头 → 默认 x-api-key', () {
      final request = buildRequest(EndpointAuthMode.preserve);
      expect(authHeadersOf(request), {
        'x-api-key': endpointToken,
      });
    });

    test('xApiKey: 客户端带 Bearer → 强制 x-api-key', () {
      final request = buildRequest(
        EndpointAuthMode.xApiKey,
        clientHeaders: clientBearer,
      );
      expect(authHeadersOf(request), {
        'x-api-key': endpointToken,
      });
    });

    test('xApiKey: 客户端带 x-api-key → 保持 x-api-key', () {
      final request = buildRequest(
        EndpointAuthMode.xApiKey,
        clientHeaders: clientXApiKey,
      );
      expect(authHeadersOf(request), {
        'x-api-key': endpointToken,
      });
    });

    test('xApiKey: 客户端无认证头 → x-api-key', () {
      final request = buildRequest(EndpointAuthMode.xApiKey);
      expect(authHeadersOf(request), {
        'x-api-key': endpointToken,
      });
    });

    test('bearer: 客户端带 Bearer → 保持 Bearer 端点 token', () {
      final request = buildRequest(
        EndpointAuthMode.bearer,
        clientHeaders: clientBearer,
      );
      expect(authHeadersOf(request), {
        'authorization': 'Bearer $endpointToken',
      });
    });

    test('bearer: 客户端带 x-api-key → 强制 Bearer', () {
      final request = buildRequest(
        EndpointAuthMode.bearer,
        clientHeaders: clientXApiKey,
      );
      expect(authHeadersOf(request), {
        'authorization': 'Bearer $endpointToken',
      });
    });

    test('bearer: 客户端无认证头 → Bearer', () {
      final request = buildRequest(EndpointAuthMode.bearer);
      expect(authHeadersOf(request), {
        'authorization': 'Bearer $endpointToken',
      });
    });
  });
}
