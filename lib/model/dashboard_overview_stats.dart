/// 概览统计：消息数、token 总量、活跃天数、缓存命中率。
///
/// 口径说明：
/// - [messages]：成功的 `/v1/messages` 请求数，而非 Claude Code 对话的
///   「消息条数」——request_logs 没有会话标识，Claude Code 一次交互触发的
///   多次 API 调用（工具循环）无法归并，此值略大于真实消息数。
/// - [totalTokens]：仅统计 2xx 成功请求，与 token 图表/费用口径一致。
/// - [activeDays]：统计有任意请求（含失败）的本地去重日期数，与热力图
///   口径一致。
/// - [cacheHitRate]：缓存读取占输入类 token 的比例，范围 0.0~1.0。
///   仅统计 2xx 成功请求；cache_creation 是首次写入缓存的 token，既不
///   命中也不算未命中，不计入分子分母。无输入类 token 时为 0.0。
class DashboardOverviewStats {
  final int messages;
  final int totalTokens;
  final int activeDays;
  final double cacheHitRate;

  const DashboardOverviewStats({
    required this.messages,
    required this.totalTokens,
    required this.activeDays,
    this.cacheHitRate = 0.0,
  });
}
