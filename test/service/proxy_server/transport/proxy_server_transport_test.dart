import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_proxy/service/proxy_server/transport/proxy_server_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _HttpProxy extends HttpOverrides {
  _HttpProxy(this.port);
  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (_) => 'PROXY 127.0.0.1:$port';
}

void main() {
  test('HTTPS 经 HTTP 代理先发明文 CONNECT', () async {
    final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(proxy.close);
    final request = Completer<String>();
    proxy.listen((socket) {
      addTearDown(socket.destroy);
      final buffer = <int>[];
      socket.listen((data) {
        buffer.addAll(data);
        final text = latin1.decode(buffer);
        if (!request.isCompleted && text.contains('\r\n\r\n')) {
          request.complete(text);
          // 不连接外网，隧道握手测试在此结束。
          socket.write('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n');
          unawaited(socket.close());
        }
      });
    });
    await HttpOverrides.runWithHttpOverrides(() async {
      final transport = ProxyServerTransport(apiTimeoutMs: 500);
      addTearDown(transport.close);
      await expectLater(
        transport.forwardRequest(
          http.Request(
            'POST',
            Uri.parse('https://api.example.test/v1/messages'),
          ),
        ),
        throwsA(anything),
      );
      expect(
        await request.future.timeout(const Duration(seconds: 1)),
        startsWith('CONNECT api.example.test:443 HTTP/1.1\r\n'),
      );
    }, _HttpProxy(proxy.port));
  });
}
