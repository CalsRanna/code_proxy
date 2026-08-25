import 'package:code_proxy/util/model_display_name_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('modelDisplayName', () {
    test('Claude 标准命名走正则 fast path', () {
      expect(modelDisplayName('claude-sonnet-4-5'), 'Claude Sonnet 4.5');
      expect(modelDisplayName('claude-opus-4-1'), 'Claude Opus 4.1');
    });

    test('非 Claude 模型按分段首字母大写', () {
      expect(modelDisplayName('deepseek-chat'), 'Deepseek Chat');
      expect(modelDisplayName('gpt-4o'), 'Gpt 4o');
      expect(modelDisplayName('minimax'), 'Minimax');
    });

    test('畸形模型名的空段被跳过而非抛 RangeError', () {
      expect(modelDisplayName('gpt-4-'), 'Gpt 4');
      expect(modelDisplayName('a--b'), 'A B');
      expect(modelDisplayName('-leading'), 'Leading');
      expect(modelDisplayName('--'), '');
    });

    test('空串不抛异常', () {
      expect(modelDisplayName(''), '');
    });
  });
}
