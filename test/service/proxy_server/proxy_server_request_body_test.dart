import 'dart:convert';

import 'package:code_proxy/service/proxy_server/proxy_server_request_body.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProxyServerRequestBody', () {
    test('空字节不解析', () {
      final body = ProxyServerRequestBody.empty();
      expect(body.bytes, isEmpty);
      expect(body.json, isNull);
      expect(body.originalModel, isNull);
    });

    test('非法 JSON 返回 null 且不抛', () {
      final body = ProxyServerRequestBody(utf8.encode('{invalid'));
      expect(body.json, isNull);
      expect(body.originalModel, isNull);
    });

    test('非法 UTF-8 返回 null 且不抛', () {
      expect(ProxyServerRequestBody(const [0xff]).json, isNull);
    });

    test('非对象 JSON 返回 null', () {
      for (final raw in ['[]', '123', '"text"', 'null', 'true']) {
        expect(
          ProxyServerRequestBody(utf8.encode(raw)).json,
          isNull,
          reason: raw,
        );
      }
    });

    test('解析结果缓存为同一实例', () {
      final body = ProxyServerRequestBody(utf8.encode('{"model":"m"}'));
      expect(identical(body.json, body.json), isTrue);
    });

    test('originalModel 取映射前模型名，缺失或非字符串时为 null', () {
      expect(
        ProxyServerRequestBody(
          utf8.encode('{"model":"claude-opus-5"}'),
        ).originalModel,
        'claude-opus-5',
      );
      expect(
        ProxyServerRequestBody(utf8.encode('{"model":123}')).originalModel,
        isNull,
      );
      expect(ProxyServerRequestBody(utf8.encode('{}')).originalModel, isNull);
    });
  });
}
