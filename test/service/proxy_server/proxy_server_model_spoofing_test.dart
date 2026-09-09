import 'dart:convert';
import 'dart:io';

import '../../support/authenticated_http_client.dart';
import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/default_model_config_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Anthropic 格式端点的响应模型伪装（端到端）。
///
/// 请求侧模型映射照常把 `claude-opus-5` 换成端点实际模型发往上游；
/// 响应侧把 `model` 回填为客户端请求的原始模型名（默认行为，不配置）。
/// 审计日志保留上游原始响应（rawResponseBody）与客户端收到的改写文本
/// （responseBody），两者可对照。
void main() {
  group('Anthropic 格式端点响应模型伪装（端到端）', () {
    ProxyServerService? service;
    final upstreamServers = <HttpServer>[];
    http.Client? client;

    setUp(() {
      // 请求模型须精确命中全局入口,才能映射到端点实际模型。
      DefaultModelConfigService.instance.replaceConfigForTesting(
        const DefaultModelConfig(
          haikuModel: 'claude-haiku-4-5-20251001',
          sonnetModel: 'claude-sonnet-4-5-20250929',
          opusModel: 'claude-opus-5',
          fableModel: 'claude-fable-5-1',
        ),
      );
    });

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

    EndpointEntity buildAnthropicEndpoint(int port) {
      return EndpointEntity(
        id: 'ep-anthropic',
        name: 'Anthropic Endpoint',
        apiFormat: EndpointApiFormat.anthropic,
        baseUrl: 'http://127.0.0.1:$port',
        authToken: 'upstream-token',
        // 端点实际模型：请求侧的 claude-opus-5 会被映射到这里
        opusModel: 'upstream-real-opus-model',
      );
    }

    test('非流式：响应 model 回填客户端原始模型名，请求映射不受影响', () async {
      Map<String, dynamic>? capturedBody;
      String? upstreamResponseBody;

      upstreamServers.add(
        await _startUpstreamServer((request) async {
          capturedBody =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;

          upstreamResponseBody = jsonEncode({
            'id': 'msg_123',
            'type': 'message',
            'role': 'assistant',
            'model': 'upstream-real-opus-model',
            'content': [
              {'type': 'text', 'text': 'Hello from upstream'},
            ],
            'stop_reason': 'end_turn',
            'stop_sequence': null,
            'usage': {'input_tokens': 42, 'output_tokens': 7},
          });
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType.json;
          request.response.write(upstreamResponseBody);
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
      service!.endpoints = [buildAnthropicEndpoint(upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final response = await client!.post(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
        headers: {
          'content-type': 'application/json',
          'x-api-key': 'client-token',
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-opus-5',
          'max_tokens': 1024,
          'stream': false,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
      );

      // 上游仍收到映射后的实际模型（请求侧不受影响）
      expect(capturedBody!['model'], 'upstream-real-opus-model');

      // 客户端收到伪装后的原始模型名
      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-opus-5');
      expect(body['content'], [
        {'type': 'text', 'text': 'Hello from upstream'},
      ]);
      expect(body['usage']['input_tokens'], 42);

      // 审计：记录客户端原始模型 + 客户端收到的改写文本（上游原文仍为真实模型）
      expect(loggedRequest!.originalModel, 'claude-opus-5');
      expect(upstreamResponseBody, contains('"upstream-real-opus-model"'));
      final auditBody =
          jsonDecode(loggedResponse!.responseBody!) as Map<String, dynamic>;
      expect(auditBody['model'], 'claude-opus-5');
      // token 统计不受伪装影响（responseBody 已改写但 usage 保留）
      expect(loggedResponse!.usage!['input'], 42);
      expect(loggedResponse!.usage!['output'], 7);
    });

    test('流式：message_start 的 model 被替换，其余事件原样透传', () async {
      Map<String, dynamic>? capturedBody;
      final upstreamStreamText = StringBuffer();

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
          void sse(String event, Map<String, dynamic> data) {
            final block = 'event: $event\ndata: ${jsonEncode(data)}\n\n';
            upstreamStreamText.write(block);
            request.response.write(block);
          }

          sse('message_start', {
            'type': 'message_start',
            'message': {
              'id': 'msg_1',
              'type': 'message',
              'role': 'assistant',
              'model': 'upstream-real-opus-model',
              'content': <Object>[],
              'usage': {'input_tokens': 42},
            },
          });
          sse('content_block_start', {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': ''},
          });
          sse('content_block_delta', {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Hi from SSE'},
          });
          sse('content_block_stop', {'type': 'content_block_stop', 'index': 0});
          sse('message_delta', {
            'type': 'message_delta',
            'delta': {'stop_reason': 'end_turn'},
            'usage': {'output_tokens': 7},
          });
          sse('message_stop', {'type': 'message_stop'});
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
      service!.endpoints = [buildAnthropicEndpoint(upstreamServers[0].port)];
      await service!.start();

      client = AuthenticatedTestClient();
      final response = await client!.post(
        Uri.parse('http://127.0.0.1:${service!.boundPort}/v1/messages'),
        headers: {
          'content-type': 'application/json',
          'x-api-key': 'client-token',
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-opus-5',
          'max_tokens': 1024,
          'stream': true,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
        }),
      );

      expect(capturedBody!['model'], 'upstream-real-opus-model');
      expect(response.statusCode, HttpStatus.ok);

      final events = _parseSseEvents(response.body);
      expect(events, hasLength(6));

      // message_start 的 model 被伪装为客户端原始模型名
      final messageStart = events.firstWhere((e) => e.$1 == 'message_start');
      final message = messageStart.$2['message'] as Map<String, dynamic>;
      expect(message['model'], 'claude-opus-5');
      expect(message['usage'], {'input_tokens': 42});

      // 其余事件内容未被改写
      final delta = events.firstWhere((e) => e.$1 == 'content_block_delta');
      expect(delta.$2['delta'], {'type': 'text_delta', 'text': 'Hi from SSE'});
      final stop = events.firstWhere((e) => e.$1 == 'message_stop');
      expect(stop.$2, {'type': 'message_stop'});

      // 审计：responseBody 是客户端收到的改写文本（上游原文仍为真实模型），
      // usage 统计不受影响
      expect(
        upstreamStreamText.toString(),
        contains('"model":"upstream-real-opus-model"'),
      );
      final auditBody = loggedResponse!.responseBody!;
      expect(auditBody, contains('"model":"claude-opus-5"'));
      expect(auditBody, contains('Hi from SSE'));
      expect(loggedResponse!.usage!['input'], 42);
      expect(loggedResponse!.usage!['output'], 7);
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
