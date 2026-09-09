import 'package:code_proxy/service/proxy_server/response/anthropic_sse_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnthropicSseScanner', () {
    test('完整流：识别 message_stop 并累积 usage', () {
      final scanner = AnthropicSseScanner();
      scanner.add(
        'event: message_start\n'
        'data: {"type":"message_start","message":{"usage":'
        '{"input_tokens":100,"cache_read_input_tokens":20,'
        '"cache_creation_input_tokens":5}}}\n\n'
        'event: message_delta\n'
        'data: {"type":"message_delta","usage":{"output_tokens":50}}\n\n'
        'event: message_stop\n'
        'data: {"type":"message_stop"}\n\n',
      );
      scanner.flush();

      expect(scanner.sawCompletionSignal, isTrue);
      expect(scanner.usage['input'], 100);
      expect(scanner.usage['output'], 50);
      expect(scanner.usage['cache_read'], 20);
      expect(scanner.usage['cache_creation'], 5);
    });

    test('message_stop 跨 chunk 边界分裂仍能识别', () {
      final scanner = AnthropicSseScanner();
      scanner.add('event: message_st');
      scanner.add('op\ndata: {"type":"mess');
      scanner.add('age_stop"}\n\n');
      scanner.flush();

      expect(scanner.sawCompletionSignal, isTrue);
    });

    test('usage 跨 chunk 边界分裂仍能累积', () {
      final scanner = AnthropicSseScanner();
      scanner.add('data: {"type":"message_delta","usage":{"outp');
      scanner.add('ut_tokens":77}}\n');
      scanner.flush();

      expect(scanner.usage['output'], 77);
    });

    test('末行没有换行结尾时由 flush 收尾', () {
      final scanner = AnthropicSseScanner();
      scanner.add('data: {"type":"message_stop"}');
      expect(scanner.sawCompletionSignal, isFalse);

      scanner.flush();
      expect(scanner.sawCompletionSignal, isTrue);
    });

    test('缺少 message_stop 时不误报完成', () {
      final scanner = AnthropicSseScanner();
      scanner.add(
        'event: content_block_delta\n'
        'data: {"type":"content_block_delta","delta":{"text":"hi"}}\n\n',
      );
      scanner.flush();

      expect(scanner.sawCompletionSignal, isFalse);
    });

    test('损坏的 JSON 行被跳过且不影响后续行', () {
      final scanner = AnthropicSseScanner();
      scanner.add('data: {"broken\ndata: {"type":"message_stop"}\n');
      scanner.flush();

      expect(scanner.sawCompletionSignal, isTrue);
    });

    test('output_tokens 取最后一次出现的值', () {
      final scanner = AnthropicSseScanner();
      scanner.add(
        'data: {"type":"message_delta","usage":{"output_tokens":10}}\n'
        'data: {"type":"message_delta","usage":{"output_tokens":99}}\n',
      );
      scanner.flush();

      expect(scanner.usage['output'], 99);
    });

    test('无 usage 的流返回全 null', () {
      final scanner = AnthropicSseScanner();
      scanner.add('event: ping\ndata: {"type":"ping"}\n\n');
      scanner.flush();

      expect(scanner.usage, {
        'input': null,
        'output': null,
        'cache_creation': null,
        'cache_read': null,
      });
    });
  });

  group('AnthropicSseScanner 首字信号', () {
    test(
      'message_start / content_block_start / ping 不触发，首个 content_block_delta 触发',
      () {
        final scanner = AnthropicSseScanner();
        scanner.add(
          'event: message_start\n'
          'data: {"type":"message_start","message":{"usage":{"input_tokens":1}}}\n\n'
          'event: content_block_start\n'
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n'
          'event: ping\n'
          'data: {"type":"ping"}\n\n',
        );
        expect(scanner.sawContentDelta, isFalse);

        // thinking 也是内容：扩展思考开启时它就是首个 token
        scanner.add(
          'event: content_block_delta\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"…"}}\n\n',
        );
        expect(scanner.sawContentDelta, isTrue);
      },
    );

    test('跨 chunk 分裂的 content_block_delta 在行完整后才触发', () {
      final scanner = AnthropicSseScanner();
      scanner.add('data: {"type":"content_block_del');
      expect(scanner.sawContentDelta, isFalse);

      scanner.add('ta","index":0,"delta":{"type":"text_delta","text":"hi"}}\n');
      expect(scanner.sawContentDelta, isTrue);
    });
  });
}
