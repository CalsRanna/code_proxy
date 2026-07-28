import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('ProxyServerService', () {
    ProxyServerService? service;
    final upstreamServers = <HttpServer>[];
    http.Client? client;

    tearDown(() async {
      client?.close();
      if (service != null) {
        await service!.stop();
      }
      for (final server in upstreamServers) {
        await server.close(force: true);
      }
      upstreamServers.clear();
    });

    test('count_tokens 由本地应答器处理，不转发到上游', () async {
      var firstHits = 0;
      var secondHits = 0;
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          firstHits++;
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }),
      );
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          secondHits++;
          request.response.statusCode = HttpStatus.ok;
          request.response.write('should not be reached');
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        config: const ProxyServerConfig(
          address: '127.0.0.1',
          port: 0,
          apiTimeoutMs: 2000,
          circuitBreakerFailureThreshold: 1,
        ),
      );
      service!.endpoints = [
        _buildEndpoint('ep-1', upstreamServers[0].port),
        _buildEndpoint('ep-2', upstreamServers[1].port),
      ];
      await service!.start();

      client = http.Client();
      final response = await client!.post(
        Uri.parse(
          'http://127.0.0.1:${service!.boundPort}/v1/messages/count_tokens',
        ),
        headers: {
          'content-type': 'application/json',
          'x-api-key': 'client-token',
        },
        body: jsonEncode({
          'model': 'claude-opus-5',
          'messages': [{'role': 'user', 'content': 'Hello'}],
        }),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body.containsKey('input_tokens'), isTrue);
      expect(body['input_tokens'], greaterThan(0));
      // 不应转发到上游
      expect(firstHits, 0);
      expect(secondHits, 0);
      // 不应触发断路器
      expect(
        service!.getOpenCircuitBreakerEndpointIds({'ep-1', 'ep-2'}),
        isEmpty,
      );
    });

    test('count_tokens 异常也由本地应答器安全兜底', () async {
      // 本地应答器即使没有端点也不会转发，返回 200 + 估算值
      var hit = false;
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          hit = true;
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        config: const ProxyServerConfig(
          address: '127.0.0.1',
          port: 0,
          apiTimeoutMs: 500,
          circuitBreakerFailureThreshold: 1,
        ),
      );
      // 只有一个端点，但 count_tokens 不应使用它
      service!.endpoints = [
        _buildEndpoint('ep-1', upstreamServers[0].port),
      ];
      await service!.start();

      client = http.Client();
      final response = await client!.post(
        Uri.parse(
          'http://127.0.0.1:${service!.boundPort}/v1/messages/count_tokens',
        ),
        headers: {'content-type': 'application/json', 'x-api-key': 'ct'},
        body: jsonEncode({'model': 'claude-3-7-sonnet'}),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(hit, false);
    });

    test('4xx 响应应直接返回且不重试不熔断', () async {
      var firstHits = 0;
      var secondHits = 0;
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          firstHits++;
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('invalid request');
          await request.response.close();
        }),
      );
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          secondHits++;
          request.response.statusCode = HttpStatus.ok;
          request.response.write('should not be reached');
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        config: const ProxyServerConfig(
          address: '127.0.0.1',
          port: 0,
          apiTimeoutMs: 2000,
          circuitBreakerFailureThreshold: 1,
        ),
      );
      service!.endpoints = [
        _buildEndpoint('ep-1', upstreamServers[0].port),
        _buildEndpoint('ep-2', upstreamServers[1].port),
      ];
      await service!.start();

      client = http.Client();
      final response = await client!.post(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
        headers: {
          'content-type': 'application/json',
          'x-api-key': 'client-token',
        },
        body: jsonEncode({'model': 'claude-3-7-sonnet'}),
      );

      expect(response.statusCode, HttpStatus.badRequest);
      expect(response.body, 'invalid request');
      expect(firstHits, 1);
      expect(secondHits, 0);
      expect(
        service!.getOpenCircuitBreakerEndpointIds({'ep-1', 'ep-2'}),
        isEmpty,
      );
    });
  });
}

EndpointEntity _buildEndpoint(String id, int port) {
  return EndpointEntity(
    id: id,
    name: 'Endpoint $id',
    anthropicBaseUrl: 'http://127.0.0.1:$port',
    anthropicAuthToken: 'upstream-token',
  );
}

Future<HttpServer> _startUpstreamServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}
