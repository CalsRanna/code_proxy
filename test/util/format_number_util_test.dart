import 'package:code_proxy/util/format_number_util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatWithThousandsSeparator', () {
    test('不足千位不加逗号', () {
      expect(formatWithThousandsSeparator(0), '0');
      expect(formatWithThousandsSeparator(999), '999');
    });

    test('每三位插入一个逗号', () {
      expect(formatWithThousandsSeparator(1000), '1,000');
      expect(formatWithThousandsSeparator(47202), '47,202');
      expect(formatWithThousandsSeparator(1234567), '1,234,567');
      expect(formatWithThousandsSeparator(1234567890), '1,234,567,890');
    });

    test('负数千分位', () {
      expect(formatWithThousandsSeparator(-1234), '-1,234');
      expect(formatWithThousandsSeparator(-1234567), '-1,234,567');
    });
  });

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
    test('首字用时在前、总用时在后，并排展示', () {
      expect(formatResponseTiming(548, 7390), '548ms / 7.39s');
      expect(formatResponseTiming(1250, 12340), '1.25s / 12.34s');
    });

    test('首字用时缺失时用 - 占位，总用时照常展示', () {
      expect(formatResponseTiming(null, 7390), '- / 7.39s');
    });

    test('总用时缺失时用 - 占位，两者都缺失即 - / -', () {
      expect(formatResponseTiming(548, null), '548ms / -');
      expect(formatResponseTiming(null, null), '- / -');
    });
  });
}
