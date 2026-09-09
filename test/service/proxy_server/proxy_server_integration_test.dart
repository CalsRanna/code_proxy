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
  final servers = <HttpServer>[];
  final rawServers = <ServerSocket>[];
  final clients = <http.Client>[];
  ProxyServerService? proxy;
  final logs = <ProxyServerResponse>[];
  var unavailable = 0;
  var restored = 0;

  Future<HttpServer> upstream(
    Future<void> Function(HttpRequest) respond,
  ) async {
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
        // Some tests deliberately cancel a response while the peer is writing.
      } on SocketException {
        // Expected when switching modes closes the proxy's upstream socket.
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

  Future<void> start(
    List<EndpointEntity> endpoints, {
    int timeout = 3000,
    int threshold = 5,
  }) async {
    proxy = ProxyServerService(
      config: ProxyServerConfig(
        port: 0,
        apiTimeoutMs: timeout,
        circuitBreakerFailureThreshold: threshold,
      ),
      authToken: testProxyAuthToken,
      onEndpointUnavailable: (_) => unavailable++,
      onEndpointRestored: (_) => restored++,
      onRequestCompleted: (_, _, response) => logs.add(response),
    );
    proxy!.endpoints = endpoints;
    await proxy!.start();
  }

  http.Client client() {
    final client = AuthenticatedTestClient();
    clients.add(client);
    return client;
  }

  Uri url([String path = '/v1/messages']) =>
      Uri.parse('http://127.0.0.1:${proxy!.boundPort}$path');

  http.Request request({bool stream = false}) => http.Request('POST', url())
    ..headers['content-type'] = 'application/json'
    ..body = jsonEncode({
      'model': 'claude-test',
      'max_tokens': 16,
      'stream': stream,
      'messages': [
        {'role': 'user', 'content': 'Hello'},
      ],
    });

  Future<http.Response> send() async =>
      http.Response.fromStream(await client().send(request()));

  setUp(() {
    logs.clear();
    unavailable = 0;
    restored = 0;
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
  });

  for (final status in [500, 502, 503]) {
    test(
      'retries upstream $status before reaching the circuit breaker threshold',
      () async {
        var hits = 0;
        var backupHits = 0;
        final a = await upstream((request) async {
          request.response.statusCode = ++hits == 1 ? status : 200;
          request.response.write(
            hits == 1 ? '{"error":"temporary"}' : '{"ok":true}',
          );
          await request.response.close();
        });
        final b = await upstream((request) async {
          backupHits++;
          await request.response.close();
        });
        await start([endpoint('a', a.port), endpoint('b', b.port)]);
        final response = await send();
        expect(response.statusCode, 200);
        expect(hits, 2);
        expect(backupHits, 0);
        expect(logs.map((log) => log.statusCode), [status, 200]);
        expect(proxy!.getOpenCircuitBreakerEndpointIds(['a', 'b']), isEmpty);
        expect(unavailable, 0);
        expect(restored, 0);
      },
    );
  }

  test('client disconnect cancels the pending upstream header wait', () async {
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    rawServers.add(raw);
    final received = Completer<void>();
    final disconnected = Completer<void>();
    raw.listen((socket) {
      addTearDown(socket.destroy);
      socket.listen((_) {
        if (!received.isCompleted) received.complete();
      }, onDone: disconnected.complete);
    });
    await start([endpoint('a', raw.port)], timeout: 10000);
    final downstream = client();
    final pending = downstream.send(request());
    final cancelled = expectLater(
      pending,
      throwsA(isA<http.ClientException>()),
    );
    await received.future.timeout(const Duration(seconds: 2));
    downstream.close();
    await cancelled;
    await disconnected.future.timeout(const Duration(seconds: 2));
    expect(logs, isEmpty);
    expect(unavailable, 0);
  });

  test(
    'client disconnect stops retry backoff without cancelling a new request',
    () async {
      var hits = 0;
      final failed = Completer<void>();
      final a = await upstream((request) async {
        hits++;
        if (hits == 1) {
          request.response.statusCode = 500;
          request.response.headers.set('retry-after', '1');
          await request.response.close();
          failed.complete();
        } else {
          request.response.write('{"ok":true}');
          await request.response.close();
        }
      });
      await start([endpoint('a', a.port)], timeout: 10000);
      final downstream = client();
      final pending = downstream.send(request());
      final cancelled = expectLater(
        pending,
        throwsA(isA<http.ClientException>()),
      );
      await failed.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      downstream.close();
      await cancelled;
      expect((await send()).statusCode, 200);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(hits, 2);
      expect(logs.map((log) => log.statusCode), [500, 200]);
      expect(unavailable, 0);
    },
  );

  test('client disconnect closes a silent upstream SSE connection', () async {
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    rawServers.add(raw);
    final disconnected = Completer<void>();
    raw.listen((socket) {
      addTearDown(socket.destroy);
      var sent = false;
      socket.listen((_) {
        if (sent) return;
        sent = true;
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'Content-Type: text/event-stream\r\n'
          'Connection: close\r\n\r\n'
          ': ${'x' * 8192}\n\n',
        );
      }, onDone: disconnected.complete);
    });
    await start([endpoint('a', raw.port)], timeout: 10000);
    final downstream = client();
    final response = await downstream.send(request(stream: true));
    final received = Completer<void>();
    final subscription = response.stream.listen((_) {
      if (!received.isCompleted) received.complete();
    }, onError: (Object _) {});
    await received.future.timeout(const Duration(seconds: 2));
    downstream.close();
    await disconnected.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();
    expect(logs, isEmpty);
    expect(unavailable, 0);
  });

  test(
    'stopping releases the listening port and the service can restart',
    () async {
      final a = await upstream((request) async {
        request.response.write('{"ok":true}');
        await request.response.close();
      });
      await start([endpoint('a', a.port)]);
      expect((await send()).statusCode, 200);
      final port = proxy!.boundPort!;
      await proxy!.stop();
      final rebound = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await rebound.close();
      await proxy!.start();
      expect((await send()).statusCode, 200);
    },
  );

  test('active SSE continues beyond the API idle timeout', () async {
    final a = await upstream((request) async {
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.bufferOutput = false;
      request.response.write(': ${'x' * 8192}\n\n');
      await request.response.flush();
      for (var i = 0; i < 7; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        request.response.write(': heartbeat\n\n');
        await request.response.flush();
      }
      request.response.write(
        'event: message_stop\ndata: {"type":"message_stop"}\n\n',
      );
      await request.response.close();
    });
    await start([endpoint('a', a.port)], timeout: 200);
    final watch = Stopwatch()..start();
    final stream = await client().send(request(stream: true));
    final body = await stream.stream.bytesToString();
    expect(stream.statusCode, 200);
    expect(body, contains('message_stop'));
    expect(body, isNot(contains('event: error')));
    expect(watch.elapsedMilliseconds, greaterThan(400));
    expect(logs.map((log) => log.statusCode), [200]);
  });

  test(
    'truncated SSE records a failure without resending partial output',
    () async {
      var hits = 0;
      final a = await upstream((request) async {
        hits++;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,'
          '"delta":{"type":"text_delta","text":"partial"}}\n\n',
        );
        await request.response.close();
      });
      await start([endpoint('a', a.port)]);
      final stream = await client().send(request(stream: true));
      final body = await stream.stream.bytesToString();
      expect(stream.statusCode, 200);
      expect(body, contains('partial'));
      expect(body, contains('event: error'));
      expect(hits, 1);
      expect(logs.map((log) => log.statusCode), [502]);
    },
  );

  test('health checks honor existing breakers', () async {
    final a = await upstream((request) async {
      request.response.statusCode = 500;
      await request.response.close();
    });
    await start([endpoint('a', a.port)], threshold: 1);
    expect((await send()).statusCode, 500);
    expect((await client().head(url())).statusCode, 503);
  });

  test('no endpoint returns 500 while local responses still work', () async {
    await start([]);
    expect((await send()).statusCode, 500);
    expect((await client().head(url())).statusCode, 503);
    expect(
      (await client().post(
        url('/v1/messages/count_tokens'),
        body: '{}',
      )).statusCode,
      200,
    );
  });

  test(
    'header failures retry beyond the normal transient retry budget',
    () async {
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      rawServers.add(raw);
      var hits = 0;
      raw.listen((socket) {
        var handled = false;
        socket.listen((_) async {
          if (handled) return;
          handled = true;
          if (++hits <= 3) {
            socket.destroy();
          } else {
            socket.write(
              'HTTP/1.1 200 OK\r\nContent-Length: 2\r\n'
              'Connection: close\r\n\r\n{}',
            );
            await socket.flush();
            await socket.close();
          }
        }, onDone: socket.destroy);
      });
      await start([endpoint('a', raw.port)], timeout: 10000);
      expect((await send()).statusCode, 200);
      expect(hits, 4);
      expect(unavailable, 0);
      expect(logs.map((log) => log.statusCode), [502, 200]);
    },
  );

  for (final format in [
    EndpointApiFormat.openaiChat,
    EndpointApiFormat.openaiResponses,
  ]) {
    test('retries and converts ${format.name} responses', () async {
      var hits = 0;
      final a = await upstream((request) async {
        if (++hits == 1) {
          request.response.statusCode = 503;
          request.response.write('{"error":{"message":"temporary"}}');
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              format == EndpointApiFormat.openaiChat
                  ? {
                      'id': 'chatcmpl-test',
                      'object': 'chat.completion',
                      'model': 'gpt-test',
                      'choices': [
                        {
                          'index': 0,
                          'message': {'role': 'assistant', 'content': 'Hello'},
                          'finish_reason': 'stop',
                        },
                      ],
                      'usage': {'prompt_tokens': 2, 'completion_tokens': 1},
                    }
                  : {
                      'id': 'resp-test',
                      'object': 'response',
                      'status': 'completed',
                      'model': 'gpt-test',
                      'output': [
                        {
                          'type': 'message',
                          'role': 'assistant',
                          'content': [
                            {'type': 'output_text', 'text': 'Hello'},
                          ],
                        },
                      ],
                      'usage': {'input_tokens': 2, 'output_tokens': 1},
                    },
            ),
          );
        }
        await request.response.close();
      });
      await start([endpoint('a', a.port, format: format)]);
      final response = await send();
      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['type'], 'message');
      expect(body['model'], 'claude-test');
      expect(body['content'][0]['text'], 'Hello');
      expect(hits, 2);
    });
  }
  for (final status in [400, 401, 403, 404, 408, 429]) {
    test('default returns $status without retrying or failing over', () async {
      var hits = 0;
      var backupHits = 0;
      final a = await upstream((request) async {
        hits++;
        request.response.statusCode = status;
        request.response.write('upstream error');
        await request.response.close();
      });
      final b = await upstream((request) async {
        backupHits++;
        await request.response.close();
      });
      await start([endpoint('a', a.port), endpoint('b', b.port)], threshold: 1);
      final response = await send();
      expect(response.statusCode, status);
      expect(response.body, 'upstream error');
      expect(hits, 1);
      expect(backupHits, 0);
      expect(unavailable, 0);
      expect(logs.map((log) => log.statusCode), [status]);
    });
  }

  for (final status in [500, 503]) {
    test(
      '$status reaches the shared failure threshold and fails over',
      () async {
        var hits = 0;
        var backupHits = 0;
        final a = await upstream((request) async {
          hits++;
          request.response.statusCode = status;
          await request.response.close();
        });
        final b = await upstream((request) async {
          backupHits++;
          request.response.write('backup response');
          await request.response.close();
        });
        await start([
          endpoint('a', a.port),
          endpoint('b', b.port),
        ], threshold: 2);
        expect((await send()).body, 'backup response');
        expect(hits, 2);
        expect(backupHits, 1);
        expect(unavailable, 1);
        expect(proxy!.getOpenCircuitBreakerEndpointIds(['a', 'b']), {'a'});
        expect(logs.map((log) => log.statusCode), [status, status, 200]);
      },
    );
  }

  test(
    'all endpoints failing eventually returns the final upstream error',
    () async {
      final a = await upstream((request) async {
        request.response.statusCode = 500;
        await request.response.close();
      });
      final b = await upstream((request) async {
        request.response.statusCode = 503;
        request.response.write('last upstream error');
        await request.response.close();
      });
      await start([endpoint('a', a.port), endpoint('b', b.port)], threshold: 1);
      final response = await send();
      expect(response.statusCode, 503);
      expect(response.body, 'last upstream error');
      expect(unavailable, 2);
      expect(logs.map((log) => log.statusCode), [500, 503]);
    },
  );

  test(
    'Retry-After waits on the same endpoint beyond the per-attempt timeout',
    () async {
      var hits = 0;
      final a = await upstream((request) async {
        if (++hits == 1) {
          request.response.statusCode = 500;
          request.response.headers.set('retry-after', '1');
        } else {
          request.response.write('ok');
        }
        await request.response.close();
      });
      await start([endpoint('a', a.port)], timeout: 500);
      final watch = Stopwatch()..start();
      expect((await send()).body, 'ok');
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(950));
      expect(hits, 2);
      expect(logs.map((log) => log.statusCode), [500, 200]);
    },
  );

  test(
    'Retry-After from a failed endpoint does not delay the backup',
    () async {
      final a = await upstream((request) async {
        request.response.statusCode = 500;
        request.response.headers.set('retry-after', '60');
        await request.response.close();
      });
      final b = await upstream((request) async {
        request.response.write('backup');
        await request.response.close();
      });
      await start([endpoint('a', a.port), endpoint('b', b.port)], threshold: 1);
      expect((await send().timeout(const Duration(seconds: 2))).body, 'backup');
    },
  );

  test(
    'client disconnect suppresses retries after a late TLS handshake failure',
    () async {
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      rawServers.add(raw);
      final received = Completer<Socket>();
      var connections = 0;
      raw.listen((socket) {
        connections++;
        addTearDown(socket.destroy);
        socket.listen((_) {
          if (!received.isCompleted) received.complete(socket);
        });
      });
      await start([
        endpoint(
          'a',
          raw.port,
        ).copyWith(baseUrl: 'https://127.0.0.1:${raw.port}'),
      ], timeout: 10000);
      final downstream = client();
      final cancelled = expectLater(
        downstream.send(request()),
        throwsA(isA<http.ClientException>()),
      );
      final socket = await received.future.timeout(const Duration(seconds: 2));
      downstream.close();
      await cancelled;
      // SecureSocket.startConnect.cancel() only cancels the TCP establishment
      // in this Dart SDK. End the handshake later to exercise late-I/O cleanup.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      socket.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(connections, 1);
      expect(logs, isEmpty);
      expect(unavailable, 0);
    },
  );

  test('cancelling one request preserves an in-flight peer', () async {
    final firstReceived = Completer<void>();
    final secondReceived = Completer<void>();
    final finishSecond = Completer<void>();
    var hits = 0;
    final a = await upstream((request) async {
      if (++hits == 1) {
        firstReceived.complete();
        return;
      }
      secondReceived.complete();
      await finishSecond.future;
      request.response.write('peer survived');
      await request.response.close();
    });
    await start([endpoint('a', a.port)]);
    final firstClient = client();
    final cancelled = expectLater(
      firstClient.send(request()),
      throwsA(isA<http.ClientException>()),
    );
    await firstReceived.future;
    final second = send();
    await secondReceived.future;
    firstClient.close();
    await cancelled;
    finishSecond.complete();
    expect((await second).body, 'peer survived');
    expect(logs.map((log) => log.statusCode), [200]);
    expect(unavailable, 0);
  });
}
