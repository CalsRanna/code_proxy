import 'dart:convert';

import 'package:code_proxy/service/proxy_server/converter/openai_compat_response_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = OpenAiCompatResponseConverter();

  Map<String, dynamic> convertResponse(Map<String, dynamic> body) {
    return converter.convertResponse(body, originalModel: 'claude-sonnet-4-5');
  }

  group('非流式响应转换', () {
    test('纯文本响应完整转换', () {
      final result = convertResponse({
        'id': 'chatcmpl-abc',
        'object': 'chat.completion',
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': 'Hello!'},
            'finish_reason': 'stop',
          },
        ],
        'usage': {
          'prompt_tokens': 100,
          'completion_tokens': 50,
          'total_tokens': 150,
        },
      });

      expect(result['id'], 'chatcmpl-abc');
      expect(result['type'], 'message');
      expect(result['role'], 'assistant');
      // model 回填客户端原始模型名
      expect(result['model'], 'claude-sonnet-4-5');
      expect(result['content'], [
        {'type': 'text', 'text': 'Hello!'},
      ]);
      expect(result['stop_reason'], 'end_turn');
      expect(result['stop_sequence'], isNull);
      expect(result['usage']['input_tokens'], 100);
      expect(result['usage']['output_tokens'], 50);
    });

    test('tool_calls 转为 tool_use block，arguments 解析为 input', () {
      final result = convertResponse({
        'id': 'chatcmpl-2',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {
                  'id': 'call_01',
                  'type': 'function',
                  'function': {
                    'name': 'get_weather',
                    'arguments': '{"city": "Beijing"}',
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
        'usage': {'prompt_tokens': 10, 'completion_tokens': 20},
      });

      expect(result['stop_reason'], 'tool_use');
      expect(result['content'][0], {
        'type': 'tool_use',
        'id': 'call_01',
        'name': 'get_weather',
        'input': {'city': 'Beijing'},
      });
    });

    test('arguments 为坏 JSON 时兜底 raw_arguments 而不抛错', () {
      final result = convertResponse({
        'id': 'x',
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': 'c1',
                  'type': 'function',
                  'function': {'name': 'f', 'arguments': '{"broken'},
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });
      expect(result['content'][0]['input'], {'raw_arguments': '{"broken'});
    });

    test('文本 + 工具调用混合时按序生成 content blocks', () {
      final result = convertResponse({
        'id': 'x',
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': 'Checking now.',
              'tool_calls': [
                {
                  'id': 'c1',
                  'type': 'function',
                  'function': {'name': 'f', 'arguments': '{}'},
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });
      final content = result['content'] as List;
      expect(content, hasLength(2));
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'tool_use');
    });

    test('finish_reason 映射表', () {
      Map<String, dynamic> withFinish(String reason) => convertResponse({
        'id': 'x',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 't'},
            'finish_reason': reason,
          },
        ],
      });

      expect(withFinish('stop')['stop_reason'], 'end_turn');
      expect(withFinish('length')['stop_reason'], 'max_tokens');
      expect(withFinish('tool_calls')['stop_reason'], 'tool_use');
      expect(withFinish('function_call')['stop_reason'], 'tool_use');
      expect(withFinish('unknown_xx')['stop_reason'], 'end_turn');
    });

    test('cached_tokens 映射为 cache_read_input_tokens', () {
      final result = convertResponse({
        'id': 'x',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 't'},
            'finish_reason': 'stop',
          },
        ],
        'usage': {
          'prompt_tokens': 100,
          'completion_tokens': 10,
          'prompt_tokens_details': {'cached_tokens': 80},
        },
      });
      expect(result['usage']['input_tokens'], 20);
      expect(result['usage']['cache_read_input_tokens'], 80);
      expect(result['usage']['cache_creation_input_tokens'], 0);
    });

    test('cache_write_tokens 映射后不会重复计入普通输入', () {
      final result = convertResponse({
        'id': 'x',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 't'},
            'finish_reason': 'stop',
          },
        ],
        'usage': {
          'prompt_tokens': 100,
          'completion_tokens': 10,
          'prompt_tokens_details': {
            'cached_tokens': 60,
            'cache_write_tokens': 20,
          },
        },
      });

      expect(result['usage'], {
        'input_tokens': 20,
        'output_tokens': 10,
        'cache_read_input_tokens': 60,
        'cache_creation_input_tokens': 20,
      });
    });

    test('usage 缺失时归零不抛错', () {
      final result = convertResponse({
        'id': 'x',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 't'},
            'finish_reason': 'stop',
          },
        ],
      });
      expect(result['usage']['input_tokens'], 0);
      expect(result['usage']['output_tokens'], 0);
    });

    test('空 content 补空 text block 保证协议合法', () {
      final result = convertResponse({
        'id': 'x',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': ''},
            'finish_reason': 'stop',
          },
        ],
      });
      expect((result['content'] as List), hasLength(1));
      expect(result['content'][0], {'type': 'text', 'text': ''});
    });

    test('畸形响应（无 choices）返回空消息不抛错', () {
      final result = convertResponse({'id': 'weird', 'object': 'error'});
      expect(result['type'], 'message');
      expect((result['content'] as List)[0]['text'], '');
    });

    test('reasoning_content 转为 thinking block 且置于 content 首位', () {
      final result = convertResponse({
        'id': 'x',
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'reasoning_content': 'Let me think about it.',
              'content': 'Answer is 42.',
            },
            'finish_reason': 'stop',
          },
        ],
      });
      final content = result['content'] as List;
      expect(content, hasLength(2));
      expect(content[0], {
        'type': 'thinking',
        'thinking': 'Let me think about it.',
      });
      expect(content[1]['type'], 'text');
      expect(content[1]['text'], 'Answer is 42.');
    });

    test('reasoning 字段（OpenRouter 命名）同样转换', () {
      final result = convertResponse({
        'id': 'x',
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'reasoning': 'step by step',
              'content': 'done',
            },
            'finish_reason': 'stop',
          },
        ],
      });
      expect(result['content'][0], {
        'type': 'thinking',
        'thinking': 'step by step',
      });
    });

    test('无 reasoning 时 content 不含 thinking block', () {
      final result = convertResponse({
        'id': 'x',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 't'},
            'finish_reason': 'stop',
          },
        ],
      });
      expect(
        (result['content'] as List).every((b) => b['type'] != 'thinking'),
        isTrue,
      );
    });
  });

  group('错误响应转换', () {
    test('标准 OpenAI 错误体转 Anthropic 格式', () {
      final result = converter.convertErrorBody(
        jsonEncode({
          'error': {
            'message': 'Incorrect API key provided.',
            'type': 'invalid_request_error',
            'code': 'invalid_api_key',
          },
        }),
      );
      expect(result['type'], 'error');
      expect(result['error']['type'], 'authentication_error');
      expect(result['error']['message'], 'Incorrect API key provided.');
    });

    test('rate limit 错误映射', () {
      final result = converter.convertErrorBody(
        jsonEncode({
          'error': {
            'message': 'Rate limit reached',
            'type': 'rate_limit_error',
          },
        }),
      );
      expect(result['error']['type'], 'rate_limit_error');
    });

    test('quota 错误映射为 billing_error', () {
      final result = converter.convertErrorBody(
        jsonEncode({
          'error': {
            'message': 'insufficient quota',
            'type': 'insufficient_quota',
          },
        }),
      );
      expect(result['error']['type'], 'billing_error');
    });

    test('非 JSON 错误体保留原文包进 api_error', () {
      final result = converter.convertErrorBody('<html>Bad Gateway</html>');
      expect(result['error']['type'], 'api_error');
      expect(result['error']['message'], '<html>Bad Gateway</html>');
    });

    test('空错误体不抛错', () {
      final result = converter.convertErrorBody('');
      expect(result['error']['type'], 'api_error');
    });

    test('mapErrorTypeFromStatus 状态码映射', () {
      expect(
        OpenAiCompatResponseConverter.mapErrorTypeFromStatus(400),
        'invalid_request_error',
      );
      expect(
        OpenAiCompatResponseConverter.mapErrorTypeFromStatus(401),
        'authentication_error',
      );
      expect(
        OpenAiCompatResponseConverter.mapErrorTypeFromStatus(429),
        'rate_limit_error',
      );
      expect(
        OpenAiCompatResponseConverter.mapErrorTypeFromStatus(503),
        'api_error',
      );
    });
  });
}
