import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../support/authenticated_http_client.dart';

void main() {
  group('OpenAI Responses API 端点格式转换（端到端）', () {
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

    EndpointEntity buildResponsesEndpoint(int port, {String id = 'ep-resp'}) {
      return EndpointEntity(
        id: id,
        name: 'OpenAI Responses Endpoint',
        apiFormat: EndpointApiFormat.openaiResponses,
        anthropicBaseUrl: 'http://127.0.0.1:$port',
        anthropicAuthToken: 'upstream-token',
      );
    }

    test('非流式：请求转换为 Responses 格式转发，响应转换回 Anthropic 格式', () async {
      String? capturedPath;
      String? capturedAuth;
      Map<String, dynamic>? capturedBody;

      upstreamServers.add(
        await _startUpstreamServer((request) async {
          capturedPath = request.uri.path;
          capturedAuth = request.headers.value('authorization');
          capturedBody =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;

          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'id': 'resp_123',
            'object': 'response',
            'model': 'gpt-5',
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'content': [
                  {'type': 'output_text', 'text': 'Hello from GPT'},
                ],
              },
            ],
            'usage': {
              'input_tokens': 42,
              'input_tokens_details': {'cached_tokens': 20},
              'output_tokens': 7,
            },
          }));
          await request.response.close();
        }),
      );

      ProxyServerRequest? loggedRequest;
      ProxyServerResponse? loggedResponse;
      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(address: '127.0.0.1', port: 0),
        onRequestCompleted: (endpoint, request, response) {
          loggedRequest = request;
          loggedResponse = response;
        },
      );
      service!.endpoints = [buildResponsesEndpoint(upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final response = await client!.post(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
        headers: {
          'content-type': 'application/json',
          'x-api-key': 'client-token',
          'anthropic-version': '2023-06-01',
          'anthropic-beta': 'context-1m-2025-08-07',
        },
        body: jsonEncode({
          'model': 'test-model-x',
          'max_tokens': 1024,
          'stream': false,
          'system': 'You are helpful.',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
      );

      // 上游收到的是 Responses API 格式
      expect(capturedPath, '/v1/responses');
      expect(capturedAuth, 'Bearer upstream-token');
      expect(capturedBody!['model'], 'test-model-x');
      expect(capturedBody!['store'], false);
      expect(capturedBody!['max_output_tokens'], 1024);
      expect(capturedBody!['instructions'], 'You are helpful.');
      expect(capturedBody!['input'][0]['role'], 'user');
      // Anthropic 专有头不透传
      expect(
        (capturedBody!['input'] as List),
        isNot(contains('anthropic-beta')),
      );

      // 审计记录：请求双向留痕（原文 Anthropic 格式 + 转发 Responses 格式）
      final clientRequestBody =
          jsonDecode(loggedRequest!.originalBody!) as Map<String, dynamic>;
      expect(clientRequestBody['model'], 'test-model-x');
      expect(clientRequestBody['max_tokens'], 1024);
      expect(jsonDecode(loggedRequest!.body), capturedBody);

      // 审计记录：响应双向留痕（上游 JSON 原文 + 转换后 Anthropic 格式）
      final rawResponseJson =
          jsonDecode(loggedResponse!.rawResponseBody!) as Map<String, dynamic>;
      expect(rawResponseJson['id'], 'resp_123');
      expect(rawResponseJson['object'], 'response');
      final convertedLogBody =
          jsonDecode(loggedResponse!.responseBody!) as Map<String, dynamic>;
      expect(convertedLogBody['type'], 'message');
      expect(convertedLogBody['content'], [
        {'type': 'text', 'text': 'Hello from GPT'},
      ]);

      // 客户端收到的是 Anthropic 格式
      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['type'], 'message');
      expect(body['role'], 'assistant');
      // model 回填客户端原始模型名
      expect(body['model'], 'test-model-x');
      expect(body['content'], [
        {'type': 'text', 'text': 'Hello from GPT'},
      ]);
      expect(body['stop_reason'], 'end_turn');
      expect(body['usage']['input_tokens'], 42);
      expect(body['usage']['output_tokens'], 7);
      expect(body['usage']['cache_read_input_tokens'], 20);
    });

    test('非流式工具调用：function_call → tool_use，stop_reason=tool_use', () async {
      Map<String, dynamic>? capturedBody;

      upstreamServers.add(
        await _startUpstreamServer((request) async {
          capturedBody =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;

          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'id': 'resp_tool',
            'model': 'gpt-5',
            'status': 'completed',
            'output': [
              {
                'type': 'function_call',
                'id': 'fc_1',
                'call_id': 'call_abc',
                'name': 'get_weather',
                'arguments': '{"city":"Tokyo"}',
              },
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }));
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(address: '127.0.0.1', port: 0),
      );
      service!.endpoints = [buildResponsesEndpoint(upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final response = await client!.post(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'model': 'm',
          'max_tokens': 1024,
          'tools': [
            {
              'name': 'get_weather',
              'description': 'Get weather',
              'input_schema': {
                'type': 'object',
                'properties': {'city': {'type': 'string'}},
              },
            },
          ],
          'messages': [
            {'role': 'user', 'content': 'weather in Tokyo?'},
          ],
        }),
      );

      // 上游 tools 为扁平 function 结构
      expect((capturedBody!['tools'] as List)[0], {
        'type': 'function',
        'name': 'get_weather',
        'description': 'Get weather',
        'parameters': {
          'type': 'object',
          'properties': {'city': {'type': 'string'}},
        },
      });

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['stop_reason'], 'tool_use');
      expect(body['content'], [
        {
          'type': 'tool_use',
          'id': 'call_abc',
          'name': 'get_weather',
          'input': {'city': 'Tokyo'},
        },
      ]);
    });

    test('流式：Responses SSE 事件流转换为完整 Anthropic SSE 事件序列', () async {
      String? capturedPath;

      upstreamServers.add(
        await _startUpstreamServer((request) async {
          capturedPath = request.uri.path;

          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/event-stream',
          );
          void event(Map<String, dynamic> data) => request.response.write(
                'event: ${data['type']}\ndata: ${jsonEncode(data)}\n\n',
              );

          event({'type': 'response.created', 'response': {'id': 'resp_s'}});
          event({
            'type': 'response.output_item.added',
            'item': {
              'type': 'message',
              'role': 'assistant',
              'status': 'in_progress',
              'content': [],
            },
          });
          event({
            'type': 'response.output_text.delta',
            'delta': 'Hello',
          });
          event({
            'type': 'response.output_text.delta',
            'delta': ' stream',
          });
          event({
            'type': 'response.completed',
            'response': {
              'id': 'resp_s',
              'status': 'completed',
              'usage': {
                'input_tokens': 33,
                'input_tokens_details': {'cached_tokens': 11},
                'output_tokens': 4,
              },
            },
          });
          await request.response.close();
        }),
      );

      ProxyServerResponse? loggedResponse;
      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(address: '127.0.0.1', port: 0),
        onRequestCompleted: (endpoint, request, response) {
          loggedResponse = response;
        },
      );
      service!.endpoints = [buildResponsesEndpoint(upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final request = http.Request(
        'POST',
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
      )
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'model': 'test-model-x',
          'max_tokens': 1024,
          'stream': true,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        });

      final streamed =
          await client!.send(request).then(http.Response.fromStream);

      expect(streamed.statusCode, HttpStatus.ok);
      expect(
        streamed.headers['content-type'],
        contains('text/event-stream'),
      );

      final events = _parseSseEvents(streamed.body);
      expect(events.map((e) => e.$1), [
        'message_start',
        'ping',
        'content_block_start',
        'content_block_delta',
        'content_block_delta',
        'content_block_stop',
        'message_delta',
        'message_stop',
      ]);

      // message_start 回填客户端原始模型名
      expect(events[0].$2['message']['model'], 'test-model-x');
      expect(events[3].$2['delta'], {'type': 'text_delta', 'text': 'Hello'});
      expect(events[6].$2['usage']['output_tokens'], 4);
      expect(events[6].$2['usage']['input_tokens'], 33);
      expect(events[6].$2['usage']['cache_read_input_tokens'], 11);
      expect(events[6].$2['delta']['stop_reason'], 'end_turn');

      expect(capturedPath, '/v1/responses');

      // 审计记录：rawResponseBody 为上游 Responses SSE 原文，
      // responseBody 为转换后的 Anthropic SSE 文本
      expect(loggedResponse!.rawResponseBody, contains('response.created'));
      expect(loggedResponse!.rawResponseBody,
          contains('"input_tokens_details"'));
      expect(loggedResponse!.responseBody, contains('message_start'));
      expect(loggedResponse!.responseBody, contains('message_stop'));
    });

    test('流式思考：reasoning summary delta → thinking block', () async {
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/event-stream',
          );
          void event(Map<String, dynamic> data) => request.response.write(
                'event: ${data['type']}\ndata: ${jsonEncode(data)}\n\n',
              );

          event({'type': 'response.created', 'response': {}});
          event({
            'type': 'response.reasoning_summary_text.delta',
            'delta': 'thinking...',
          });
          event({'type': 'response.output_text.delta', 'delta': 'Answer'});
          event({
            'type': 'response.completed',
            'response': {'status': 'completed', 'usage': {}},
          });
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(address: '127.0.0.1', port: 0),
      );
      service!.endpoints = [buildResponsesEndpoint(upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final request = http.Request(
        'POST',
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
      )
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'model': 'm',
          'max_tokens': 1024,
          'stream': true,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        });

      final streamed =
          await client!.send(request).then(http.Response.fromStream);
      final events = _parseSseEvents(streamed.body);

      final thinkingStarts = events
          .where((e) =>
              e.$1 == 'content_block_start' &&
              e.$2['content_block']['type'] == 'thinking')
          .toList();
      expect(thinkingStarts, hasLength(1));
      expect(thinkingStarts.first.$2['index'], 0);

      final textStarts = events
          .where((e) =>
              e.$1 == 'content_block_start' &&
              e.$2['content_block']['type'] == 'text')
          .toList();
      // text block 开启在 thinking 之后
      expect(textStarts, hasLength(1));
      expect(textStarts.first.$2['index'], greaterThan(0));
    });

    test('上游错误体转换为 Anthropic 错误格式', () async {
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'error': {
              'message': 'Incorrect API key provided',
              'type': 'invalid_request_error',
              'code': 'invalid_api_key',
            },
          }));
          await request.response.close();
        }),
      );

      ProxyServerResponse? loggedResponse;
      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(address: '127.0.0.1', port: 0),
        onRequestCompleted: (endpoint, request, response) {
          loggedResponse = response;
        },
      );
      service!.endpoints = [buildResponsesEndpoint(upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final response = await client!.post(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'model': 'm',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
      );

      // 401 是客户端错误，原状态码返回给客户端判断认证问题
      expect(response.statusCode, HttpStatus.unauthorized);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['type'], 'error');
      expect(body['error']['type'], 'authentication_error');
      expect(body['error']['message'], 'Incorrect API key provided');

      // 审计记录：rawResponseBody 为上游错误 JSON 原文
      final rawError =
          jsonDecode(loggedResponse!.rawResponseBody!) as Map<String, dynamic>;
      expect(rawError['error']['code'], 'invalid_api_key');
    });

    test('baseUrl 以 /v1 结尾时路径重写为 /responses', () async {
      String? capturedPath;

      upstreamServers.add(
        await _startUpstreamServer((request) async {
          capturedPath = request.uri.path;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'id': 'resp_1',
            'model': 'gpt-5',
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': 'ok'},
                ],
              },
            ],
            'usage': {},
          }));
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        authToken: testProxyAuthToken,
        config: const ProxyServerConfig(address: '127.0.0.1', port: 0),
      );
      service!.endpoints = [
        EndpointEntity(
          id: 'ep-v1',
          name: 'V1 Suffix Endpoint',
          apiFormat: EndpointApiFormat.openaiResponses,
          anthropicBaseUrl:
              'http://127.0.0.1:${upstreamServers[0].port}/v1',
          anthropicAuthToken: 'token',
        ),
      ];
      await service!.start();

      client = AuthenticatedTestClient();
      await client!.post(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'model': 'm',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
      );

      // baseUrl 已含 /v1，重写后的完整路径应为 /v1/responses
      // （而非 /v1/v1/responses）
      expect(capturedPath, '/v1/responses');
    });
  });
}

Future<HttpServer> _startUpstreamServer(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

/// 解析 Anthropic 格式 SSE 文本为 (event, data) 记录列表
List<(String, Map<String, dynamic>)> _parseSseEvents(String text) {
  final events = <(String, Map<String, dynamic>)>[];
  for (final block in text.split('\n\n')) {
    if (block.trim().isEmpty) continue;
    String? event;
    Map<String, dynamic>? data;
    for (final line in block.split('\n')) {
      if (line.startsWith('event: ')) event = line.substring(7);
      if (line.startsWith('data: ')) {
        data = jsonDecode(line.substring(6)) as Map<String, dynamic>;
      }
    }
    if (event != null && data != null) events.add((event, data));
  }
  return events;
}
