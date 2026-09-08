import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:code_proxy/model/endpoint_entity.dart';
import 'package:code_proxy/service/proxy_server/brute_force/proxy_server_brute_force_executor.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_config.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_retry_delay.dart';
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
    anthropicBaseUrl: 'http://127.0.0.1:$port',
    anthropicAuthToken: 'upstream-secret',
    apiFormat: format,
  );

  Future<void> start(
    List<EndpointEntity> endpoints, {
    bool enabled = true,
    int timeout = 3000,
    int threshold = 1,
  }) async {
    proxy = ProxyServerService(
      config: ProxyServerConfig(
        port: 0,
        apiTimeoutMs: timeout,
        circuitBreakerFailureThreshold: threshold,
        bruteForceModeEnabled: enabled,
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

  for (final status in [400, 401, 403, 404, 408, 429, 500, 503]) {
    test(
      'retries upstream $status on the pinned endpoint without breaking',
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

  test('shares one deadline across retries and Retry-After waits', () async {
    var hits = 0;
    final a = await upstream((request) async {
      hits++;
      request.response.statusCode = 429;
      request.response.headers.set('retry-after', '120');
      await request.response.close();
    });
    await start([endpoint('a', a.port)], timeout: 250);
    final watch = Stopwatch()..start();
    final response = await send();
    expect(response.statusCode, 504);
    expect(response.body, contains('after 1 attempts'));
    expect(hits, 1);
    expect(watch.elapsedMilliseconds, inInclusiveRange(200, 1200));
    expect(logs.map((log) => log.statusCode), [429]);
  });

  test('deadline closes a socket which never sends response headers', () async {
    final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    rawServers.add(raw);
    final disconnected = Completer<void>();
    raw.listen((socket) {
      socket.listen(
        (_) {},
        onDone: () {
          socket.destroy();
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
    });
    await start([endpoint('a', raw.port)], timeout: 150);
    expect((await send()).statusCode, 504);
    await disconnected.future.timeout(const Duration(seconds: 2));
    expect(logs.map((log) => log.statusCode), [504]);
  });

  for (final status in [200, 500]) {
    test(
      'total budget bounds a continuously arriving $status non-stream body',
      () async {
        final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        rawServers.add(raw);
        final disconnected = Completer<void>();
        raw.listen((socket) {
          Timer? timer;
          var started = false;
          socket.listen(
            (_) {
              if (started) return;
              started = true;
              socket.write(
                'HTTP/1.1 $status Test\r\n'
                'Content-Type: text/plain\r\n'
                'Transfer-Encoding: chunked\r\n\r\n',
              );
              socket.write('1\r\nx\r\n');
              timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
                socket.write('1\r\nx\r\n');
              });
            },
            onDone: () {
              timer?.cancel();
              socket.destroy();
              if (!disconnected.isCompleted) disconnected.complete();
            },
          );
        });
        await start([endpoint('a', raw.port)], timeout: 180);
        final watch = Stopwatch()..start();
        expect((await send()).statusCode, 504);
        expect(watch.elapsedMilliseconds, lessThan(1000));
        await disconnected.future.timeout(const Duration(seconds: 2));
        expect(logs, hasLength(1));
      },
    );
  }

  test('successful SSE continues past the retry deadline', () async {
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
    'switch interrupts normal header wait while retaining port and auth',
    () async {
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      rawServers.add(raw);
      final connected = Completer<void>();
      final disconnected = Completer<void>();
      raw.listen((socket) {
        socket.listen(
          (_) {
            if (!connected.isCompleted) connected.complete();
          },
          onDone: () {
            socket.destroy();
            if (!disconnected.isCompleted) disconnected.complete();
          },
        );
      });
      await start([endpoint('a', raw.port)], enabled: false);
      final port = proxy!.boundPort;
      final oldRequest = send();
      await connected.future;
      proxy!.setBruteForceModeEnabled(true);
      expect((await oldRequest).statusCode, 503);
      await disconnected.future.timeout(const Duration(seconds: 2));
      expect(proxy!.boundPort, port);
      expect((await client().head(url())).statusCode, 200);
      expect(logs, isEmpty);
      expect(unavailable, 0);

      final a = await upstream((request) async {
        request.response.write('new mode');
        await request.response.close();
      });
      proxy!.endpoints = [endpoint('b', a.port)];
      expect((await send()).body, 'new mode');
      final unauthenticated = http.Client();
      clients.add(unauthenticated);
      expect((await unauthenticated.post(url())).statusCode, 401);
    },
  );

  test(
    'disabling cancels retry waits and restores normal 4xx handling',
    () async {
      var hits = 0;
      final failed = Completer<void>();
      final a = await upstream((request) async {
        hits++;
        request.response.statusCode = 401;
        request.response.headers.set('retry-after', '1');
        await request.response.close();
        if (!failed.isCompleted) failed.complete();
      });
      await start([endpoint('a', a.port)]);
      final port = proxy!.boundPort;
      final oldRequest = send();
      await failed.future;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      proxy!.setBruteForceModeEnabled(false);
      expect((await oldRequest).statusCode, 503);
      expect((await send()).statusCode, 401);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(hits, 2);
      expect(proxy!.boundPort, port);
      expect(unavailable, 0);
    },
  );

  for (final enabled in [false, true]) {
    test(
      'switch cancels active SSE from ${enabled ? 'brute force' : 'normal'} mode',
      () async {
        var hits = 0;
        final a = await upstream((request) async {
          hits++;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.bufferOutput = false;
          request.response.write(': ${'x' * 8192}\n\n');
          await request.response.flush();
          // Keep the response open until the mode switch cancels its socket.
        });
        await start([endpoint('a', a.port)], enabled: enabled);
        final stream = await client().send(request(stream: true));
        final gotChunk = Completer<void>();
        final done = Completer<void>();
        stream.stream.listen((_) {
          if (!gotChunk.isCompleted) gotChunk.complete();
        }, onDone: done.complete);
        await gotChunk.future;
        proxy!.setBruteForceModeEnabled(!enabled);
        await done.future.timeout(const Duration(seconds: 2));
        expect(hits, 1);
        expect(unavailable, 0);
        expect(logs, isEmpty);
        expect(proxy!.getOpenCircuitBreakerEndpointIds(['a']), isEmpty);
      },
    );
  }

  test(
    'health checks ignore existing breakers only while brute force is on',
    () async {
      final a = await upstream((request) async {
        request.response.statusCode = 500;
        await request.response.close();
      });
      await start([endpoint('a', a.port)], enabled: false);
      expect((await send()).statusCode, 500);
      expect((await client().head(url())).statusCode, 503);
      proxy!.setBruteForceModeEnabled(true);
      expect((await client().head(url())).statusCode, 200);
      proxy!.setBruteForceModeEnabled(false);
      expect((await client().head(url())).statusCode, 503);
    },
  );

  test('no endpoint returns 503 while local responses still work', () async {
    await start([]);
    expect((await send()).statusCode, 503);
    expect((await client().head(url())).statusCode, 503);
    expect(
      (await client().post(
        url('/v1/messages/count_tokens'),
        body: '{}',
      )).statusCode,
      200,
    );
  });

  test('brute force and normal mode use the same full jitter calculation', () {
    final normalRandom = Random(42);
    final bruteForceRandom = Random(42);
    for (final attempt in [1, 2, 3, 4, 5, 6, 7, 8, 1000000]) {
      expect(
        ProxyServerBruteForceExecutor.retryDelay(
          attempt,
          random: bruteForceRandom,
        ).inMilliseconds,
        calculateProxyRetryDelayMs(attempt + 1, random: normalRandom),
      );
    }
  });

  test('Retry-After uses the longer of server delay and sampled jitter', () {
    final now = DateTime.utc(2026, 9, 8);
    final jitter = ProxyServerBruteForceExecutor.retryDelay(
      4,
      random: Random(42),
    );
    for (final retryAfter in ['0', 'bad', '-1']) {
      expect(
        ProxyServerBruteForceExecutor.retryDelay(
          4,
          retryAfter: retryAfter,
          random: Random(42),
        ),
        jitter,
      );
    }
    expect(
      ProxyServerBruteForceExecutor.retryDelay(2, retryAfter: '3'),
      const Duration(seconds: 3),
    );
    expect(
      ProxyServerBruteForceExecutor.retryDelay(
        2,
        retryAfter: HttpDate.format(now.add(const Duration(seconds: 5))),
        now: now,
      ),
      const Duration(seconds: 5),
    );
    expect(
      ProxyServerBruteForceExecutor.retryDelay(8, retryAfter: '60'),
      const Duration(seconds: 60),
    );
    expect(
      ProxyServerBruteForceExecutor.retryDelay(
        4,
        retryAfter: '3',
        random: Random(42),
      ),
      jitter > const Duration(seconds: 3) ? jitter : const Duration(seconds: 3),
    );
  });

  test('HTTP jitter retries remain bounded by the total deadline', () async {
    var hits = 0;
    final a = await upstream((request) async {
      hits++;
      request.response.statusCode = 500;
      await request.response.close();
    });
    await start([endpoint('a', a.port)], timeout: 2500);
    final watch = Stopwatch()..start();
    final response = await send();
    expect(response.statusCode, 504);
    expect(hits, greaterThanOrEqualTo(2));
    expect(watch.elapsedMilliseconds, inInclusiveRange(2400, 3500));
    final hitsAtDeadline = hits;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(hits, hitsAtDeadline);
    expect(unavailable, 0);
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
      expect(logs, hasLength(4));
    },
  );

  test('switch cancels normal retries without resurrecting old work', () async {
    var hits = 0;
    final first = Completer<void>();
    final a = await upstream((request) async {
      hits++;
      // A zero jitter delay may already start the second attempt. Keep it
      // pending so switching exercises cancellation in either state.
      if (hits > 1) return;
      request.response.statusCode = 500;
      await request.response.close();
      if (!first.isCompleted) first.complete();
    });
    await start([endpoint('a', a.port)], enabled: false, threshold: 5);
    final old = send();
    await first.future;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    proxy!.setBruteForceModeEnabled(true);
    proxy!.setBruteForceModeEnabled(false);
    proxy!.setBruteForceModeEnabled(true);
    expect((await old).statusCode, 503);
    final hitsAtCancellation = hits;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(hits, hitsAtCancellation);
    expect(unavailable, 0);
  });

  test(
    'disabling a pinned endpoint cancels its request without failover',
    () async {
      final first = Completer<void>();
      final a = await upstream((request) async {
        if (!first.isCompleted) first.complete();
      });
      var backupHits = 0;
      final b = await upstream((request) async {
        backupHits++;
        await request.response.close();
      });
      await start([endpoint('a', a.port), endpoint('b', b.port)]);
      final old = send();
      await first.future;
      proxy!.endpoints = [
        endpoint('a', a.port).copyWith(enabled: false),
        endpoint('b', b.port),
      ];
      expect((await old).statusCode, 503);
      expect(backupHits, 0);
      expect(unavailable, 0);
    },
  );

  test('each concurrent request has its own deadline and connection', () async {
    var hits = 0;
    final first = Completer<void>();
    final a = await upstream((request) async {
      if (++hits == 1) {
        first.complete();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 110));
      request.response.write('{}');
      await request.response.close();
    });
    await start([endpoint('a', a.port)], timeout: 300);
    final old = send();
    await first.future;
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final next = send();
    expect((await old).statusCode, 504);
    expect((await next).statusCode, 200);
  });

  for (final format in [
    EndpointApiFormat.openai,
    EndpointApiFormat.openaiResponses,
  ]) {
    test('retries and converts ${format.name} responses', () async {
      var hits = 0;
      final a = await upstream((request) async {
        if (++hits == 1) {
          request.response.statusCode = 403;
          request.response.write('{"error":{"message":"temporary"}}');
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              format == EndpointApiFormat.openai
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
}
