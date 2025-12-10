/// 图表数据模型
class ChartData {
  /// 每日请求量统计
  final Map<String, int> dailyRequests;

  /// 按端点的Token使用统计（用于饼图）
  final Map<String, int> endpointTokenUsage;

  /// 按模型和日期的Token使用统计（用于柱状图）
  final Map<String, Map<String, int>> modelDateTokenUsage;

  ChartData({
    required this.dailyRequests,
    required this.endpointTokenUsage,
    required this.modelDateTokenUsage,
  });
}
