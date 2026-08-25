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
      expect(authHeadersOf(request), {'x-api-key': endpointToken});
    });

    test('preserve: 客户端无认证头 → 默认 x-api-key', () {
      final request = buildRequest(EndpointAuthMode.preserve);
      expect(authHeadersOf(request), {'x-api-key': endpointToken});
    });

    test('xApiKey: 客户端带 Bearer → 强制 x-api-key', () {
      final request = buildRequest(
        EndpointAuthMode.xApiKey,
        clientHeaders: clientBearer,
      );
      expect(authHeadersOf(request), {'x-api-key': endpointToken});
    });

    test('xApiKey: 客户端带 x-api-key → 保持 x-api-key', () {
      final request = buildRequest(
        EndpointAuthMode.xApiKey,
        clientHeaders: clientXApiKey,
      );
      expect(authHeadersOf(request), {'x-api-key': endpointToken});
    });

    test('xApiKey: 客户端无认证头 → x-api-key', () {
      final request = buildRequest(EndpointAuthMode.xApiKey);
      expect(authHeadersOf(request), {'x-api-key': endpointToken});
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

  group('ProxyServerRequestHandler 1M 上下文注入', () {
    final handler = ProxyServerRequestHandler(const ProxyServerConfig());

    tearDownAll(handler.close);

    http.Request buildRequest({
      Map<String, String>? clientHeaders,
      Map<String, dynamic>? bodyJson,
    }) {
      final endpoint = EndpointEntity(
        id: 'ep-1',
        name: 'Test Endpoint',
        anthropicAuthToken: 'sk-endpoint-token',
        anthropicBaseUrl: 'https://api.example.com',
      );
      final shelfRequest = shelf.Request(
        'POST',
        Uri.parse('http://localhost:9000/v1/messages'),
        headers: clientHeaders ?? const {},
      );
      final body = utf8.encode(
        jsonEncode(
          bodyJson ??
              {
                'model': 'claude-opus-5',
                'max_tokens': 100,
                'messages': [
                  {'role': 'user', 'content': 'Hello'},
                ],
              },
        ),
      );
      return handler.prepareRequest(shelfRequest, endpoint, body);
    }

    const expectedBetas = 'context-1m-2025-08-07,max-tokens-1m';

    test('客户端未带 anthropic-beta → 注入两个标记', () {
      expect(buildRequest().headers['anthropic-beta'], expectedBetas);
    });

    test('客户端带空 anthropic-beta → 不产生前导逗号', () {
      final request = buildRequest(clientHeaders: {'anthropic-beta': ''});
      expect(request.headers['anthropic-beta'], isNot(startsWith(',')));
      expect(request.headers['anthropic-beta'], expectedBetas);
    });

    test('客户端带纯空白 anthropic-beta → 空段被过滤', () {
      final request = buildRequest(clientHeaders: {'anthropic-beta': ' , '});
      expect(request.headers['anthropic-beta'], expectedBetas);
    });

    test('客户端已带其中一个标记 → 去重并保留原有标记', () {
      final request = buildRequest(
        clientHeaders: {
          'anthropic-beta': 'tool-streaming-2025-05-14, context-1m-2025-08-07',
        },
      );
      expect(
        request.headers['anthropic-beta'],
        'tool-streaming-2025-05-14,context-1m-2025-08-07,max-tokens-1m',
      );
    });

    test('请求体不再被注入 thinking 或抬高 max_tokens', () {
      final request = buildRequest(
        bodyJson: {
          'model': 'claude-opus-5',
          'max_tokens': 256,
          'messages': [
            {'role': 'user', 'content': 'Hi'},
          ],
        },
      );
      final decoded =
          jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;

      expect(decoded['max_tokens'], 256);
      expect(decoded.containsKey('thinking'), isFalse);
    });
  });
}
