/// 上游流在未发送协议完成信号（Anthropic `message_stop`、OpenAI
/// finish_reason/[DONE] 或 Responses completed/incomplete/failed）前即到达
/// EOF，视为静默截断。
///
/// 这种情况常见于网关在模型长推理中途断开连接：客户端若收到转换器
/// 补发的"正常收尾"会误以为模型零输出完成，而非流被截断。
class UpstreamStreamAbortedException implements Exception {
  const UpstreamStreamAbortedException();

  @override
  String toString() =>
      'Upstream stream ended without completion signal '
      '(connection closed mid-stream)';
}
