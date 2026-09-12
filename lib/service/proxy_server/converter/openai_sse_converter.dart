/// OpenAI 上游流式转换器的公共接口。
///
/// Chat Completions 与 Responses API 两种流格式共用同一套输出约定，
/// 响应处理器据此统一驱动，不感知上游具体协议。
abstract class OpenAiSseConverter {
  /// 头部事件（message_start + ping），在构造后立即产出
  List<int> initialEvents();

  /// 处理一个上游字节块，返回转换后的 Anthropic SSE 字节
  List<int> handleData(List<int> chunk);

  /// 上游流正常结束的收尾事件
  List<int> handleDone();

  /// 上游流异常中断时的 error 事件
  List<int> handleError(Object error);

  /// 最终 token 用量（供日志与统计）
  Map<String, int?> get finalUsage;

  /// 上游流是否收到过完成信号。
  ///
  /// Chat Completions 为 `[DONE]` 或 finish_reason chunk；
  /// Responses API 为 response.completed/incomplete/failed。
  /// 调用方在流结束后据此区分正常完成与上游静默截断：为 false 时
  /// 应按流中断处理（error 事件 + 断路器计数），不能补发正常收尾事件
  /// 伪装成"零输出成功响应"。
  bool get isComplete;

  /// 上游显式报告的失败；终止事件并不代表成功。
  Object? get error;

  /// 是否已向客户端输出过首个内容 delta（text / thinking / tool 参数）。
  ///
  /// 响应处理器在每个上游 chunk 处理后检查，首次翻转的时刻即首字用时终点；
  /// message_start / ping / content_block_start 不算内容。
  bool get hasContentDelta;

  /// 取走当前累计的输出并清空缓冲
  List<int> takeOutput();
}
