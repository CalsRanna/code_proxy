import 'dart:convert';

import 'package:code_proxy/service/proxy_server/converter/openai_responses_stream_converter.dart';
import 'package:flutter_test/flutter_test.dart';

/// 解析 SSE 输出为 (event, data) 记录列表
List<(String, Map<String, dynamic>)> parseEvents(List<int> bytes) {
  final text = utf8.decode(bytes);
  final events = <(String, Map<String, dynamic>)>[];
  for (final block in text.split('\n\n')) {
    if (block.trim().isEmpty) continue;
    String? event;
    Map<String, dynamic>? data;
    for (final line in block.split('\n')) {
      if (line.startsWith('event: ')) event = line.substring(7);
      if (line.startsWith('data: ')) {
        data = jsonDecode(line.substring(6)) as Map<String, dynamic>;
      }
    }
    events.add((event!, data!));
  }
  return events;
}

void main() {
  List<(String, Map<String, dynamic>)> runStream(
    List<List<int>> chunks, {
    bool callHandleDone = true,
  }) {
    final converter =
        OpenAiResponsesSseStreamConverter(originalModel: 'claude-sonnet-4-5');
    final out = <int>[...converter.initialEvents()];
    for (final chunk in chunks) {
      out.addAll(converter.handleData(chunk));
    }
    if (callHandleDone) out.addAll(converter.handleDone());
    return parseEvents(out);
  }

  /// Responses API 的 SSE 事件同时带 event: 行与 data.type，
  /// 转换器只依赖 data.type
  List<int> sse(List<Map<String, dynamic>> events) {
    return utf8.encode(
      events
          .map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n')
          .join(),
    );
  }

  test('头部事件：message_start + ping 立即产出', () {
    final converter =
        OpenAiResponsesSseStreamConverter(originalModel: 'claude-sonnet-4-5');
    final events = parseEvents(converter.initialEvents());

    expect(events[0].$1, 'message_start');
    expect(events[0].$2['message']['model'], 'claude-sonnet-4-5');
    expect(events[1].$1, 'ping');
  });

  test('纯文本流：output_text.delta → 完整 Anthropic 事件序列', () {
    final events = runStream([
      sse([
        {'type': 'response.created', 'response': {'id': 'resp_1'}},
        {'type': 'response.in_progress'},
        {
          'type': 'response.output_item.added',
          'output_index': 0,
          'item': {
            'type': 'message',
            'role': 'assistant',
            'status': 'in_progress',
            'content': [],
          },
        },
        {
          'type': 'response.output_text.delta',
          'item_id': 'msg_1',
          'output_index': 0,
          'content_index': 0,
          'delta': 'Hello',
        },
        {
          'type': 'response.output_text.delta',
          'item_id': 'msg_1',
          'output_index': 0,
          'content_index': 0,
          'delta': ' world',
        },
      ]),
    ]);

    expect(events.map((e) => e.$1), [
      'message_start',
      'ping',
      'content_block_start',
      'content_block_delta',
      'content_block_delta',
      'content_block_stop',
      'message_delta',
      'message_stop',
    ]);
    expect(events[3].$2['delta'], {'type': 'text_delta', 'text': 'Hello'});
    expect(events[4].$2['delta'], {'type': 'text_delta', 'text': ' world'});
    // response.created 等生命周期事件不回传给客户端
  });

  test('reasoning summary delta → thinking block，先于 text 关闭', () {
    final events = runStream([
      sse([
        {
          'type': 'response.reasoning_summary_text.delta',
          'delta': 'pondering...',
        },
        {'type': 'response.reasoning_summary_text.delta', 'delta': ' done'},
        {'type': 'response.output_text.delta', 'delta': 'Answer'},
      ]),
    ]);

    expect(events.map((e) => e.$1), [
      'message_start',
      'ping',
      'content_block_start', // thinking @0
      'content_block_delta',
      'content_block_delta',
      'content_block_stop', // thinking
      'content_block_start', // text @1
      'content_block_delta',
      'content_block_stop',
      'message_delta',
      'message_stop',
    ]);
    expect(events[2].$2['content_block']['type'], 'thinking');
    expect(events[3].$2['delta'],
        {'type': 'thinking_delta', 'thinking': 'pondering...'});
    expect(events[5].$2['index'], 0);
    expect(events[6].$2['index'], 1);
    expect(events[6].$2['content_block']['type'], 'text');
  });

  group('工具调用流', () {
    test('added → arguments.delta → done → completed 全序列', () {
      final events = runStream([
        sse([
          {
            'type': 'response.output_item.added',
            'output_index': 0,
            'item': {
              'type': 'function_call',
              'id': 'fc_1',
              'call_id': 'call_abc',
              'name': 'get_weather',
              'arguments': '',
              'status': 'in_progress',
            },
          },
          {
            'type': 'response.function_call_arguments.delta',
            'item_id': 'fc_1',
            'output_index': 0,
            'delta': '{"city":',
          },
          {
            'type': 'response.function_call_arguments.delta',
            'item_id': 'fc_1',
            'output_index': 0,
            'delta': '"Tokyo"}',
          },
          {
            'type': 'response.output_item.done',
            'output_index': 0,
            'item': {
              'type': 'function_call',
              'id': 'fc_1',
              'call_id': 'call_abc',
              'name': 'get_weather',
              'arguments': '{"city":"Tokyo"}',
              'status': 'completed',
            },
          },
          {
            'type': 'response.completed',
            'response': {
              'id': 'resp_1',
              'status': 'completed',
              'usage': {
                'input_tokens': 50,
                'input_tokens_details': {'cached_tokens': 30},
                'output_tokens': 8,
              },
            },
          },
        ]),
      ]);

      expect(events.map((e) => e.$1), [
        'message_start',
        'ping',
        'content_block_start', // tool_use @0
        'content_block_delta',
        'content_block_delta',
        'content_block_stop',
        'message_delta',
        'message_stop',
      ]);
      expect(events[2].$2['content_block'], {
        'type': 'tool_use',
        'id': 'call_abc',
        'name': 'get_weather',
        'input': <String, dynamic>{},
      });
      expect(events[3].$2['delta'],
          {'type': 'input_json_delta', 'partial_json': '{"city":'});
      expect(events[4].$2['delta'],
          {'type': 'input_json_delta', 'partial_json': '"Tokyo"}'});
      // completed 携带 usage，handleDone 不重复收尾
      expect(events[6].$2['usage']['output_tokens'], 8);
      expect(events[6].$2['usage']['cache_read_input_tokens'], 30);
      expect(events[6].$2['delta']['stop_reason'], 'end_turn');
    });

    test('completed 后 handleDone 不重复输出收尾事件', () {
      final converter =
          OpenAiResponsesSseStreamConverter(originalModel: 'm');
      converter.initialEvents();
      converter.handleData(sse([
        {'type': 'response.output_text.delta', 'delta': 'hi'},
        {
          'type': 'response.completed',
          'response': {'status': 'completed', 'usage': {}},
        },
      ]));
      final tail = converter.handleDone();
      expect(tail, isEmpty);
    });

    test('跳过 added 直接 done 时补开工具块', () {
      final events = runStream([
        sse([
          {
            'type': 'response.output_item.done',
            'output_index': 0,
            'item': {
              'type': 'function_call',
              'id': 'fc_late',
              'call_id': 'call_late',
              'name': 'fn',
              'arguments': '{}',
              'status': 'completed',
            },
          },
        ]),
      ]);

      final starts = events.where((e) => e.$1 == 'content_block_start');
      expect(starts, hasLength(1));
      expect(starts.first.$2['content_block']['name'], 'fn');
      expect(
        events.any((e) => e.$1 == 'content_block_stop'),
        isTrue,
      );
    });
  });

  test('incomplete → stop_reason=max_tokens', () {
    final events = runStream([
      sse([
        {'type': 'response.output_text.delta', 'delta': 'partial'},
        {
          'type': 'response.incomplete',
          'response': {
            'status': 'incomplete',
            'incomplete_details': {'reason': 'max_output_tokens'},
            'usage': {'input_tokens': 10, 'output_tokens': 100},
          },
        },
      ]),
    ]);

    final messageDelta = events.lastWhere((e) => e.$1 == 'message_delta');
    expect(messageDelta.$2['delta']['stop_reason'], 'max_tokens');
  });

  test('failed → error 事件终止，无 message_stop', () {
    final events = runStream([
      sse([
        {'type': 'response.output_text.delta', 'delta': 'par'},
        {
          'type': 'response.failed',
          'response': {
            'error': {'code': 'server_error', 'message': 'boom'},
          },
        },
      ], ),
    ]);

    expect(events.last.$1, 'error');
    expect(events.last.$2['error']['message'], contains('boom'));
    expect(events.any((e) => e.$1 == 'message_stop'), isFalse);
  });

  test('handleError（传输层异常）→ error 事件', () {
    final converter = OpenAiResponsesSseStreamConverter(originalModel: 'm');
    final out = <int>[...converter.initialEvents()];
    out.addAll(converter.handleData(sse([
      {'type': 'response.output_text.delta', 'delta': 'partial'},
    ])));
    out.addAll(converter.handleError(Exception('conn reset')));
    final events = parseEvents(out);

    expect(events.last.$1, 'error');
    expect(events.last.$2['error']['message'], contains('conn reset'));
  });

  test('usage 在 response.completed 中捕获（含 cached_tokens）', () {
    final converter = OpenAiResponsesSseStreamConverter(originalModel: 'm');
    converter.initialEvents();
    converter.handleData(sse([
      {'type': 'response.output_text.delta', 'delta': 'hi'},
      {
        'type': 'response.completed',
        'response': {
          'status': 'completed',
          'usage': {
            'input_tokens': 12,
            'input_tokens_details': {'cached_tokens': 7},
            'output_tokens': 3,
          },
        },
      },
    ]));

    expect(converter.finalUsage, {
      'input': 12,
      'output': 3,
      'cache_creation': 0,
      'cache_read': 7,
    });
  });

  test('多字节 UTF-8 跨 chunk 截断正确处理', () {
    final full = sse([
      {'type': 'response.output_text.delta', 'delta': '你好世界'},
      {'type': 'response.completed', 'response': {'status': 'completed'}},
    ]);
    // 在中文字符中间切开
    final cut = 3 + 5; // "event..." 头之后、首字符字节中间
    final events = runStream([full.sublist(0, cut), full.sublist(cut)]);

    final deltas = events
        .where((e) => e.$1 == 'content_block_delta')
        .map((e) => e.$2['delta']['text'])
        .join();
    expect(deltas, '你好世界');
  });

  test('data: [DONE] 行被容错忽略', () {
    final bytes = utf8.encode(
      '${utf8.decode(sse([
          {'type': 'response.output_text.delta', 'delta': 'ok'},
        ]))}data: [DONE]\n\n',
    );
    final events = runStream([bytes]);

    expect(
      events.any((e) => e.$1 == 'content_block_delta'),
      isTrue,
    );
    // 正常收尾
    expect(events.last.$1, 'message_stop');
  });

  test('空流：handleDone 补空 text block 收尾', () {
    final events = runStream(const <List<int>>[]);

    expect(events.map((e) => e.$1), [
      'message_start',
      'ping',
      'content_block_start',
      'content_block_stop',
      'message_delta',
      'message_stop',
    ]);
    expect(events[2].$2['content_block'], {'type': 'text', 'text': ''});
  });

  group('完成信号检测（isComplete）', () {
    test('仅 delta 事件时 isComplete 为 false（上游静默截断）', () {
      final converter = OpenAiResponsesSseStreamConverter(originalModel: 'm');
      converter.initialEvents();
      converter.handleData(sse([
        {'type': 'response.output_text.delta', 'delta': 'partial'},
      ]));
      expect(converter.isComplete, isFalse);
    });

    test('response.completed 后 isComplete 为 true', () {
      final converter = OpenAiResponsesSseStreamConverter(originalModel: 'm');
      converter.initialEvents();
      converter.handleData(sse([
        {'type': 'response.output_text.delta', 'delta': 'hi'},
        {
          'type': 'response.completed',
          'response': {'status': 'completed', 'usage': {}},
        },
      ]));
      expect(converter.isComplete, isTrue);
    });

    test('response.incomplete 后 isComplete 为 true', () {
      final converter = OpenAiResponsesSseStreamConverter(originalModel: 'm');
      converter.initialEvents();
      converter.handleData(sse([
        {
          'type': 'response.incomplete',
          'response': {'status': 'incomplete', 'usage': {}},
        },
      ]));
      expect(converter.isComplete, isTrue);
    });

    test('response.failed 后 isComplete 为 true（上游已明确终止）', () {
      final converter = OpenAiResponsesSseStreamConverter(originalModel: 'm');
      converter.initialEvents();
      converter.handleData(sse([
        {
          'type': 'response.failed',
          'response': {'error': {'message': 'boom'}},
        },
      ]));
      expect(converter.isComplete, isTrue);
    });

    test('流结束后从未收到完成事件时 isComplete 为 false', () {
      final converter = OpenAiResponsesSseStreamConverter(originalModel: 'm');
      converter.initialEvents();
      converter.handleData(sse([
        {'type': 'response.output_text.delta', 'delta': 'partial'},
      ]));
      converter.handleDone();
      expect(converter.isComplete, isFalse);
    });
  });
}
