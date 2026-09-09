import 'package:code_proxy/service/proxy_server/response/anthropic_sse_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnthropicSseReader 状态', () {
    test('完整流：识别 message_stop 并累积 usage', () {
      final reader = AnthropicSseReader();
      reader.add(
        'event: message_start\n'
        'data: {"type":"message_start","message":{"usage":'
        '{"input_tokens":100,"cache_read_input_tokens":20,'
        '"cache_creation_input_tokens":5}}}\n\n'
        'event: message_delta\n'
        'data: {"type":"message_delta","usage":{"output_tokens":50}}\n\n'
        'event: message_stop\n'
        'data: {"type":"message_stop"}\n\n',
      );
      reader.flush();

      expect(reader.sawCompletionSignal, isTrue);
      expect(reader.usage['input'], 100);
      expect(reader.usage['output'], 50);
      expect(reader.usage['cache_read'], 20);
      expect(reader.usage['cache_creation'], 5);
    });

    test('未开启伪装时 add 恒返回 null，可原样转发原始字节', () {
      final reader = AnthropicSseReader();
      expect(reader.add('data: {"type":"ping"}\n'), isNull);
      expect(reader.add('data: {"type":"message_stop"}\n\n'), isNull);
      expect(reader.flush(), isEmpty);
      expect(reader.sawCompletionSignal, isTrue);
    });

    test('message_stop 跨 chunk 边界分裂仍能识别', () {
      final reader = AnthropicSseReader();
      reader.add('event: message_st');
      reader.add('op\ndata: {"type":"mess');
      reader.add('age_stop"}\n\n');
      reader.flush();

      expect(reader.sawCompletionSignal, isTrue);
    });

    test('usage 跨 chunk 边界分裂仍能累积', () {
      final reader = AnthropicSseReader();
      reader.add('data: {"type":"message_delta","usage":{"outp');
      reader.add('ut_tokens":77}}\n');
      reader.flush();

      expect(reader.usage['output'], 77);
    });

    test('末行没有换行结尾时由 flush 收尾', () {
      final reader = AnthropicSseReader();
      reader.add('data: {"type":"message_stop"}');
      expect(reader.sawCompletionSignal, isFalse);

      reader.flush();
      expect(reader.sawCompletionSignal, isTrue);
    });

    test('缺少 message_stop 时不误报完成', () {
      final reader = AnthropicSseReader();
      reader.add(
        'event: content_block_delta\n'
        'data: {"type":"content_block_delta","delta":{"text":"hi"}}\n\n',
      );
      reader.flush();

      expect(reader.sawCompletionSignal, isFalse);
    });

    test('损坏的 JSON 行被跳过且不影响后续行', () {
      final reader = AnthropicSseReader();
      reader.add('data: {"broken\ndata: {"type":"message_stop"}\n');
      reader.flush();

      expect(reader.sawCompletionSignal, isTrue);
    });

    test('output_tokens 取最后一次出现的值', () {
      final reader = AnthropicSseReader();
      reader.add(
        'data: {"type":"message_delta","usage":{"output_tokens":10}}\n'
        'data: {"type":"message_delta","usage":{"output_tokens":99}}\n',
      );
      reader.flush();

      expect(reader.usage['output'], 99);
    });

    test('无 usage 的流返回全 null', () {
      final reader = AnthropicSseReader();
      reader.add('event: ping\ndata: {"type":"ping"}\n\n');
      reader.flush();

      expect(reader.usage, {
        'input': null,
        'output': null,
        'cache_creation': null,
        'cache_read': null,
      });
    });
  });

  group('AnthropicSseReader 首字信号', () {
    test(
      'message_start / content_block_start / ping 不触发，首个 content_block_delta 触发',
      () {
        final reader = AnthropicSseReader();
        reader.add(
          'event: message_start\n'
          'data: {"type":"message_start","message":{"usage":{"input_tokens":1}}}\n\n'
          'event: content_block_start\n'
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n'
          'event: ping\n'
          'data: {"type":"ping"}\n\n',
        );
        expect(reader.sawContentDelta, isFalse);

        // thinking 也是内容：扩展思考开启时它就是首个 token
        reader.add(
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"…"}}\n\n',
        );
        expect(reader.sawContentDelta, isTrue);
      },
    );

    test('跨 chunk 分裂的 content_block_delta 在行完整后才触发', () {
      final reader = AnthropicSseReader();
      reader.add('data: {"type":"content_block_del');
      expect(reader.sawContentDelta, isFalse);

      reader.add('ta","index":0,"delta":{"type":"text_delta","text":"hi"}}\n');
      expect(reader.sawContentDelta, isTrue);
    });
  });

  group('AnthropicSseReader 模型伪装', () {
    test('message_start 的 model 被替换，其余事件原样透传', () {
      const original =
          'event: message_start\n'
          'data: {"type":"message_start","message":{"id":"msg_1","type":"message",'
          '"role":"assistant","model":"deepseek-real-model",'
          '"usage":{"input_tokens":100},"content":[]}}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","delta":{"text":"hi"}}\n\n'
          'event: message_delta\n'
          'data: {"type":"message_delta","usage":{"output_tokens":50}}\n\n'
          'event: message_stop\n'
          'data: {"type":"message_stop"}\n\n';

      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      final rewritten = (reader.add(original) ?? '') + reader.flush();

      expect(
        rewritten,
        'event: message_start\n'
        'data: {"type":"message_start","message":{"id":"msg_1","type":"message",'
        '"role":"assistant","model":"claude-opus-5",'
        '"usage":{"input_tokens":100},"content":[]}}\n\n'
        'event: content_block_delta\n'
        'data: {"type":"content_block_delta","delta":{"text":"hi"}}\n\n'
        'event: message_delta\n'
        'data: {"type":"message_delta","usage":{"output_tokens":50}}\n\n'
        'event: message_stop\n'
        'data: {"type":"message_stop"}\n\n',
      );
      expect(reader.sawCompletionSignal, isTrue);
      expect(reader.usage['output'], 50);
    });

    test('跨 chunk 边界时行拼接后仍完成替换', () {
      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      // 第一次 add：事件名行已完整（以 \n 结尾）立即输出；
      // data 行没有换行结尾，保留在缓冲等待补全
      expect(
        reader.add('event: message_start\ndata: {"type":"message_start"'),
        'event: message_start\n',
      );
      // 第二次 add 补完 data 行其余部分
      final out = reader.add(
        ',"message":{"model":"deepseek-real-model"}}\n\n'
        'event: message_stop\n'
        'data: {"type":"message_stop"}\n\n',
      );
      reader.flush();

      expect(
        out,
        'data: {"type":"message_start","message":{"model":"claude-opus-5"}}\n\n'
        'event: message_stop\n'
        'data: {"type":"message_stop"}\n\n',
      );
    });

    test('跨 chunk 的 message_start 不会被转发两次', () {
      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      // 尾行不完整时必须扣住，不能原样放行原始字节
      expect(
        reader.add(
          'event: message_start\n'
          'data: {"type":"message_start","message":{"model":"deep',
        ),
        'event: message_start\n',
      );
      expect(
        reader.add('-model"}}\n\n'),
        'data: {"type":"message_start","message":{"model":"claude-opus-5"}}\n\n',
      );
    });

    test('未改写且无残留尾行时返回 null', () {
      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      expect(reader.add('event: ping\ndata: {"type":"ping"}\n\n'), isNull);
      reader.flush();
    });

    test('损坏的 data 行不抛异常且原样透传', () {
      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      final out = reader.add(
        'event: message_start\n'
        'data: {"type":"mess\n' // 损坏：缺少闭合，解析失败
        'data: {"type":"ping"}\n\n',
      );
      reader.flush();

      expect(out, isNull);
    });

    test('无 data: 前缀的行（event 名行）原样透传', () {
      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      final out = reader.add(
        'event: message_start\n'
        'data: {"type":"message_start","message":{"model":"deepseek"}}\n\n',
      );
      reader.flush();

      expect(
        out,
        'event: message_start\n'
        'data: {"type":"message_start","message":{"model":"claude-opus-5"}}\n\n',
      );
    });

    test('flush 处理末尾无换行的 message_start 残留行', () {
      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      // 事件名行已完整输出；无换行结尾的 data 行由 flush 收尾改写
      expect(
        reader.add(
          'event: message_start\n'
          'data: {"type":"message_start","message":{"model":"deepseek"}}',
        ),
        'event: message_start\n',
      );
      final flushed = reader.flush();

      expect(
        flushed,
        'data: {"type":"message_start","message":{"model":"claude-opus-5"}}',
      );
    });

    test('多事件流顺序与换行结构保持', () {
      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      final out = reader.add(
        'event: ping\n'
        'data: {"type":"ping"}\n\n'
        'event: message_start\n'
        'data: {"type":"message_start","message":{"model":"a"}}\n\n'
        'event: content_block_start\n'
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n',
      );
      reader.flush();

      expect(
        out,
        'event: ping\n'
        'data: {"type":"ping"}\n\n'
        'event: message_start\n'
        'data: {"type":"message_start","message":{"model":"claude-opus-5"}}\n\n'
        'event: content_block_start\n'
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n',
      );
    });

    test('message_start 缺失 message.model 时原样透传', () {
      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      final out = reader.add(
        'data: {"type":"message_start","message":{"id":"msg_1"}}\n\n',
      );
      reader.flush();

      expect(out, isNull);
    });

    test('保留 data: 后无空格的写法结构', () {
      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      final out = reader.add(
        'data:{"type":"message_start","message":{"model":"deepseek"}}\n\n',
      );
      reader.flush();

      expect(
        out,
        'data:{"type":"message_start","message":{"model":"claude-opus-5"}}\n\n',
      );
    });

    test('分块边界落在 data 行中间时不得丢字节', () {
      const stream =
          'event: message_start\n'
          'data: {"type":"message_start","message":{"id":"msg_1","model":"deepseek-real-model","usage":{"input_tokens":1}}}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello 世界"}}\n\n'
          'event: message_stop\n'
          'data: {"type":"message_stop"}\n\n';

      String replay(List<String> chunks) {
        final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
        final out = StringBuffer();
        for (final chunk in chunks) {
          out.write(reader.add(chunk) ?? chunk);
        }
        out.write(reader.flush());
        return out.toString();
      }

      final baseline = replay([stream]);
      // 切点落在 content_block_delta 的 data 行中间
      final split = stream.indexOf('"text":"hello') + 8;
      final got = replay([stream.substring(0, split), stream.substring(split)]);

      expect(got, baseline);
      expect(got, contains('"text":"hello 世界"'));
    });

    test('任意切分点的转发结果都与整段喂入一致', () {
      const stream =
          'event: message_start\n'
          'data: {"type":"message_start","message":{"id":"msg_1","model":"deepseek-real-model","usage":{"input_tokens":1}}}\n\n'
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello 世界"}}\n\n'
          'event: message_stop\n'
          'data: {"type":"message_stop"}\n\n';

      String replay(List<String> chunks) {
        final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
        final out = StringBuffer();
        for (final chunk in chunks) {
          out.write(reader.add(chunk) ?? chunk);
        }
        out.write(reader.flush());
        return out.toString();
      }

      final baseline = replay([stream]);
      for (var split = 1; split < stream.length; split++) {
        final got = replay([
          stream.substring(0, split),
          stream.substring(split),
        ]);
        expect(got, baseline, reason: '切分点 $split 的输出与整段喂入不一致');
      }
    });

    test('CRLF 行尾：改写命中且行尾 CR 保留', () {
      final reader = AnthropicSseReader(spoofedModel: 'claude-opus-5');
      final out = reader.add(
        'event: message_start\r\n'
        'data: {"type":"message_start","message":{"model":"deepseek"}}\r\n\r\n',
      );
      reader.flush();

      expect(
        out,
        'event: message_start\r\n'
        'data: {"type":"message_start","message":{"model":"claude-opus-5"}}\r\n\r\n',
      );
    });
  });
}
