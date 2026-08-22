import 'dart:convert';

import 'package:code_proxy/service/proxy_server/converter/openai_responses_request_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = OpenAiResponsesRequestConverter();

  Map<String, dynamic> convert(Map<String, dynamic> body) =>
      converter.convert(body);

  test('最小请求：model/input/stream/store 基础字段', () {
    final out = convert({
      'model': 'gpt-5',
      'max_tokens': 1024,
      'stream': false,
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    });

    expect(out['model'], 'gpt-5');
    expect(out['stream'], false);
    expect(out['store'], false);
    expect(out['max_output_tokens'], 1024);
    expect(out['input'], [
      {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': 'hi'},
        ],
      },
    ]);
    // Anthropic 专有字段不透传
    expect(out.containsKey('messages'), isFalse);
    expect(out.containsKey('max_tokens'), isFalse);
  });

  test('system 字符串 → instructions', () {
    final out = convert({
      'model': 'gpt-5',
      'system': 'You are helpful.',
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    });
    expect(out['instructions'], 'You are helpful.');
  });

  test('system blocks 数组 → 多个 text block 空行连接', () {
    final out = convert({
      'model': 'gpt-5',
      'system': [
        {
          'type': 'text',
          'text': 'Rule A',
          'cache_control': {'type': 'ephemeral'},
        },
        {'type': 'text', 'text': 'Rule B'},
      ],
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    });
    expect(out['instructions'], 'Rule A\n\nRule B');
  });

  test('assistant text + tool_use → message item + function_call item', () {
    final out = convert({
      'model': 'gpt-5',
      'messages': [
        {
          'role': 'assistant',
          'content': [
            {'type': 'thinking', 'thinking': 'let me think'},
            {'type': 'text', 'text': 'Let me check.'},
            {
              'type': 'tool_use',
              'id': 'toolu_01',
              'name': 'get_weather',
              'input': {'city': 'Tokyo'},
            },
          ],
        },
      ],
    });

    final input = out['input'] as List;
    expect(input, hasLength(2));
    expect(input[0], {
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'output_text', 'text': 'Let me check.'},
      ],
    });
    expect(input[1], {
      'type': 'function_call',
      'call_id': 'toolu_01',
      'name': 'get_weather',
      'arguments': '{"city":"Tokyo"}',
    });
    // thinking 块剥离
    expect(jsonEncode(input), isNot(contains('let me think')));
  });

  test('user tool_result → function_call_output，与普通内容保序', () {
    final out = convert({
      'model': 'gpt-5',
      'messages': [
        {'role': 'user', 'content': 'what is the weather?'},
        {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'id': 'toolu_01',
              'name': 'get_weather',
              'input': {'city': 'Tokyo'},
            },
          ],
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'toolu_01',
              'content': [
                {'type': 'text', 'text': 'Sunny, 22C'},
              ],
            },
            {'type': 'text', 'text': 'and tomorrow?'},
          ],
        },
      ],
    });

    final input = out['input'] as List;
    expect(input, hasLength(4));
    expect(input[2], {
      'type': 'function_call_output',
      'call_id': 'toolu_01',
      'output': 'Sunny, 22C',
    });
    expect(input[3]['type'], 'message');
    expect((input[3]['content'] as List)[0]['text'], 'and tomorrow?');
  });

  test('image base64 source → input_image data URI', () {
    final out = convert({
      'model': 'gpt-5',
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/png',
                'data': 'aGVsbG8=',
              },
            },
          ],
        },
      ],
    });

    final content = (out['input'] as List)[0]['content'] as List;
    expect(content[0], {
      'type': 'input_image',
      'image_url': 'data:image/png;base64,aGVsbG8=',
    });
  });

  test('document 纯文本 source 保留为文本，PDF source 降级占位', () {
    final out = convert({
      'model': 'gpt-5',
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'document',
              'title': 'Notes',
              'source': {'type': 'text', 'data': 'plain content'},
            },
            {
              'type': 'document',
              'source': {
                'type': 'base64',
                'media_type': 'application/pdf',
                'data': 'xx',
              },
            },
          ],
        },
      ],
    });

    final content = (out['input'] as List)[0]['content'] as List;
    expect(content[0]['type'], 'input_text');
    expect(content[0]['text'], contains('Document: Notes'));
    expect(content[0]['text'], contains('plain content'));
    expect(content[1]['type'], 'input_text');
    expect(content[1]['text'], contains('not convertible'));
  });

  test('tools 转换：扁平 function 结构（无嵌套），server tools 丢弃', () {
    final out = convert({
      'model': 'gpt-5',
      'tools': [
        {
          'name': 'get_weather',
          'description': 'Get weather',
          'input_schema': {
            'type': 'object',
            'properties': {'city': {'type': 'string'}},
          },
        },
        {
          'type': 'web_search_20250305',
          'name': 'web_search',
        },
      ],
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    });

    expect(out['tools'], [
      {
        'type': 'function',
        'name': 'get_weather',
        'description': 'Get weather',
        'parameters': {
          'type': 'object',
          'properties': {'city': {'type': 'string'}},
        },
      },
    ]);
  });

  group('tool_choice', () {
    test('auto/any/none/tool 四种映射', () {
      Map<String, dynamic> tc(Map<String, dynamic> toolChoice) => convert({
            'model': 'gpt-5',
            'tool_choice': toolChoice,
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          });

      expect(tc({'type': 'auto'})['tool_choice'], 'auto');
      expect(tc({'type': 'any'})['tool_choice'], 'required');
      expect(tc({'type': 'none'})['tool_choice'], 'none');
      expect(tc({'type': 'tool', 'name': 'get_weather'})['tool_choice'], {
        'type': 'function',
        'name': 'get_weather',
      });
    });
  });

  group('output_config.effort 转换', () {
    test('effort 恒等透传，无需 thinking 参数（Fable 5 形态）', () {
      final out = convert({
        'model': 'gpt-5',
        'output_config': {'effort': 'max'},
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      expect(out['reasoning'], {'effort': 'max'});
    });

    test('effort 不降级：xhigh/max 原样透传', () {
      Map<String, dynamic> withEffort(String effort) => convert({
            'model': 'gpt-5',
            'output_config': {'effort': effort},
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
          });
      expect(withEffort('xhigh')['reasoning'], {'effort': 'xhigh'});
      expect(withEffort('low')['reasoning'], {'effort': 'low'});
    });

    test('旧形态 enabled + budget 不发送 reasoning', () {
      final out = convert({
        'model': 'gpt-5',
        'thinking': {'type': 'enabled', 'budget_tokens': 10240},
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      expect(out.containsKey('reasoning'), isFalse);
    });

    test('disabled / 未携带 effort 不发送 reasoning', () {
      final disabled = convert({
        'model': 'gpt-5',
        'thinking': {'type': 'disabled'},
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      expect(disabled.containsKey('reasoning'), isFalse);
    });
  });

  test('temperature/top_p 透传，stop_sequences 丢弃', () {
    final out = convert({
      'model': 'gpt-5',
      'temperature': 0.7,
      'top_p': 0.9,
      'stop_sequences': ['END'],
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    });
    expect(out['temperature'], 0.7);
    expect(out['top_p'], 0.9);
    expect(out.containsKey('stop_sequences'), isFalse);
    expect(out.containsKey('stop'), isFalse);
  });

  test('全块被剥离的 user 消息保留空消息维持轮次交替', () {
    final out = convert({
      'model': 'gpt-5',
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'thinking', 'thinking': 'x'},
          ],
        },
        {'role': 'assistant', 'content': 'ok'},
      ],
    });

    final input = out['input'] as List;
    expect(input, hasLength(2));
    expect((input[0]['content'] as List)[0],
        {'type': 'input_text', 'text': ''});
  });
}
