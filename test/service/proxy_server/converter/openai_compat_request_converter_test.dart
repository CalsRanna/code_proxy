import 'dart:convert';

import 'package:code_proxy/service/proxy_server/converter/openai_compat_request_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = OpenAiCompatRequestConverter();

  Map<String, dynamic> convert(Map<String, dynamic> body) {
    return converter.convert(body);
  }

  group('顶层字段映射', () {
    test('基础参数透传与重命名', () {
      final result = convert({
        'model': 'gpt-4o',
        'max_tokens': 1024,
        'temperature': 0.7,
        'top_p': 0.9,
        'stop_sequences': ['END', 'STOP'],
        'stream': false,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });

      expect(result['model'], 'gpt-4o');
      expect(result['max_tokens'], 1024);
      expect(result['temperature'], 0.7);
      expect(result['top_p'], 0.9);
      expect(result['stop'], ['END', 'STOP']);
      expect(result['stream'], false);
      expect(result.containsKey('stop_sequences'), isFalse);
    });

    test('流式请求注入 stream_options.include_usage', () {
      final result = convert({
        'model': 'gpt-4o',
        'stream': true,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      expect(result['stream_options']['include_usage'], isTrue);

      final nonStream = convert({
        'model': 'gpt-4o',
        'stream': false,
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      expect(nonStream.containsKey('stream_options'), isFalse);
    });
  });

  group('system 字段转换', () {
    test('system 缺省时不生成 system 消息', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      expect(result['messages'], hasLength(1));
      expect(result['messages'][0]['role'], 'user');
    });

    test('system 为字符串时转为 system 消息', () {
      final result = convert({
        'model': 'm',
        'system': 'You are helpful.',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      expect(result['messages'][0], {
        'role': 'system',
        'content': 'You are helpful.',
      });
    });

    test('system 为 blocks 数组时拼接 text 并剥离 cache_control', () {
      final result = convert({
        'model': 'm',
        'system': [
          {
            'type': 'text',
            'text': 'Part one.',
            'cache_control': {'type': 'ephemeral'},
          },
          {'type': 'text', 'text': 'Part two.'},
        ],
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      expect(result['messages'][0]['content'], 'Part one.\n\nPart two.');
      expect(jsonEncode(result), isNot(contains('cache_control')));
    });
  });

  group('user 消息转换', () {
    test('纯文本 content 原样保留', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {'role': 'user', 'content': 'hello'},
        ],
      });
      expect(result['messages'][0], {'role': 'user', 'content': 'hello'});
    });

    test('多块图文混排保持数组形态，base64 图片转 data URI', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/png',
                  'data': 'QUJD',
                },
              },
              {'type': 'text', 'text': '这是什么？'},
            ],
          },
        ],
      });
      final content = result['messages'][0]['content'] as List;
      expect(content, hasLength(2));
      expect(content[0]['type'], 'image_url');
      expect(content[0]['image_url']['url'], 'data:image/png;base64,QUJD');
      expect(content[1], {'type': 'text', 'text': '这是什么？'});
    });

    test('url source 图片直传 URL', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {'type': 'url', 'url': 'https://example.com/a.png'},
              },
            ],
          },
        ],
      });
      expect(
        (result['messages'][0]['content'] as List)[0]['image_url']['url'],
        'https://example.com/a.png',
      );
    });

    test('单个 text 块降级为纯字符串', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'only text'},
            ],
          },
        ],
      });
      expect(result['messages'][0]['content'], 'only text');
    });

    test('document 文本 source 降级为 text 块', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'document',
                'title': 'notes',
                'source': {'type': 'text', 'data': 'file content'},
              },
            ],
          },
        ],
      });
      // 单个 text 内容块降级为纯字符串
      final text = result['messages'][0]['content'] as String;
      expect(text, contains('Document: notes'));
      expect(text, contains('file content'));
    });

    test('仅含 thinking 的 user 消息保留空 user 占位', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'thinking', 'thinking': '...', 'signature': 'x'},
            ],
          },
        ],
      });
      expect(result['messages'][0], {'role': 'user', 'content': ''});
    });
  });

  group('assistant 消息与工具调用往返', () {
    test('tool_use 转为 tool_calls，input 序列化为 arguments', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Let me check.'},
              {
                'type': 'tool_use',
                'id': 'toolu_01',
                'name': 'read_file',
                'input': {'path': '/a.txt'},
              },
            ],
          },
        ],
      });
      final msg = result['messages'][0];
      expect(msg['role'], 'assistant');
      expect(msg['content'], 'Let me check.');
      expect((msg['tool_calls'] as List)[0], {
        'id': 'toolu_01',
        'type': 'function',
        'function': {
          'name': 'read_file',
          'arguments': '{"path":"/a.txt"}',
        },
      });
    });

    test('assistant 历史 thinking 块被剥离', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'thinking',
                'thinking': 'internal',
                'signature': 'sig',
              },
              {'type': 'text', 'text': 'answer'},
            ],
          },
        ],
      });
      final msg = result['messages'][0];
      expect(msg['content'], 'answer');
      expect(msg.containsKey('tool_calls'), isFalse);
      expect(jsonEncode(result), isNot(contains('thinking')));
    });

    test('tool_result 展开为 role:tool 消息且紧跟 assistant', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {
            'role': 'user',
            'content': 'list files',
          },
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_01',
                'name': 'ls',
                'input': {},
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
                  {'type': 'text', 'text': 'a.txt\nb.txt'},
                ],
              },
              {'type': 'text', 'text': 'and also look at this'},
            ],
          },
        ],
      });

      final messages = result['messages'] as List;
      expect(messages[1]['role'], 'assistant');
      // tool_result 先展开为 tool 消息
      expect(messages[2]['role'], 'tool');
      expect(messages[2]['tool_call_id'], 'toolu_01');
      expect(messages[2]['content'], 'a.txt\nb.txt');
      // 同消息内混排的普通文本追加为后续 user 消息
      expect(messages[3], {'role': 'user', 'content': 'and also look at this'});
    });

    test('tool_result 内容为字符串时原样保留', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 't1',
                'content': 'plain output',
              },
            ],
          },
        ],
      });
      expect(result['messages'][0]['content'], 'plain output');
    });
  });

  group('tools 与 tool_choice', () {
    test('自定义工具转 function 定义', () {
      final result = convert({
        'model': 'm',
        'tools': [
          {
            'name': 'get_weather',
            'description': 'Get weather',
            'input_schema': {
              'type': 'object',
              'properties': {'city': {'type': 'string'}},
            },
          },
        ],
        'messages': [
          {'role': 'user', 'content': 'x'},
        ],
      });
      final tools = result['tools'] as List;
      expect(tools[0], {
        'type': 'function',
        'function': {
          'name': 'get_weather',
          'description': 'Get weather',
          'parameters': {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
          },
        },
      });
    });

    test('server tools 与无效工具被过滤', () {
      final result = convert({
        'model': 'm',
        'tools': [
          {'type': 'web_search_20250305', 'name': 'web_search'},
          {'name': '', 'description': '', 'input_schema': {}},
          {'type': 'custom', 'name': 'ok', 'description': 'd', 'input_schema': {}},
        ],
        'messages': [
          {'role': 'user', 'content': 'x'},
        ],
      });
      final tools = result['tools'] as List;
      expect(tools, hasLength(1));
      expect(tools[0]['function']['name'], 'ok');
    });

    test('tool_choice 四种分支映射正确', () {
      Map<String, dynamic> withChoice(Map<String, dynamic> choice) {
        return convert({
          'model': 'm',
          'tool_choice': choice,
          'messages': [
            {'role': 'user', 'content': 'x'},
          ],
        });
      }

      expect(withChoice({'type': 'auto'})['tool_choice'], 'auto');
      expect(withChoice({'type': 'any'})['tool_choice'], 'required');
      expect(withChoice({'type': 'none'})['tool_choice'], 'none');
      expect(withChoice({'type': 'tool', 'name': 't1'})['tool_choice'], {
        'type': 'function',
        'function': {'name': 't1'},
      });
    });

    test('无 tools 时即使有 tool_choice 也不生成 tools', () {
      final result = convert({
        'model': 'm',
        'tool_choice': {'type': 'auto'},
        'messages': [
          {'role': 'user', 'content': 'x'},
        ],
      });
      expect(result.containsKey('tools'), isFalse);
      expect(result['tool_choice'], 'auto');
    });
  });

  group('thinking 参数转换', () {
    test('thinking.enabled 带 budget 转为 reasoning effort + max_tokens', () {
      final result = convert({
        'model': 'm',
        'thinking': {'type': 'enabled', 'budget_tokens': 10240},
        'messages': [
          {'role': 'user', 'content': 'x'},
        ],
      });
      expect(result['reasoning'], {'effort': 'medium', 'max_tokens': 10240});
    });

    test('budget 分档映射：小 budget → low，大 budget → high', () {
      Map<String, dynamic> withBudget(int budget) => convert({
            'model': 'm',
            'thinking': {'type': 'enabled', 'budget_tokens': budget},
            'messages': [
              {'role': 'user', 'content': 'x'},
            ],
          });
      expect(withBudget(2048)['reasoning']['effort'], 'low');
      expect(withBudget(32768)['reasoning']['effort'], 'high');
    });

    test('thinking.enabled 无 budget 时仅设 effort=medium 兜底', () {
      final result = convert({
        'model': 'm',
        'thinking': {'type': 'enabled'},
        'messages': [
          {'role': 'user', 'content': 'x'},
        ],
      });
      expect(result['reasoning'], {'effort': 'medium'});
    });

    test('未启用 thinking 时不含 reasoning 字段', () {
      final result = convert({
        'model': 'm',
        'messages': [
          {'role': 'user', 'content': 'x'},
        ],
      });
      expect(result.containsKey('reasoning'), isFalse);

      final disabled = convert({
        'model': 'm',
        'thinking': {'type': 'disabled'},
        'messages': [
          {'role': 'user', 'content': 'x'},
        ],
      });
      expect(disabled.containsKey('reasoning'), isFalse);
    });
  });
}
