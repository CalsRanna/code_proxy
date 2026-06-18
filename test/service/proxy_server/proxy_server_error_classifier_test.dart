import 'dart:io';

import 'package:code_proxy/service/proxy_server/proxy_server_error_classifier.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProxyServerErrorClassifier.isHeaderNotReceived', () {
    test('匹配 header 未达的 ClientException', () {
      final error = http.ClientException(
        'Connection closed before full header was received',
      );
      expect(ProxyServerErrorClassifier.isHeaderNotReceived(error), isTrue);
    });

    test('带前后缀文本仍匹配', () {
      final error = http.ClientException(
        'ClientException: Connection closed before full header was received, '
        'uri=https://example.com',
      );
      expect(ProxyServerErrorClassifier.isHeaderNotReceived(error), isTrue);
    });

    test('其它消息的 ClientException 不匹配', () {
      final error = http.ClientException('Connection reset by peer');
      expect(ProxyServerErrorClassifier.isHeaderNotReceived(error), isFalse);
    });

    test('SocketException 不匹配', () {
      expect(
        ProxyServerErrorClassifier.isHeaderNotReceived(
          const SocketException('failed'),
        ),
        isFalse,
      );
    });

    test('HandshakeException 不匹配', () {
      expect(
        ProxyServerErrorClassifier.isHeaderNotReceived(
          const HandshakeException('handshake failed'),
        ),
        isFalse,
      );
    });

    test('TlsException 不匹配', () {
      expect(
        ProxyServerErrorClassifier.isHeaderNotReceived(
          const TlsException('tls failed'),
        ),
        isFalse,
      );
    });

    test('非异常对象不匹配', () {
      expect(
        ProxyServerErrorClassifier.isHeaderNotReceived('a string'),
        isFalse,
      );
    });
  });

  group('ProxyServerErrorClassifier.isPossibleHeaderNotReceivedVariant', () {
    test('精确命中的不算变体(避免与正常路径重复告警)', () {
      final error = http.ClientException(
        'Connection closed before full header was received',
      );
      expect(
        ProxyServerErrorClassifier.isPossibleHeaderNotReceivedVariant(error),
        isFalse,
      );
    });

    test('措辞接近但不精确命中算变体(疑似 SDK 改了文案)', () {
      final error = http.ClientException(
        'Connection closed while awaiting response header',
      );
      expect(
        ProxyServerErrorClassifier.isPossibleHeaderNotReceivedVariant(error),
        isTrue,
      );
    });

    test('大小写不同仍算变体', () {
      final error = http.ClientException(
        'CONNECTION CLOSED before the HEADER arrived',
      );
      expect(
        ProxyServerErrorClassifier.isPossibleHeaderNotReceivedVariant(error),
        isTrue,
      );
    });

    test('普通连接重置不算变体(无 header 关键词)', () {
      final error = http.ClientException('Connection closed by peer');
      expect(
        ProxyServerErrorClassifier.isPossibleHeaderNotReceivedVariant(error),
        isFalse,
      );
    });

    test('非 ClientException 不算变体', () {
      expect(
        ProxyServerErrorClassifier.isPossibleHeaderNotReceivedVariant(
          const SocketException('failed'),
        ),
        isFalse,
      );
    });
  });
}
