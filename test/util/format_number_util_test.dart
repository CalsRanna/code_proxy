import 'package:code_proxy/util/format_number_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDurationMs', () {
    test('不足 1 秒显示整数毫秒', () {
      expect(formatDurationMs(0), '0ms');
      expect(formatDurationMs(548), '548ms');
      expect(formatDurationMs(999), '999ms');
    });

    test('1 秒及以上显示两位小数的秒', () {
      expect(formatDurationMs(1000), '1.00s');
      expect(formatDurationMs(1250), '1.25s');
    });
  });

  group('formatResponseTiming', () {
    test('总用时与首字用时并排展示', () {
      expect(formatResponseTiming(7390, 548), '7.39s / 548ms');
      expect(formatResponseTiming(12340, 1250), '12.34s / 1.25s');
    });

    test('首字用时缺失时显示占位符', () {
      expect(formatResponseTiming(7390, null), '7.39s / -');
      expect(formatResponseTiming(null, null), '0.00s / -');
    });
  });
}
