/// 按「本地日期 + 模型」聚合的 token 用量（仅统计 2xx 成功请求）。
///
/// 四类计数遵循 Anthropic 口径且互不重叠：[input] 仅为未缓存输入，
/// [cacheCreation] 与 [cacheRead] 各自独立，因此 [total] 是四者之和。
///
/// 图表与费用计算共用同一份聚合结果 —— 此前两者各跑一条几乎相同的
/// `GROUP BY (date, model)` 查询，只是返回形状不同。
class ModelDateTokenStat {
  /// 本地时区下的日期，格式 `YYYY-MM-DD`。
  final String date;

  /// 模型名；请求未记录 model 时为 `unknown`。
  final String model;

  final int input;
  final int output;
  final int cacheCreation;
  final int cacheRead;

  const ModelDateTokenStat({
    required this.date,
    required this.model,
    required this.input,
    required this.output,
    required this.cacheCreation,
    required this.cacheRead,
  });

  int get total => input + output + cacheCreation + cacheRead;
}
