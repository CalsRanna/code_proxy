import 'package:code_proxy/service/proxy_server/anthropic_sse_model_rewriter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnthropicSseModelRewriter', () {
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

      final rewriter = AnthropicSseModelRewriter('claude-opus-5');
      final rewritten = rewriter.add(original) + rewriter.flush();

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
    });

    test('跨 chunk 边界时行拼接后仍完成替换', () {
      final rewriter = AnthropicSseModelRewriter('claude-opus-5');
      // 第一次 add：事件名行已完整（以 \n 结尾）立即输出；
      // data 行没有换行结尾，保留在缓冲等待补全
      expect(
        rewriter.add('event: message_start\ndata: {"type":"message_start"'),
        'event: message_start\n',
      );
      // 第二次 add 补完 data 行其余部分
      final out = rewriter.add(
        ',"message":{"model":"deepseek-real-model"}}\n\n'
        'event: message_stop\n'
        'data: {"type":"message_stop"}\n\n',
      );
      rewriter.flush();

      expect(
        out,
        'data: {"type":"message_start","message":{"model":"claude-opus-5"}}\n\n'
        'event: message_stop\n'
        'data: {"type":"message_stop"}\n\n',
      );
    });

    test('非 JSON 或损坏的 data 行原样透传', () {
      final rewriter = AnthropicSseModelRewriter('claude-opus-5');
      final out = rewriter.add(
        'event: message_start\n'
        'data: {"type":"mess\n' // 损坏：缺少闭合，解析失败
        'data: {"type":"ping"}\n\n',
      );
      rewriter.flush();

      expect(
        out,
        'event: message_start\n'
        'data: {"type":"mess\n'
        'data: {"type":"ping"}\n\n',
      );
    });

    test('无 data: 前缀的行（event 名行）原样透传', () {
      final rewriter = AnthropicSseModelRewriter('claude-opus-5');
      final out = rewriter.add(
        'event: message_start\n'
        'data: {"type":"message_start","message":{"model":"deepseek"}}\n\n',
      );
      rewriter.flush();

      expect(
        out,
        'event: message_start\n'
        'data: {"type":"message_start","message":{"model":"claude-opus-5"}}\n\n',
      );
    });

    test('flush 处理末尾无换行的 message_start 残留行', () {
      final rewriter = AnthropicSseModelRewriter('claude-opus-5');
      // 事件名行已完整输出；无换行结尾的 data 行由 flush 收尾改写
      expect(
        rewriter.add(
          'event: message_start\n'
          'data: {"type":"message_start","message":{"model":"deepseek"}}',
        ),
        'event: message_start\n',
      );
      final flushed = rewriter.flush();

      expect(
        flushed,
        'data: {"type":"message_start","message":{"model":"claude-opus-5"}}',
      );
    });

    test('多事件流顺序与换行结构保持', () {
      final rewriter = AnthropicSseModelRewriter('claude-opus-5');
      final out = rewriter.add(
        'event: ping\n'
        'data: {"type":"ping"}\n\n'
        'event: message_start\n'
        'data: {"type":"message_start","message":{"model":"a"}}\n\n'
        'event: content_block_start\n'
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n',
      );
      rewriter.flush();

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
      final rewriter = AnthropicSseModelRewriter('claude-opus-5');
      final out = rewriter.add(
        'data: {"type":"message_start","message":{"id":"msg_1"}}\n\n',
      );
      rewriter.flush();

      expect(
        out,
        'data: {"type":"message_start","message":{"id":"msg_1"}}\n\n',
      );
    });

    test('保留 data: 后无空格的写法结构', () {
      final rewriter = AnthropicSseModelRewriter('claude-opus-5');
      final out = rewriter.add(
        'data:{"type":"message_start","message":{"model":"deepseek"}}\n\n',
      );
      rewriter.flush();

      expect(
        out,
        'data:{"type":"message_start","message":{"model":"claude-opus-5"}}\n\n',
      );
    });
  });
}
