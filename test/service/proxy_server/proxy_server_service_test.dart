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

    test('count_tokens 黑名单命中 5xx 时应直接返回首个上游响应', () async {
      var firstHits = 0;
      var secondHits = 0;
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          firstHits++;
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('count_tokens unsupported');
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
        body: jsonEncode({'model': 'claude-3-7-sonnet'}),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.body, 'count_tokens unsupported');
      expect(firstHits, 1);
      expect(secondHits, 0);
      expect(
        service!.getOpenCircuitBreakerEndpointIds({'ep-1', 'ep-2'}),
        isEmpty,
      );
    });

    test('count_tokens 黑名单命中异常时应直接返回原始错误且不故障转移', () async {
      var secondHits = 0;
      final unusedPort = await _allocateUnusedPort();
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
          apiTimeoutMs: 500,
          circuitBreakerFailureThreshold: 1,
        ),
      );
      service!.endpoints = [
        _buildEndpoint('ep-1', unusedPort),
        _buildEndpoint('ep-2', upstreamServers[0].port),
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
        body: jsonEncode({'model': 'claude-3-7-sonnet'}),
      );

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(
        response.body,
        anyOf(contains('Connection refused'), contains('SocketException')),
      );
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

Future<int> _allocateUnusedPort() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close(force: true);
  return port;
}
