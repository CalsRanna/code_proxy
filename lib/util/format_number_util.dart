/// 图表缩略数字格式：1.0M / 1.0K，不足千按原样显示。
String formatCompactNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return n.toString();
}
