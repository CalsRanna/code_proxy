import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/default_model_config.dart';
import 'package:code_proxy/service/default_model_config_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request_body.dart';
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
        authToken: endpointToken,
        baseUrl: 'https://api.example.com',
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
      final prepared = handler.prepareRequest(
        shelfRequest,
        endpoint,
        ProxyServerRequestBody(body),
      );
      return prepared.request;
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
        authToken: 'sk-endpoint-token',
        baseUrl: 'https://api.example.com',
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
      final prepared = handler.prepareRequest(
        shelfRequest,
        endpoint,
        ProxyServerRequestBody(body),
      );
      return prepared.request;
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

  group('ProxyServerRequestHandler 超时切断底层请求', () {
    // 针对「等响应头」路径：此时还没有响应流可供取消，若不 abort，底层请求
    // 会一直挂着占用连接。响应体 idle timeout 那条路径不适合做这个断言 ——
    // 流订阅被取消时 HttpClient 本来就会关掉连接，加不加 abort 都观察不到
    // 差别（实测确认过），那里的 abort 属于明确清理而非修复。
    test('等响应头超时会 abort 请求，服务端能观察到连接关闭', () async {
      final serverSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(serverSocket.close);

      // 服务端收下请求后永不响应，连响应头都不发
      final clientClosed = Completer<void>();
      serverSocket.listen((socket) {
        socket.listen(
          (_) {},
          onDone: () {
            if (!clientClosed.isCompleted) clientClosed.complete();
          },
          onError: (_) {
            if (!clientClosed.isCompleted) clientClosed.complete();
          },
        );
      });

      final handler = ProxyServerRequestHandler(
        const ProxyServerConfig(apiTimeoutMs: 300),
      );
      addTearDown(handler.close);

      final request = http.Request(
        'POST',
        Uri.parse('http://127.0.0.1:${serverSocket.port}/v1/messages'),
      )..bodyBytes = utf8.encode('{"model":"claude-opus-5"}');

      await expectLater(
        handler.forwardRequest(request),
        throwsA(isA<TimeoutException>()),
      );

      // 关键断言：不 abort 时请求会继续挂着等响应，服务端观察不到 done，
      // 这里就会超时失败。
      await clientClosed.future.timeout(const Duration(seconds: 3));
    });
  });
  group('ProxyServerRequestHandler 请求体解析共享', () {
    final handler = ProxyServerRequestHandler(const ProxyServerConfig());

    tearDownAll(handler.close);

    setUp(() {
      DefaultModelConfigService.instance.replaceConfigForTesting(
        const DefaultModelConfig(
          haikuModel: 'claude-haiku-4-5-20251001',
          sonnetModel: 'claude-sonnet-4-5-20250929',
          opusModel: 'claude-opus-5',
        ),
      );
    });

    shelf.Request shelfRequest() =>
        shelf.Request('POST', Uri.parse('http://localhost:9000/v1/messages'));

    EndpointEntity endpointOf(String id, {String? opusModel}) => EndpointEntity(
      id: id,
      name: id,
      baseUrl: 'https://$id.example.com',
      opusModel: opusModel,
    );

    test('anthropic 端点模型未映射时，转发字节与输入逐字节一致', () {
      // 多余空格与非常规键序：一旦重新编码就会被规范化，字节必然不同。
      const raw =
          '{"max_tokens":256,   "model":"unknown-model",\n "messages":[]}';
      final prepared = handler.prepareRequest(
        shelfRequest(),
        endpointOf('passthrough'),
        ProxyServerRequestBody(utf8.encode(raw)),
      );
      expect(prepared.request.bodyBytes, utf8.encode(raw));
      expect(prepared.mappedModel, 'unknown-model');
    });

    test('模型映射命中时改写 model，共享解析结果保持原值', () {
      const raw = '{"model":"claude-opus-5","max_tokens":16}';
      final body = ProxyServerRequestBody(utf8.encode(raw));
      final prepared = handler.prepareRequest(
        shelfRequest(),
        endpointOf('mapped', opusModel: 'upstream-opus'),
        body,
      );
      expect(
        jsonDecode(utf8.decode(prepared.request.bodyBytes))['model'],
        'upstream-opus',
      );
      expect(prepared.mappedModel, 'upstream-opus');
      // 共享的解析结果与 originalModel 必须仍是客户端原始模型名，
      // 否则故障转移到下一个端点会读到上一个端点的映射结果。
      expect(body.originalModel, 'claude-opus-5');
      expect(body.json!['model'], 'claude-opus-5');
    });

    test('故障转移到另一个端点时，各自使用自己的映射模型', () {
      const raw = '{"model":"claude-opus-5","max_tokens":16}';
      final body = ProxyServerRequestBody(utf8.encode(raw));
      final first = handler.prepareRequest(
        shelfRequest(),
        endpointOf('first', opusModel: 'up-a'),
        body,
      );
      final second = handler.prepareRequest(
        shelfRequest(),
        endpointOf('second', opusModel: 'up-b'),
        body,
      );
      expect(
        jsonDecode(utf8.decode(first.request.bodyBytes))['model'],
        'up-a',
      );
      expect(
        jsonDecode(utf8.decode(second.request.bodyBytes))['model'],
        'up-b',
      );
      expect(body.originalModel, 'claude-opus-5');
    });

    test('同端点重试复用请求体缓存', () {
      const raw = '{"model":"claude-opus-5","max_tokens":16}';
      final body = ProxyServerRequestBody(utf8.encode(raw));
      final endpoint = endpointOf('cached', opusModel: 'up-c');
      final cache = ProxyServerBodyCache();
      final first = handler.prepareRequest(
        shelfRequest(),
        endpoint,
        body,
        bodyCache: cache,
      );
      final second = handler.prepareRequest(
        shelfRequest(),
        endpoint,
        body,
        bodyCache: cache,
      );
      expect(identical(first.request.bodyBytes, second.request.bodyBytes), isTrue);
    });
  });

}
