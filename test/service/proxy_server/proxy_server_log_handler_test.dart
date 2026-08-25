import 'dart:convert';

import 'package:code_proxy/service/proxy_server/proxy_server_log_handler.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_request.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response.dart';
import 'package:code_proxy/service/proxy_server/proxy_server_response_handler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  group('RequestLogErrorMessage', () {
    test('errorBody 为空时应回退到 responseBody', () {
      final handler = ProxyServerLogHandler.create();
      final log = handler.buildRequestLog(
        endpoint: createEndpoint(),
        request: const ProxyServerRequest(
          method: 'POST',
          path: '/v1/messages',
          headers: {},
          body: '{"model":"MiniMax-M2.5"}',
        ),
        response: const ProxyServerResponse(
          statusCode: 500,
          headers: {},
          responseTime: 100,
          errorBody: '   ',
          responseBody: '{"error":"upstream failure"}',
        ),
      );

      expect(log.errorMessage, '{"error":"upstream failure"}');
    });

    test('5xx 且响应体为空时应写入默认错误信息', () {
      final handler = ProxyServerLogHandler.create();
      final log = handler.buildRequestLog(
        endpoint: createEndpoint(),
        request: const ProxyServerRequest(
          method: 'POST',
          path: '/v1/messages',
          headers: {},
          body: '{"model":"MiniMax-M2.5"}',
        ),
        response: const ProxyServerResponse(
          statusCode: 500,
          headers: {},
          responseTime: 100,
          errorBody: '',
          responseBody: '',
        ),
      );

      expect(log.errorMessage, 'HTTP 500 with empty response body');
    });

    test('3xx 的正常响应体不应被写入 error_message', () {
      final handler = ProxyServerLogHandler.create();
      final log = handler.buildRequestLog(
        endpoint: createEndpoint(),
        request: const ProxyServerRequest(
          method: 'POST',
          path: '/v1/messages',
          headers: {},
          body: '{"model":"claude-opus-5"}',
        ),
        response: const ProxyServerResponse(
          statusCode: 304,
          headers: {},
          responseTime: 100,
          responseBody: '{"content":[{"text":"正常的模型响应体"}]}',
        ),
      );

      expect(log.errorMessage, isNull);
    });

    test('失败请求提取到的 usage 应如实入库', () {
      final handler = ProxyServerLogHandler.create();
      final log = handler.buildRequestLog(
        endpoint: createEndpoint(),
        request: const ProxyServerRequest(
          method: 'POST',
          path: '/v1/messages',
          headers: {},
          body: '{"model":"claude-opus-5"}',
        ),
        response: const ProxyServerResponse(
          statusCode: 500,
          headers: {},
          responseTime: 100,
          usage: {
            'input': 1234,
            'output': 56,
            'cache_creation': 7,
            'cache_read': 8,
          },
          errorBody: 'internal error',
        ),
      );

      expect(log.inputTokens, 1234);
      expect(log.outputTokens, 56);
      expect(log.cacheCreationInputTokens, 7);
      expect(log.cacheReadInputTokens, 8);
      expect(log.errorMessage, 'internal error');
    });

    test('不可读响应体应生成可见摘要', () {
      final text = ResponseDecompressor.decodeForLogging(utf8.encode(''), null);
      expect(text, isEmpty);

      final binarySummary = ResponseDecompressor.decodeForLogging(const [
        0,
        159,
        146,
        150,
        255,
      ], 'br');
      expect(binarySummary, contains('non-text response body'));
      expect(binarySummary, contains('content-encoding: br'));
      expect(binarySummary, contains('base64:'));
    });
  });
}
