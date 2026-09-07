/// 模型入口哨兵 —— 客户端可见的恒定模型名(入口)。
///
/// CLI 与 Desktop 都通过模型发现拿到这些名字并原样回传:CLI 读
/// `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` 走 /v1/models 的 id,
/// Desktop 则直接使用发现列表的 id。代理端由
/// [ProxyServerModelMapper] 按哨兵精确匹配到**当前端点**的实际模型
/// (出口)。故障转移只改变出口,入口恒定 → 客户端无感。
///
/// 命名约束:必须以 `claude-` 开头 —— Claude Desktop(v1.6259.1 起)与
/// Claude Code CLI 的模型发现都会过滤掉"不明显是 Claude"的 id
/// (官方文档:auto-discovery shows only models whose IDs are
/// recognizably Claude)。
library;

abstract final class ProxySentinel {
  // —— 标准哨兵(当前规范,settings 与 /v1/models 共用)——

  /// Opus 槽位
  static const String opus = 'claude-opus-proxy';

  /// Sonnet 槽位
  static const String sonnet = 'claude-sonnet-proxy';

  /// Haiku 槽位
  static const String haiku = 'claude-haiku-proxy';

  // —— 旧哨兵(2026-09 前 settings.json 的"值=变量名"形态,升级过渡兼容)——

  /// 旧 Opus 哨兵
  static const String legacyOpus = 'ANTHROPIC_DEFAULT_OPUS_MODEL';

  /// 旧 Sonnet 哨兵
  static const String legacySonnet = 'ANTHROPIC_DEFAULT_SONNET_MODEL';

  /// 旧 Haiku 哨兵
  static const String legacyHaiku = 'ANTHROPIC_DEFAULT_HAIKU_MODEL';

  /// 已退役的快速模型占位符(Claude Code 弃用后仍可能出现在旧配置中)
  static const String legacySmallFast = 'ANTHROPIC_SMALL_FAST_MODEL';

  // —— 模型族 tier(/v1/models 的 anthropic_family_tier 字段)——
  //
  // 官方文档指定该字段用于把"不透明别名的 Claude 模型"标记为 Claude,
  // 使其通过自动发现过滤;与 claude- 前缀构成双保险。

  /// Opus tier
  static const String tierOpus = 'opus';

  /// Sonnet tier
  static const String tierSonnet = 'sonnet';

  /// Haiku tier
  static const String tierHaiku = 'haiku';
}
