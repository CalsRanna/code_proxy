import 'package:code_proxy/service/proxy_server/converter/openai_responses_response_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = OpenAiResponsesResponseConverter();

  test('标准响应：reasoning + message + function_call 按序转换', () {
    final out = converter.convertResponse({
      'id': 'resp_123',
      'object': 'response',
      'model': 'gpt-5',
      'status': 'completed',
      'output': [
        {
          'type': 'reasoning',
          'id': 'rs_1',
          'summary': [
            {'type': 'summary_text', 'text': 'thinking hard'},
          ],
        },
        {
          'type': 'message',
          'id': 'msg_1',
          'role': 'assistant',
          'status': 'completed',
          'content': [
            {'type': 'output_text', 'text': 'Hello ', 'annotations': []},
            {'type': 'output_text', 'text': 'world', 'annotations': []},
          ],
        },
      ],
      'usage': {
        'input_tokens': 100,
        'input_tokens_details': {'cached_tokens': 60},
        'output_tokens': 20,
        'output_tokens_details': {'reasoning_tokens': 5},
        'total_tokens': 120,
      },
    }, originalModel: 'claude-sonnet-4-5');

    expect(out['id'], 'resp_123');
    expect(out['type'], 'message');
    // model 回填客户端原始模型名
    expect(out['model'], 'claude-sonnet-4-5');
    expect(out['stop_reason'], 'end_turn');
    expect(out['content'], [
      {'type': 'thinking', 'thinking': 'thinking hard'},
      {'type': 'text', 'text': 'Hello world'},
    ]);
    expect(out['usage'], {
      'input_tokens': 100,
      'output_tokens': 20,
      'cache_read_input_tokens': 60,
      'cache_creation_input_tokens': 0,
    });
  });

  test('function_call → tool_use block，stop_reason=tool_use', () {
    final out = converter.convertResponse({
      'id': 'resp_1',
      'model': 'gpt-5',
      'status': 'completed',
      'output': [
        {
          'type': 'function_call',
          'id': 'fc_1',
          'call_id': 'call_abc',
          'name': 'get_weather',
          'arguments': '{"city":"Tokyo"}',
        },
      ],
      'usage': {'input_tokens': 10, 'output_tokens': 5},
    }, originalModel: null);

    expect(out['model'], 'gpt-5');
    expect(out['stop_reason'], 'tool_use');
    expect(out['content'], [
      {
        'type': 'tool_use',
        'id': 'call_abc',
        'name': 'get_weather',
        'input': {'city': 'Tokyo'},
      },
    ]);
  });

  test('arguments 非法 JSON 时兜底 raw_arguments', () {
    final out = converter.convertResponse({
      'id': 'resp_1',
      'model': 'gpt-5',
      'status': 'completed',
      'output': [
        {
          'type': 'function_call',
          'call_id': 'call_x',
          'name': 'fn',
          'arguments': '{broken json',
        },
      ],
      'usage': {},
    }, originalModel: null);

    expect((out['content'] as List)[0]['input'], {
      'raw_arguments': '{broken json',
    });
  });

  test('incomplete(max_output_tokens) → stop_reason=max_tokens', () {
    final out = converter.convertResponse({
      'id': 'resp_1',
      'model': 'gpt-5',
      'status': 'incomplete',
      'incomplete_details': {'reason': 'max_output_tokens'},
      'output': [
        {
          'type': 'message',
          'content': [
            {'type': 'output_text', 'text': 'partial'},
          ],
        },
      ],
      'usage': {'input_tokens': 10, 'output_tokens': 4096},
    }, originalModel: null);

    expect(out['stop_reason'], 'max_tokens');
    expect((out['content'] as List)[0]['text'], 'partial');
  });

  test('空 output 返回空文本消息而非抛错', () {
    final out = converter.convertResponse({
      'id': 'resp_empty',
      'model': 'gpt-5',
      'status': 'completed',
      'output': [],
      'usage': {'input_tokens': 1, 'output_tokens': 0},
    }, originalModel: null);

    expect(out['content'], [
      {'type': 'text', 'text': ''},
    ]);
    expect(out['stop_reason'], 'end_turn');
  });

  test('refusal part 转为 text', () {
    final out = converter.convertResponse({
      'id': 'resp_1',
      'model': 'gpt-5',
      'status': 'completed',
      'output': [
        {
          'type': 'message',
          'content': [
            {'type': 'refusal', 'refusal': 'cannot do that', 'text': 'cannot do that'},
          ],
        },
      ],
      'usage': {},
    }, originalModel: null);

    expect(out['content'], [
      {'type': 'text', 'text': 'cannot do that'},
    ]);
  });

  test('web_search_call 等内置工具项被剥离', () {
    final out = converter.convertResponse({
      'id': 'resp_1',
      'model': 'gpt-5',
      'status': 'completed',
      'output': [
        {'type': 'web_search_call', 'id': 'ws_1'},
        {
          'type': 'message',
          'content': [
            {'type': 'output_text', 'text': 'answer'},
          ],
        },
      ],
      'usage': {},
    }, originalModel: null);

    expect(out['content'], [
      {'type': 'text', 'text': 'answer'},
    ]);
  });

  test('无 usage 时 token 数为 0', () {
    final out = converter.convertResponse({
      'id': 'resp_1',
      'model': 'gpt-5',
      'status': 'completed',
      'output': [
        {
          'type': 'message',
          'content': [
            {'type': 'output_text', 'text': 'hi'},
          ],
        },
      ],
    }, originalModel: null);

    expect(out['usage']['input_tokens'], 0);
    expect(out['usage']['output_tokens'], 0);
    expect(out['usage'].containsKey('cache_read_input_tokens'), isFalse);
  });
}
