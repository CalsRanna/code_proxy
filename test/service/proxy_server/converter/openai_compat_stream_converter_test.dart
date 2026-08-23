import 'dart:convert';

import 'package:code_proxy/service/proxy_server/converter/openai_compat_stream_converter.dart';
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
    final converter = OpenAiSseStreamConverter(originalModel: 'claude-sonnet-4-5');
    final out = <int>[...converter.initialEvents()];
    for (final chunk in chunks) {
      out.addAll(converter.handleData(chunk));
    }
    if (callHandleDone) out.addAll(converter.handleDone());
    return parseEvents(out);
  }

  List<int> sse(List<Map<String, dynamic>> dataLines) {
    return utf8.encode(
      dataLines.map((d) => 'data: ${jsonEncode(d)}\n\n').join(),
    );
  }

  test('头部事件：message_start + ping 立即产出', () {
    final converter = OpenAiSseStreamConverter(originalModel: 'claude-sonnet-4-5');
    final events = parseEvents(converter.initialEvents());

    expect(events[0].$1, 'message_start');
    expect(events[0].$2['message']['role'], 'assistant');
    // model 回填客户端原始模型名
    expect(events[0].$2['message']['model'], 'claude-sonnet-4-5');
    expect(events[0].$2['message']['content'], isEmpty);
    expect(events[1].$1, 'ping');
  });

  group('纯文本流', () {
    test('标准序列：start → delta* → stop → message_delta → message_stop', () {
      final events = runStream([
        sse([
          {
            'choices': [
              {
                'index': 0,
                'delta': {'role': 'assistant'},
                'finish_reason': null,
              },
            ],
          },
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'Hello'},
                'finish_reason': null,
              },
            ],
          },
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': ' world'},
                'finish_reason': null,
              },
            ],
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

      // role-only chunk 不产生任何内容事件，text block 惰性开启在首个文本处
      expect(events[2].$2['index'], 0);
      expect(events[2].$2['content_block'], {'type': 'text', 'text': ''});
      expect(events[3].$2['delta'], {'type': 'text_delta', 'text': 'Hello'});
      expect(events[4].$2['delta'], {'type': 'text_delta', 'text': ' world'});
      expect(events[5].$2['index'], 0);
      expect(events[6].$2['delta'], {'stop_reason': 'end_turn', 'stop_sequence': null});
    });

    test('usage 在末尾独立 chunk 时正确捕获', () {
      final converter = OpenAiSseStreamConverter(originalModel: 'm');
      converter.initialEvents();
      converter.handleData(
        sse([
          {
            'choices': [
              {
                'delta': {'content': 'hi'},
              },
            ],
          },
        ]),
      );
      converter.handleData(
        sse([
          {
            'choices': [],
            'usage': {
              'prompt_tokens': 12,
              'completion_tokens': 34,
              'prompt_tokens_details': {'cached_tokens': 8},
            },
          },
        ]),
      );
      converter.handleDone();

      final usage = converter.finalUsage;
      expect(usage['input'], 12);
      expect(usage['output'], 34);
      expect(usage['cache_read'], 8);
    });

    test('finish_reason=length 映射为 max_tokens', () {
      final events = runStream([
        sse([
          {
            'choices': [
              {
                'delta': {'content': 'abc'},
                'finish_reason': null,
              },
              {
                'delta': {},
                'finish_reason': 'length',
              },
            ],
          },
        ]),
      ]);
      final messageDelta =
          events.firstWhere((e) => e.$1 == 'message_delta');
      expect(messageDelta.$2['delta']['stop_reason'], 'max_tokens');
    });

    test('无 [DONE] 标记时 handleDone 正常收尾', () {
      final events = runStream([sse([])], callHandleDone: true);
      expect(events.last.$1, 'message_stop');
    });
  });

  group('完成信号检测（isComplete）', () {
    test('仅内容分片时 isComplete 为 false（上游静默截断）', () {
      final converter =
          OpenAiSseStreamConverter(originalModel: 'claude-sonnet-4-5');
      converter.initialEvents();
      converter.handleData(
        sse([
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'hello'},
                'finish_reason': null,
              },
            ],
          },
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': ' world'},
                'finish_reason': null,
              },
            ],
          },
        ]),
      );
      expect(converter.isComplete, isFalse);
    });

    test('收到 [DONE] 时 isComplete 为 true（即使没有 finish_reason）', () {
      final converter =
          OpenAiSseStreamConverter(originalModel: 'claude-sonnet-4-5');
      converter.initialEvents();
      converter.handleData(
        sse([
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'hello'},
                'finish_reason': null,
              },
            ],
          },
        ]),
      );
      converter.handleData(utf8.encode('data: [DONE]\n\n'));
      expect(converter.isComplete, isTrue);
    });

    test('收到 finish_reason 但没有 [DONE] 时 isComplete 为 true', () {
      final converter =
          OpenAiSseStreamConverter(originalModel: 'claude-sonnet-4-5');
      converter.initialEvents();
      converter.handleData(
        sse([
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'hello'},
                'finish_reason': null,
              },
              {
                'index': 0,
                'delta': {},
                'finish_reason': 'stop',
              },
            ],
          },
        ]),
      );
      expect(converter.isComplete, isTrue);
    });

    test('空流直接结束（无任何信号）时 isComplete 为 false', () {
      final converter =
          OpenAiSseStreamConverter(originalModel: 'claude-sonnet-4-5');
      converter.initialEvents();
      converter.handleDone();
      expect(converter.isComplete, isFalse);
    });
  });

  group('纯工具调用流', () {
    List<Map<String, dynamic>> toolCallChunks() => [
          {
            'choices': [
              {
                'delta': {
                  'role': 'assistant',
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_a',
                      'type': 'function',
                      'function': {'name': 'read_file', 'arguments': ''},
                    },
                  ],
                },
                'finish_reason': null,
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': '{"path'},
                    },
                  ],
                },
                'finish_reason': null,
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': '":"/a.txt"}'},
                    },
                  ],
                },
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {},
                'finish_reason': 'tool_calls',
              },
            ],
          },
        ];

    test('不产生 text block，partial_json 分片直转', () {
      final events = runStream([sse(toolCallChunks())]);
      final types = events.map((e) => e.$1).toList();

      expect(types.contains('content_block_start'), isTrue);
      // 不应有任何空 text block
      for (final (_, data) in events.where((e) => e.$1 == 'content_block_start')) {
        expect(data['content_block']['type'], 'tool_use');
      }
      // index 连续且从 0 开始
      expect(events.firstWhere((e) => e.$1 == 'content_block_start').$2['index'], 0);

      final deltas = events
          .where((e) => e.$1 == 'content_block_delta')
          .map((e) => e.$2['delta'])
          .toList();
      expect(deltas, hasLength(2));
      expect(deltas[0]['type'], 'input_json_delta');
      expect(deltas[0]['partial_json'], '{"path');
      expect(deltas[1]['partial_json'], '":"/a.txt"}');

      final stop = events
          .where((e) => e.$1 == 'content_block_stop')
          .map((e) => e.$2['index'])
          .toList();
      expect(stop, [0]);

      final messageDelta = events.firstWhere((e) => e.$1 == 'message_delta');
      expect(messageDelta.$2['delta']['stop_reason'], 'tool_use');
    });
  });

  group('文本 + 双工具交错流', () {
    test('text 先开先关，两个工具块 index 连续递增', () {
      final chunks = sse([
        {
          'choices': [
            {
              'delta': {'content': 'Let me check both.'},
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_1',
                    'function': {'name': 'f1', 'arguments': '{"x":'},
                  },
                ],
              },
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '1}'},
                  },
                  {
                    'index': 1,
                    'id': 'call_2',
                    'function': {'name': 'f2', 'arguments': '{"y":2}'},
                  },
                ],
              },
            },
          ],
        },
        {
          'choices': [
            {
              'delta': {},
              'finish_reason': 'tool_calls',
            },
          ],
        },
      ]);

      final events = runStream([chunks]);
      final starts = events
          .where((e) => e.$1 == 'content_block_start')
          .map((e) => (e.$2['index'], e.$2['content_block']))
          .toList();

      expect(starts, hasLength(3));
      // text block index=0
      expect(starts[0].$1, 0);
      expect(starts[0].$2['type'], 'text');
      // 工具块依次为 index=1, 2
      expect(starts[1].$1, 1);
      expect(starts[1].$2['name'], 'f1');
      expect(starts[2].$1, 2);
      expect(starts[2].$2['id'], 'call_2');

      // 所有 content_block_stop 的顺序：text(0) → f1(1) → f2(2)
      final stops = events
          .where((e) => e.$1 == 'content_block_stop')
          .map((e) => e.$2['index'] as int)
          .toList();
      expect(stops, [0, 1, 2]);
    });
  });

  group('思考内容流（reasoning_content）', () {
    test('reasoning → thinking block，随后 text 触发块切换', () {
      final events = runStream([
        sse([
          {
            'choices': [
              {
                'delta': {'role': 'assistant'},
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {'reasoning_content': 'Think '},
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {'reasoning_content': 'hard.'},
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {'content': 'Answer.'},
              },
            ],
          },
        ]),
      ]);

      expect(events.map((e) => e.$1), [
        'message_start',
        'ping',
        // thinking block 先开启
        'content_block_start',
        'content_block_delta',
        'content_block_delta',
        'content_block_stop',
        // 首个 text delta 时关闭 thinking、开启 text
        'content_block_start',
        'content_block_delta',
        'content_block_stop',
        'message_delta',
        'message_stop',
      ]);

      final starts =
          events.where((e) => e.$1 == 'content_block_start').toList();
      expect(starts[0].$2['index'], 0);
      expect(starts[0].$2['content_block']['type'], 'thinking');
      expect(starts[1].$2['index'], 1);
      expect(starts[1].$2['content_block']['type'], 'text');

      final deltas = events
          .where((e) => e.$1 == 'content_block_delta')
          .map((e) => e.$2['delta'])
          .toList();
      expect(deltas[0], {'type': 'thinking_delta', 'thinking': 'Think '});
      expect(deltas[1], {'type': 'thinking_delta', 'thinking': 'hard.'});
      expect(deltas[2], {'type': 'text_delta', 'text': 'Answer.'});

      // 关闭顺序：thinking(0) → text(1)
      final stops = events
          .where((e) => e.$1 == 'content_block_stop')
          .map((e) => e.$2['index'])
          .toList();
      expect(stops, [0, 1]);
    });

    test('OpenRouter 的 reasoning 字段名同样识别', () {
      final events = runStream([
        sse([
          {
            'choices': [
              {
                'delta': {'reasoning': 'via openrouter'},
              },
            ],
          },
        ]),
      ]);
      final delta =
          events.firstWhere((e) => e.$1 == 'content_block_delta').$2;
      expect(delta['delta']['type'], 'thinking_delta');
      expect(delta['delta']['thinking'], 'via openrouter');
    });

    test('纯思考流收尾后仍为完整合法序列', () {
      final events = runStream([
        sse([
          {
            'choices': [
              {
                'delta': {'reasoning_content': 'only thinking'},
              },
            ],
          },
        ]),
      ]);
      final types = events.map((e) => e.$1).toList();
      expect(types, [
        'message_start',
        'ping',
        'content_block_start',
        'content_block_delta',
        'content_block_stop',
        'message_delta',
        'message_stop',
      ]);
      // 不应补空 text block
      expect(types, isNot(contains('text')));
      final start = events.firstWhere((e) => e.$1 == 'content_block_start');
      expect(start.$2['content_block']['type'], 'thinking');
    });
  });

  group('边界情况', () {
    test('SSE 行跨 chunk 截断（TCP 分片）', () {
      final fullLine = utf8.encode(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': 'split line'},
            },
          ],
        })}\n\n',
      );
      final mid = fullLine.length ~/ 2;

      final events = runStream([
        fullLine.sublist(0, mid),
        fullLine.sublist(mid),
      ]);
      final textDelta = events.firstWhere((e) => e.$1 == 'content_block_delta');
      expect(textDelta.$2['delta']['text'], 'split line');
    });

    test('多字节 UTF-8 字符跨 chunk 截断', () {
      final payload = jsonEncode({
        'choices': [
          {
            'delta': {'content': '你好世界'},
          },
        ],
      });
      final bytes = utf8.encode('data: $payload\n\n');
      // 在多字节字符中间切开
      var cut = -1;
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] > 0x7F) {
          cut = i + 1; // 切在第一个非 ASCII 字节的中间
          break;
        }
      }

      final events = runStream([bytes.sublist(0, cut), bytes.sublist(cut)]);
      final textDelta = events.firstWhere((e) => e.$1 == 'content_block_delta');
      expect(textDelta.$2['delta']['text'], '你好世界');
    });

    test('CRLF 行尾兼容', () {
      final payload = jsonEncode({
        'choices': [
          {
            'delta': {'content': 'crlf'},
          },
        ],
      });
      final bytes = utf8.encode('data: $payload\r\n\r\n');
      final events = runStream([bytes]);
      final textDelta = events.firstWhere((e) => e.$1 == 'content_block_delta');
      expect(textDelta.$2['delta']['text'], 'crlf');
    });

    test('坏 JSON chunk 被跳过不中断流', () {
      final good = jsonEncode({
        'choices': [
          {
            'delta': {'content': 'ok'},
          },
        ],
      });
      final bytes = utf8.encode('data: {broken json\ndata: $good\n\n');
      final events = runStream([bytes]);
      final deltas = events.where((e) => e.$1 == 'content_block_delta').toList();
      expect(deltas, hasLength(1));
      expect(deltas[0].$2['delta']['text'], 'ok');
    });

    test('keep-alive 注释行与空行被忽略', () {
      final payload = jsonEncode({
        'choices': [
          {
            'delta': {'content': 'x'},
          },
        ],
      });
      final bytes = utf8.encode(': keep-alive\n\ndata: $payload\n\n');
      final events = runStream([bytes]);
      expect(events.where((e) => e.$1 == 'content_block_delta'), hasLength(1));
    });

    test('[DONE] 之后的数据不再处理', () {
      final afterDone = jsonEncode({
        'choices': [
          {
            'delta': {'content': 'late'},
          },
        ],
      });
      final beforeDone = jsonEncode({
        'choices': [
          {
            'delta': {'content': 'early'},
          },
        ],
      });
      final bytes =
          utf8.encode('data: $beforeDone\n\ndata: [DONE]\n\ndata: $afterDone\n\n');
      final events = runStream([bytes]);
      final texts = events
          .where((e) => e.$1 == 'content_block_delta')
          .map((e) => e.$2['delta']['text'])
          .toList();
      expect(texts, ['early']);
    });

    test('上游无数据直接结束仍输出完整合法序列', () {
      final events = runStream([const []]);
      final types = events.map((e) => e.$1).toList();
      expect(types, [
        'message_start',
        'ping',
        'content_block_start',
        'content_block_stop',
        'message_delta',
        'message_stop',
      ]);
    });

    test('handleError 输出 error 事件', () {
      final converter = OpenAiSseStreamConverter(originalModel: 'm');
      converter.initialEvents();
      final errorBytes = converter.handleError(Exception('boom'));
      final events = parseEvents(errorBytes);
      expect(events.single.$1, 'error');
      expect(events.single.$2['error']['type'], 'api_error');
      expect(converter.finalUsage['output'], isNull);
    });

    test('handleDone 重复调用幂等', () {
      final converter = OpenAiSseStreamConverter(originalModel: 'm');
      converter.initialEvents();
      final first = converter.handleDone();
      final second = converter.handleDone();
      expect(second, isEmpty);
      expect(parseEvents(first).last.$1, 'message_stop');
    });
  });
}
