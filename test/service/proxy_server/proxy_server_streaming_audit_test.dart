import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/model/request_log_entity.dart';
import 'package:code_proxy/repository/request_log_repository.dart';
import 'package:code_proxy/service/proxy_audit_service.dart';
import 'package:code_proxy/service/proxy_request_log_service.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_service.dart';
import 'package:code_proxy/service/request_log_factory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../support/authenticated_http_client.dart';

class _LogRepository extends Fake implements RequestLogRepository {
  final inserted = <RequestLogEntity>[];

  @override
  Future<void> insert(RequestLogEntity log) async => inserted.add(log);
}

const _sse =
    'event: message_start\n'
    'data: {"type":"message_start","message":{"usage":{"input_tokens":3}}}\n\n'
    'event: content_block_delta\n'
    'data: {"type":"content_block_delta","delta":{"text":"hello"}}\n\n'
    'event: message_stop\ndata: {"type":"message_stop"}\n\n';

void main() {
  late Directory root;
  late Directory auditRoot;
  late _LogRepository repository;
  late ProxyRequestLogService logService;
  late List<ProxyServerResponse> responses;
  final servers = <HttpServer>[];
  final rawServers = <ServerSocket>[];
  final clients = <http.Client>[];
  ProxyServerService? proxy;

  setUp(() {
    root = Directory.systemTemp.createTempSync('streaming_audit');
    auditRoot = Directory(p.join(root.path, 'audit'));
    repository = _LogRepository();
    responses = <ProxyServerResponse>[];
    logService = ProxyRequestLogService(
      repository: repository,
      audit: ProxyAuditService(auditDirectory: auditRoot.path),
      logFactory: RequestLogFactory.create(),
    );
  });

  tearDown(() async {
    await proxy?.stop();
    proxy = null;
    for (final client in clients) {
      client.close();
    }
    clients.clear();
    for (final server in servers) {
      await server.close(force: true);
    }
    servers.clear();
    for (final server in rawServers) {
      await server.close();
    }
    rawServers.clear();
    await logService.dispose();
    root.deleteSync(recursive: true);
  });

  Future<HttpServer> upstream(Future<void> Function(HttpRequest) respond) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(server);
    server.listen((request) async {
      unawaited(
        request.response.done.then<void>((_) {}, onError: (Object _) {}),
      );
      try {
        await request.drain<void>();
        await respond(request);
      } on HttpException {
        // 客户端中途断开时上游写入会失败
      } on SocketException {
        // 同上
      }
    });
    return server;
  }

  EndpointEntity endpoint(
    String id,
    int port, {
    EndpointApiFormat format = EndpointApiFormat.anthropic,
  }) => EndpointEntity(
    id: id,
    name: id,
    baseUrl: 'http://127.0.0.1:$port',
    authToken: 'upstream-secret',
    apiFormat: format,
  );

  Future<void> start(List<EndpointEntity> endpoints, {int timeout = 3000}) async {
    proxy = ProxyServerService(
      config: ProxyServerConfig(port: 0, apiTimeoutMs: timeout),
      authToken: testProxyAuthToken,
      onRequestCompleted: (endpoint, request, response) {
        responses.add(response);
        logService.record(endpoint, request, response);
      },
      createAuditBodyWriter: logService.startAuditBodyWriter,
    );
    proxy!.endpoints = endpoints;
    await proxy!.start();
  }

  http.Client client() {
    final created = AuthenticatedTestClient();
    clients.add(created);
    return created;
  }

  http.Request request({bool stream = true, String model = 'claude-test'}) =>
      http.Request('POST', Uri.parse('http://127.0.0.1:${proxy!.boundPort}/v1/messages'))
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'model': model,
          'max_tokens': 16,
          'stream': stream,
          'messages': [
            {'role': 'user', 'content': 'Hello'},
          ],
        });

  Future<List<Directory>> requestDirs() async {
    final dirs = <Directory>[];
    if (!await auditRoot.exists()) return dirs;
    await for (final dateDir in auditRoot.list()) {
      if (dateDir is! Directory) continue;
      await for (final requestDir in dateDir.list()) {
        if (requestDir is Directory) dirs.add(requestDir);
      }
    }
    return dirs;
  }

  /// 等到至少 [count] 个审计目录都写全了 [files]（目录先创建、正文后写入，
  /// 只等目录会读到半成品）。
  Future<List<Directory>> waitForAuditBodies(
    int count, {
    List<String> files = const ['response_body'],
  }) async {
    for (var attempt = 0; attempt < 200; attempt++) {
      final complete = <Directory>[];
      for (final dir in await requestDirs()) {
        var ready = true;
        for (final name in files) {
          if (!await File(p.join(dir.path, name)).exists()) {
            ready = false;
            break;
          }
        }
        if (ready) complete.add(dir);
      }
      if (complete.length >= count) return complete;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('审计正文未在预期时间内落盘（期望 $count 份）');
  }

  Future<List<String>> tempFiles() async {
    final tempDir = Directory(p.join(auditRoot.path, '.tmp'));
    if (!await tempDir.exists()) return const [];
    return tempDir
        .listSync()
        .map((entity) => p.basename(entity.path))
        .toList();
  }

  test('流式正文边收边写：审计文件与客户端正文一致，临时目录为空', () async {
    final upstreamServer = await upstream((request) async {
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.bufferOutput = false;
      request.response.write(_sse);
      await request.response.close();
    });
    await start([endpoint('a', upstreamServer.port)]);

    final stream = await client().send(request());
    final body = await stream.stream.bytesToString();
    expect(body, _sse);

    final dirs = await waitForAuditBodies(1);
    expect(
      await File(p.join(dirs.single.path, 'response_body')).readAsString(),
      _sse,
    );
    expect(await tempFiles(), isEmpty);
    // 流式路径不再把整段正文留在内存里，DTO 只带写入器
    expect(responses.single.responseBody, isNull);
    expect(responses.single.bodyWriter, isNotNull);
    expect(responses.single.bodyWriter!.head, contains('message_start'));
    expect(repository.inserted.single.statusCode, 200);
  });

  test('上游截断：审计文件保留半截正文与 error 事件', () async {
    final upstreamServer = await upstream((request) async {
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.bufferOutput = false;
      request.response.write(
        'event: content_block_delta\n'
        'data: {"type":"content_block_delta","delta":{"text":"partial"}}\n\n',
      );
      await request.response.flush();
      await request.response.close();
    });
    await start([endpoint('a', upstreamServer.port)]);

    final stream = await client().send(request());
    await stream.stream.bytesToString();

    final dirs = await waitForAuditBodies(1);
    final body = await File(
      p.join(dirs.single.path, 'response_body'),
    ).readAsString();
    expect(body, contains('partial'));
    expect(body, contains('event: error'));
    expect(await tempFiles(), isEmpty);
    expect(repository.inserted.single.statusCode, 502);
  });

  test('客户端中途断开：不落审计、不留临时文件', () async {
    // 上游发完首个 chunk 后保持沉默，靠 socket 关闭确认代理已检测到断连
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    rawServers.add(raw);
    final disconnected = Completer<void>();
    raw.listen((socket) {
      addTearDown(socket.destroy);
      var sent = false;
      socket.listen((_) {
        if (sent) return;
        sent = true;
        // 超过代理 HttpServer 的 8KB 输出缓冲，客户端才会立刻收到
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'Content-Type: text/event-stream\r\n'
          'Connection: close\r\n\r\n'
          ': ${'x' * 8192}\n\n',
        );
      }, onDone: disconnected.complete);
    });
    await start([endpoint('a', raw.port)]);

    final downstream = client();
    final stream = await downstream.send(request());
    final received = Completer<void>();
    final subscription = stream.stream.listen((_) {
      if (!received.isCompleted) received.complete();
    }, onError: (Object _) {});
    await received.future.timeout(const Duration(seconds: 2));
    downstream.close();
    await disconnected.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(responses, isEmpty);
    expect(await requestDirs(), isEmpty);
    expect(await tempFiles(), isEmpty);
  });

  test('OpenAI 流式转换：转换后正文与上游原文分别落盘', () async {
    const openAiSse =
        'data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1,'
        '"model":"gpt-test","choices":[{"index":0,"delta":{"role":"assistant",'
        '"content":"hi"},"finish_reason":null}]}\n\n'
        'data: {"id":"chatcmpl-1","object":"chat.completion.chunk","created":1,'
        '"model":"gpt-test","choices":[{"index":0,"delta":{},'
        '"finish_reason":"stop"}],"usage":{"prompt_tokens":3,'
        '"completion_tokens":2,"total_tokens":5}}\n\n'
        'data: [DONE]\n\n';
    final upstreamServer = await upstream((request) async {
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.bufferOutput = false;
      request.response.write(openAiSse);
      await request.response.close();
    });
    await start([
      endpoint('a', upstreamServer.port, format: EndpointApiFormat.openaiChat),
    ]);

    final stream = await client().send(request());
    final body = await stream.stream.bytesToString();
    expect(body, contains('event: message_start'));

    // raw_response_body 在 response_body 之后才 rename 落盘，等两个都齐再读
    final dirs = await waitForAuditBodies(
      1,
      files: ['response_body', 'raw_response_body'],
    );
    final responseBody = await File(
      p.join(dirs.single.path, 'response_body'),
    ).readAsString();
    expect(responseBody, contains('message_start'));
    expect(responseBody, contains('"text":"hi"'));
    expect(
      await File(p.join(dirs.single.path, 'raw_response_body')).readAsString(),
      openAiSse,
    );
    expect(await tempFiles(), isEmpty);
  });

  test('gzip 上游 + 模型伪装：审计落盘的是解压后正文', () async {
    final upstreamServer = await upstream((request) async {
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.headers.set('content-encoding', 'gzip');
      request.response.bufferOutput = false;
      request.response.add(gzip.encode(utf8.encode(_sse)));
      await request.response.close();
    });
    await start([endpoint('a', upstreamServer.port)]);

    final stream = await client().send(request());
    final body = await stream.stream.bytesToString();
    expect(body, contains('message_stop'));

    final dirs = await waitForAuditBodies(1);
    final responseBody = await File(
      p.join(dirs.single.path, 'response_body'),
    ).readAsString();
    expect(responseBody, contains('message_stop'));
    expect(await tempFiles(), isEmpty);
  });

  test('无法解压的压缩流（br）按原字节透传并落盘', () async {
    // 标注为 br 但实际是未压缩文本：代理不能解压，按原字节转发与落盘
    final upstreamServer = await upstream((request) async {
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.headers.set('content-encoding', 'br');
      request.response.bufferOutput = false;
      request.response.add(utf8.encode(_sse));
      await request.response.close();
    });
    await start([endpoint('a', upstreamServer.port)]);

    final stream = await client().send(request());
    final body = await stream.stream.bytesToString();
    expect(body, _sse);

    final dirs = await waitForAuditBodies(1);
    final responseBody = await File(
      p.join(dirs.single.path, 'response_body'),
    ).readAsString();
    expect(responseBody, _sse);
    expect(await tempFiles(), isEmpty);
  });

  test('重试：每次尝试各自落一个审计目录', () async {
    var hits = 0;
    final upstreamServer = await upstream((request) async {
      hits++;
      request.response.headers.contentType = ContentType('text', 'event-stream');
      if (hits == 1) {
        request.response.statusCode = 500;
        request.response.write('upstream failed');
        await request.response.close();
        return;
      }
      request.response.bufferOutput = false;
      request.response.write(_sse);
      await request.response.close();
    });
    await start([endpoint('a', upstreamServer.port)]);

    final stream = await client().send(request());
    expect(await stream.stream.bytesToString(), _sse);

    final dirs = await waitForAuditBodies(2);
    final bodies = <String>[];
    for (final dir in dirs) {
      bodies.add(await File(p.join(dir.path, 'response_body')).readAsString());
    }
    expect(bodies.where((body) => body == _sse), hasLength(1));
    expect(bodies.where((body) => body.contains('upstream failed')), hasLength(1));
    expect(await tempFiles(), isEmpty);
  });
}
