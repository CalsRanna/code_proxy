import 'dart:convert';

import 'package:code_proxy/service/proxy_server/proxy_server_token_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProxyServerTokenEstimator', () {
    group('estimate', () {
      test('空字符串返回 0', () {
        expect(ProxyServerTokenEstimator.estimate(''), 0);
      });

      test('纯英文文本', () {
        // "hello" = 5 字符 / 4 ≈ 1
        expect(ProxyServerTokenEstimator.estimate('hello'), greaterThan(0));
        // 约 4 字符 = 1 token
        expect(ProxyServerTokenEstimator.estimate('abcd'), 1);
      });

      test('纯中文文本', () {
        // 中文约 1 字 = 1 token
        const text = '你好世界';
        final tokens = ProxyServerTokenEstimator.estimate(text);
        expect(tokens, 4); // 4 个中文字 = 4 tokens
      });

      test('中英混排文本', () {
        // "hello世界" = 5 英文 (≈1 token) + 2 中文 (=2) ≈ 3
        final tokens = ProxyServerTokenEstimator.estimate('hello世界');
        expect(tokens, greaterThan(1));
        expect(tokens, lessThan(10));
      });

      test('长英文段落', () {
        const text = 'The quick brown fox jumps over the lazy dog';
        // 43 字符不含空格, 含空格约 43+8=51  / 4 ≈ 12-13
        final tokens = ProxyServerTokenEstimator.estimate(text);
        expect(tokens, greaterThan(8));
        expect(tokens, lessThan(20));
      });
    });

    group('estimateRequestBody', () {
      test('空请求体返回 0', () {
        expect(ProxyServerTokenEstimator.estimateRequestBody([]), 0);
      });

      test('简单消息（system + user message）', () {
        final body = jsonEncode({
          'system': 'You are a helpful assistant.',
          'messages': [
            {'role': 'user', 'content': 'Hello'},
          ],
        });
        final tokens = ProxyServerTokenEstimator.estimateRequestBody(
          utf8.encode(body),
        );
        expect(tokens, greaterThan(0));
        // system "You are a helpful assistant." ≈ 30 英文字符/4 ≈ 7-8
        // + 5 (message overhead) + "Hello"/4 ≈ 1 = ~13
        expect(tokens, greaterThan(5));
        expect(tokens, lessThan(30));
      });

      test('带 tools 的请求体', () {
        final body = jsonEncode({
          'system': 'You are a coding assistant.',
          'messages': [
            {'role': 'user', 'content': 'Write a function'},
          ],
          'tools': [
            {
              'name': 'read_file',
              'description': 'Read a file from disk',
              'input_schema': {'type': 'object', 'properties': {}},
            },
          ],
        });
        final tokens = ProxyServerTokenEstimator.estimateRequestBody(
          utf8.encode(body),
        );
        expect(tokens, greaterThan(0));
        // 带 tools 的请求体应显著大于不带 tools 的
        final bodyNoTools = jsonEncode({
          'messages': [
            {'role': 'user', 'content': 'Write a function'},
          ],
        });
        final tokensNoTools = ProxyServerTokenEstimator.estimateRequestBody(
          utf8.encode(bodyNoTools),
        );
        expect(tokens, greaterThan(tokensNoTools));
      });

      test('CJK system prompt + messages', () {
        final body = jsonEncode({
          'system': '你是一个有用的编程助手',
          'messages': [
            {'role': 'user', 'content': '帮我写一段代码'},
          ],
        });
        final tokens = ProxyServerTokenEstimator.estimateRequestBody(
          utf8.encode(body),
        );
        // "你是一个有用的编程助手" = 10 CJK ≈ 10 tokens
        // + 5 (msg overhead) + "帮我写一段代码" = 7 CJK ≈ 7 ≈ 22
        expect(tokens, greaterThan(15));
        expect(tokens, lessThan(40));
      });

      test('无效 JSON 返回 0', () {
        expect(ProxyServerTokenEstimator.estimateRequestBody([1, 2, 3]), 0);
      });

      test('含 content block 数组的消息', () {
        final body = jsonEncode({
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'First block'},
                {'type': 'text', 'text': 'Second block'},
              ],
            },
          ],
        });
        final tokens = ProxyServerTokenEstimator.estimateRequestBody(
          utf8.encode(body),
        );
        expect(tokens, greaterThan(0));
      });
    });
  });
}
