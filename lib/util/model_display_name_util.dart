/// 从模型 ID 生成可读的显示名称。
///
/// 优先匹配 Claude 模型的标准命名（`claude-<variant>-<major>-<minor>`），
/// 例如 `claude-sonnet-4-5` → `Claude Sonnet 4.5`；其余模型按 `-` 分段
/// 首字母大写，例如 `deepseek-chat` → `Deepseek Chat`。
///
/// 空段会被跳过。早前 ProxyServerLocalResponder 与 ClaudeCodeSettingService
/// 各持有一份逐字相同的实现，对空串直接取 `s[0]`，在模型名以 `-` 结尾或
/// 含 `--` 时抛 RangeError，并被调用方的空 catch 静默吞掉，导致
/// `/v1/models` 列表与 `*_MODEL_NAME` 环境变量部分缺失。
String modelDisplayName(String modelId) {
  final match = RegExp(r'^claude-(\w+)-(\d+)-(\d+)').firstMatch(modelId);
  if (match != null) {
    final variant = match.group(1)!;
    final major = match.group(2)!;
    final minor = match.group(3)!;
    return 'Claude ${variant[0].toUpperCase()}${variant.substring(1)} $major.$minor';
  }
  return modelId
      .split('-')
      .where((segment) => segment.isNotEmpty)
      .map((segment) => segment[0].toUpperCase() + segment.substring(1))
      .join(' ');
}
