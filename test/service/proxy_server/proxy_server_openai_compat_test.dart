import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('OpenAI 兼容端点格式转换（端到端）', () {
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

    EndpointEntity buildOpenAiEndpoint(int port, {String id = 'ep-openai'}) {
      return EndpointEntity(
        id: id,
        name: 'OpenAI Endpoint',
        apiFormat: EndpointApiFormat.openai,
        anthropicBaseUrl: 'http://127.0.0.1:$port',
        anthropicAuthToken: 'upstream-token',
      );
    }

    test('非流式：请求转换为 OpenAI 格式转发，响应转换回 Anthropic 格式', () async {
      String? capturedPath;
      String? capturedAuth;
      String? capturedApiKey;
      Map<String, dynamic>? capturedBody;

      upstreamServers.add(
        await _startUpstreamServer((request) async {
          capturedPath = request.uri.path;
          capturedAuth = request.headers.value('authorization');
          capturedApiKey = request.headers.value('x-api-key');
          capturedBody =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;

          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'id': 'chatcmpl-123',
            'object': 'chat.completion',
            'model': 'gpt-4o',
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': 'Hello from GPT'},
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 42,
              'completion_tokens': 7,
              'prompt_tokens_details': {'cached_tokens': 20},
            },
          }));
          await request.response.close();
        }),
      );

      ProxyServerRequest? loggedRequest;
      ProxyServerResponse? loggedResponse;
      service = ProxyServerService(
        config: const ProxyServerConfig(address: '127.0.0.1', port: 0),
        onRequestCompleted: (endpoint, request, response) {
          loggedRequest = request;
          loggedResponse = response;
        },
      );
      service!.endpoints = [buildOpenAiEndpoint(upstreamServers[0].port)];
      await service!.start();

      client = http.Client();
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

      // 上游收到的是 OpenAI 格式
      expect(capturedPath, '/v1/chat/completions');
      expect(capturedAuth, 'Bearer upstream-token');
      expect(capturedApiKey, isNull);
      expect(capturedBody!['model'], 'test-model-x');
      expect(capturedBody!['max_tokens'], 1024);
      expect((capturedBody!['messages'] as List)[0], {
        'role': 'system',
        'content': 'You are helpful.',
      });
      expect((capturedBody!['messages'] as List)[1], {
        'role': 'user',
        'content': 'hi',
      });

      // 审计记录：请求双向留痕（原文 Anthropic 格式 + 转发 OpenAI 格式）
      final clientRequestBody =
          jsonDecode(loggedRequest!.originalBody!) as Map<String, dynamic>;
      expect(clientRequestBody['model'], 'test-model-x');
      expect(clientRequestBody['system'], 'You are helpful.');
      expect(jsonDecode(loggedRequest!.body), capturedBody);

      // 审计记录：响应双向留痕（上游 chat.completion 原文 + 转换后 Anthropic）
      final rawResponseJson =
          jsonDecode(loggedResponse!.rawResponseBody!) as Map<String, dynamic>;
      expect(rawResponseJson['object'], 'chat.completion');

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

    test('流式：OpenAI chunk 流转换为完整 Anthropic SSE 事件序列', () async {
      Map<String, dynamic>? capturedBody;

      upstreamServers.add(
        await _startUpstreamServer((request) async {
          capturedBody =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;

          request.response.statusCode = HttpStatus.ok;
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/event-stream',
          );
          void chunk(Map<String, dynamic> data) =>
              request.response.write('data: ${jsonEncode(data)}\n\n');

          // role-only 首块（应被跳过）
          chunk({
            'id': 'chatcmpl-sse',
            'choices': [
              {
                'index': 0,
                'delta': {'role': 'assistant'},
                'finish_reason': null,
              },
            ],
          });
          // 文本增量
          chunk({
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'Let me check.'},
                'finish_reason': null,
              },
            ],
          });
          // 工具调用开始
          chunk({
            'choices': [
              {
                'index': 0,
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_abc',
                      'type': 'function',
                      'function': {'name': 'read_file', 'arguments': ''},
                    },
                  ],
                },
                'finish_reason': null,
              },
            ],
          });
          // 参数分片
          chunk({
            'choices': [
              {
                'index': 0,
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': '{"pa'},
                    },
                  ],
                },
              },
            ],
          });
          chunk({
            'choices': [
              {
                'index': 0,
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': 'th":"/a"}'},
                    },
                  ],
                },
              },
            ],
          });
          // 结束原因 + usage
          chunk({
            'choices': [
              {
                'index': 0,
                'delta': {},
                'finish_reason': 'tool_calls',
              },
            ],
          });
          chunk({
            'choices': [],
            'usage': {'prompt_tokens': 11, 'completion_tokens': 22},
          });
          request.response.write('data: [DONE]\n\n');
          await request.response.close();
        }),
      );

      ProxyServerResponse? loggedResponse;
      service = ProxyServerService(
        config: const ProxyServerConfig(address: '127.0.0.1', port: 0),
        onRequestCompleted: (endpoint, request, response) {
          loggedResponse = response;
        },
      );
      service!.endpoints = [buildOpenAiEndpoint(upstreamServers[0].port)];
      await service!.start();

      // 上游应收到转换后的 OpenAI 流式请求
      expect(capturedBody, isNull);

      client = http.Client();
      final streamedRequest = http.Request(
        'POST',
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
      )
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'model': 'test-model-x',
          'max_tokens': 512,
          'stream': true,
          'messages': [
            {'role': 'user', 'content': 'list files'},
          ],
        });

      final streamedResponse = await client!.send(streamedRequest);
      expect(streamedResponse.statusCode, HttpStatus.ok);

      final events = _parseSseEvents(
        await streamedResponse.stream.bytesToString(),
      );

      // 上游应收到转换后的 OpenAI 流式请求（include_usage 已注入）
      expect(capturedBody!['stream'], true);
      expect(capturedBody!['stream_options']['include_usage'], true);

      final types = events.map((e) => e.$1).toList();
      expect(types, [
        'message_start',
        'ping',
        'content_block_start',
        'content_block_delta',
        'content_block_stop',
        'content_block_start',
        'content_block_delta',
        'content_block_delta',
        'content_block_stop',
        'message_delta',
        'message_stop',
      ]);

      // message_start 携带客户端原始模型名
      expect(events[0].$2['message']['model'], 'test-model-x');

      // text block: index 0，惰性开启后立即有文本
      expect(events[2].$2['index'], 0);
      expect(events[3].$2['delta']['text'], 'Let me check.');

      // tool_use block: index 1，参数分片直转 partial_json
      expect(events[4].$2['index'], 0); // text block 关闭
      expect(events[5].$2['index'], 1);
      expect(events[5].$2['content_block'], {
        'type': 'tool_use',
        'id': 'call_abc',
        'name': 'read_file',
        'input': <String, dynamic>{},
      });
      expect(events[6].$2['delta']['partial_json'], '{"pa');
      expect(events[7].$2['delta']['partial_json'], 'th":"/a"}');
      expect(events[8].$2['index'], 1);

      // message_delta 携带 stop_reason 与 usage
      expect(events[9].$2['delta'], {
        'stop_reason': 'tool_use',
        'stop_sequence': null,
      });
      expect(events[9].$2['usage']['output_tokens'], 22);
      expect(events[9].$2['usage']['input_tokens'], 11);

      // 审计记录：rawResponseBody 为上游 chunk 流原文（含 [DONE]），
      // responseBody 为转换后的 Anthropic SSE 文本
      expect(loggedResponse!.rawResponseBody, contains('chatcmpl-sse'));
      expect(loggedResponse!.rawResponseBody, contains('[DONE]'));
      expect(loggedResponse!.responseBody, contains('message_start'));
      expect(loggedResponse!.responseBody, contains('partial_json'));
    });

    test('错误响应：OpenAI 错误体转换为 Anthropic error 格式', () async {
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'error': {
              'message': 'Incorrect API key provided.',
              'type': 'invalid_request_error',
              'code': 'invalid_api_key',
            },
          }));
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        config: const ProxyServerConfig(address: '127.0.0.1', port: 0),
      );
      service!.endpoints = [buildOpenAiEndpoint(upstreamServers[0].port)];
      await service!.start();

      client = http.Client();
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

      expect(response.statusCode, HttpStatus.unauthorized);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['type'], 'error');
      expect(body['error']['type'], 'authentication_error');
      expect(body['error']['message'], 'Incorrect API key provided.');
    });

    test('故障转移语义不变：openai 端点 500 后切换到 anthropic 端点成功', () async {
      var openAiHits = 0;
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          openAiHits++;
          await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(jsonEncode({
            'error': {'message': 'upstream exploded', 'type': 'server_error'},
          }));
          await request.response.close();
        }),
      );
      var anthropicHits = 0;
      upstreamServers.add(
        await _startUpstreamServer((request) async {
          anthropicHits++;
          await utf8.decoder.bind(request).join();
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'id': 'msg_anthropic',
            'type': 'message',
            'role': 'assistant',
            'model': 'claude-x',
            'content': [
              {'type': 'text', 'text': 'from anthropic'},
            ],
            'stop_reason': 'end_turn',
            'usage': {'input_tokens': 1, 'output_tokens': 1},
          }));
          await request.response.close();
        }),
      );

      service = ProxyServerService(
        config: const ProxyServerConfig(
          address: '127.0.0.1',
          port: 0,
          circuitBreakerFailureThreshold: 1,
        ),
      );
      service!.endpoints = [
        buildOpenAiEndpoint(upstreamServers[0].port),
        EndpointEntity(
          id: 'ep-anthropic',
          name: 'Anthropic Endpoint',
          anthropicBaseUrl: 'http://127.0.0.1:${upstreamServers[1].port}',
        ),
      ];
      await service!.start();

      client = http.Client();

      // 单次请求内完成故障转移：openai 端点 500 → 断路器打开 →
      // 同一请求切换到 anthropic 端点透传成功
      final okResponse = await client!.post(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'model': 'm',
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
      );
      expect(okResponse.statusCode, HttpStatus.ok);
      expect(openAiHits, 1);
      expect(anthropicHits, 1);

      // anthropic 端点的响应原样透传（未被格式转换改动）
      final okBody = jsonDecode(okResponse.body) as Map<String, dynamic>;
      expect(okBody['id'], 'msg_anthropic');
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
