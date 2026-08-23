import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../support/authenticated_http_client.dart';

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
        authToken: testProxyAuthToken,
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

      client = AuthenticatedTestClient();
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
          'messages': [
            {'role': 'user', 'content': 'Hello'},
          ],
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
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(
          address: '127.0.0.1',
          port: 0,
          apiTimeoutMs: 500,
          circuitBreakerFailureThreshold: 1,
        ),
      );
      // 只有一个端点，但 count_tokens 不应使用它
      service!.endpoints = [_buildEndpoint('ep-1', upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final response = await client!.post(
        Uri.parse(
          'http://127.0.0.1:${service!.boundPort}/v1/messages/count_tokens',
        ),
        headers: {
          'content-type': 'application/json',
          'x-api-key': testProxyAuthToken,
        },
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
        authToken: testProxyAuthToken,
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

      client = AuthenticatedTestClient();
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

    test('成功响应应向断路器记录成功，间歇性失败不应累积触发误熔断', () async {
      var hits = 0;
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          hits++;
          // 奇数次命中返回 500（首次尝试），偶数次命中返回 200（重试）
          request.response.statusCode = hits.isEven
              ? HttpStatus.ok
              : HttpStatus.internalServerError;
          if (hits.isEven) request.response.write('ok');
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(
          address: '127.0.0.1',
          port: 0,
          apiTimeoutMs: 2000,
          circuitBreakerFailureThreshold: 2,
        ),
      );
      service!.endpoints = [_buildEndpoint('ep-1', upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final uri = Uri.parse(
        'http://127.0.0.1:${service!.boundPort}/v1/messages',
      );
      final headers = {
        'content-type': 'application/json',
        'x-api-key': 'client-token',
      };
      final body = jsonEncode({'model': 'claude-3-7-sonnet'});

      // 请求 1：500 → 重试 → 200。成功必须把失败计数清零。
      final r1 = await client!.post(uri, headers: headers, body: body);
      expect(r1.statusCode, HttpStatus.ok);
      expect(hits, 2);

      // 请求 2：再经历一次失败+重试。若请求 1 的成功未被记录进断路器，
      // 连续失败会在此累积到阈值 2 并立即熔断，客户端将直接收到 500。
      final r2 = await client!.post(uri, headers: headers, body: body);
      expect(r2.statusCode, HttpStatus.ok);
      expect(hits, 4);
      expect(service!.getOpenCircuitBreakerEndpointIds({'ep-1'}), isEmpty);
    });

    test('stop 后重新 start 应重建出站 HttpClient，转发仍然可用', () async {
      var hit = false;
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          hit = true;
          request.response.statusCode = HttpStatus.ok;
          request.response.write('ok');
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(
          address: '127.0.0.1',
          port: 0,
          apiTimeoutMs: 2000,
          circuitBreakerFailureThreshold: 1,
        ),
      );
      service!.endpoints = [_buildEndpoint('ep-1', upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final headers = {
        'content-type': 'application/json',
        'x-api-key': 'client-token',
      };
      final body = jsonEncode({'model': 'claude-3-7-sonnet'});

      await service!.stop();
      await service!.start();

      // 端口变更回滚等场景依赖 stop → start 复用同一服务实例。
      // 若 start 未重建已关闭的出站 HttpClient，此处会抛
      // "Client is already closed" 并返回 500。
      final response = await client!.post(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
        headers: headers,
        body: body,
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(hit, true);
    });

    test('端口绑定失败后释放端口，同一服务实例仍可再次启动', () async {
      final blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstreamServers.add(blocker);
      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: ProxyServerConfig(address: '127.0.0.1', port: blocker.port),
      );

      await expectLater(service!.start(), throwsA(isA<SocketException>()));
      await service!.stop();

      await blocker.close(force: true);
      upstreamServers.remove(blocker);
      await service!.start();

      expect(service!.boundPort, isNotNull);
    });

    test('除 HEAD 外的请求必须提供正确的本地代理令牌', () async {
      var upstreamHits = 0;
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          upstreamHits++;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'type': 'message',
              'content': const [],
              'usage': {'input_tokens': 1, 'output_tokens': 1},
            }),
          );
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(
          address: '127.0.0.1',
          port: 0,
          circuitBreakerFailureThreshold: 1,
        ),
      );
      service!.endpoints = [_buildEndpoint('ep-1', upstreamServers[0].port)];
      await service!.start();

      client = http.Client();
      final uri = Uri.parse(
        'http://127.0.0.1:${service!.boundPort}/v1/messages',
      );
      final body = jsonEncode({'model': 'claude-3-7-sonnet'});

      final missing = await client!.post(uri, body: body);
      expect(missing.statusCode, HttpStatus.unauthorized);
      expect(jsonDecode(missing.body)['error']['type'], 'authentication_error');

      final wrong = await client!.post(
        uri,
        headers: {'x-api-key': 'wrong-token'},
        body: body,
      );
      expect(wrong.statusCode, HttpStatus.unauthorized);
      expect(upstreamHits, 0);

      final health = await client!.head(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/health'),
      );
      expect(health.statusCode, HttpStatus.ok);

      final authorized = await client!.post(
        uri,
        headers: {
          'content-type': 'application/json',
          'authorization': 'bEaReR $testProxyAuthToken',
        },
        body: body,
      );
      expect(authorized.statusCode, HttpStatus.ok);
      expect(upstreamHits, 1);
    });

    test('响应头后 body 停顿应在 idle timeout 内失败', () async {
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"type":"message"');
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 600));
          try {
            await request.response.close();
          } catch (_) {}
        }),
      );

      final logged = <ProxyServerResponse>[];
      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(
          address: '127.0.0.1',
          port: 0,
          apiTimeoutMs: 100,
          circuitBreakerFailureThreshold: 1,
        ),
        onRequestCompleted: (endpoint, request, response) {
          logged.add(response);
        },
      );
      service!.endpoints = [_buildEndpoint('ep-1', upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final stopwatch = Stopwatch()..start();
      final response = await client!.post(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'model': 'claude-3-7-sonnet'}),
      );
      stopwatch.stop();

      expect(response.statusCode, HttpStatus.internalServerError);
      expect(response.body, contains('response body was idle'));
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
      expect(logged, hasLength(1));
      expect(logged.single.statusCode, HttpStatus.badGateway);
      expect(logged.single.errorBody, contains('response body was idle'));
    });

    test('原生 Anthropic SSE 缺少 message_stop 时记录失败并熔断', () async {
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/event-stream',
          );
          request.response.write(
            'event: message_start\n'
            'data: {"type":"message_start","message":{"usage":{}}}\n\n'
            'event: content_block_delta\n'
            'data: {"type":"content_block_delta","index":0,'
            '"delta":{"type":"text_delta","text":"partial"}}\n\n',
          );
          await request.response.close();
        }),
      );

      final logged = Completer<ProxyServerResponse>();
      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(
          address: '127.0.0.1',
          port: 0,
          apiTimeoutMs: 2000,
          circuitBreakerFailureThreshold: 1,
        ),
        onRequestCompleted: (endpoint, request, response) {
          if (!logged.isCompleted) logged.complete(response);
        },
      );
      service!.endpoints = [_buildEndpoint('ep-1', upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final streamed = await client!.send(
        http.Request(
            'POST',
            Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
          )
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode({'model': 'claude-3-7-sonnet', 'stream': true}),
      );
      expect(streamed.statusCode, HttpStatus.ok);
      final clientBody = await streamed.stream.bytesToString();
      expect(clientBody, contains('event: error'));
      expect(clientBody, contains('without completion signal'));
      expect(clientBody, isNot(contains('event: message_stop')));

      final loggedResponse = await logged.future.timeout(
        const Duration(seconds: 1),
      );
      expect(loggedResponse.statusCode, HttpStatus.badGateway);
      expect(loggedResponse.errorBody, contains('completion signal'));
      expect(loggedResponse.responseBody, contains('partial'));
      expect(
        service!.getOpenCircuitBreakerEndpointIds({'ep-1'}),
        contains('ep-1'),
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
