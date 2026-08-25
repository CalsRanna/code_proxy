import 'package:code_proxy/service/proxy_server/proxy_server_response_handler.dart';
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
}
