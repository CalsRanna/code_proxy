/// 千分位格式化：1234567 → 1,234,567；负数同样适用（-1234 → -1,234）。
String formatWithThousandsSeparator(int n) {
  final digits = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 图表缩略数字格式：1.0M / 1.0K，不足千按原样显示。
String formatCompactNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return n.toString();
}

/// 毫秒时长的自适应格式：不足 1 秒显示整数毫秒（548ms），否则显示两位
/// 小数的秒（1.25s）。
String formatDurationMs(int ms) {
  if (ms < 1000) return '${ms}ms';
  return '${(ms / 1000).toStringAsFixed(2)}s';
}

/// 请求列表「响应时间」列文案：总用时 / 首字用时，如 `7.39s / 548ms`。
///
/// 总用时固定以秒展示（沿用历史列格式）；首字用时缺失（非流式、失败、
/// 历史记录）时不显示首字用时段。
String formatResponseTiming(int? responseTime, int? ttftMs) {
  final total = '${((responseTime ?? 0) / 1000).toStringAsFixed(2)}s';
  if (ttftMs == null) return total;
  final ttft = formatDurationMs(ttftMs);
  return '$total / $ttft';
}
