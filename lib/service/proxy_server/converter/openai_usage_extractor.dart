import 'package:code_proxy/model/normalized_token_usage.dart';

/// 从 OpenAI 格式的 usage 对象提取归一化用量。
///
/// Chat Completions 与 Responses 的 usage 键名不同但结构等价：
/// - chat：prompt_tokens / completion_tokens / prompt_tokens_details
/// - responses：input_tokens / output_tokens / input_tokens_details
/// 键名由调用方传入；缓存拆分语义（cached_tokens → 缓存读取、
/// cache_write_tokens → 缓存创建）只在这一份实现里维护。
NormalizedTokenUsage? extractOpenAiUsage(
  Map usage, {
  required String totalInputKey,
  required String outputKey,
  required String detailsKey,
}) {
  final details = usage[detailsKey];
  return NormalizedTokenUsage.fromOpenAi(
    totalInputTokens: usage[totalInputKey],
    outputTokens: usage[outputKey],
    cacheReadInputTokens: details is Map ? details['cached_tokens'] : null,
    cacheCreationInputTokens: details is Map
        ? details['cache_write_tokens']
        : null,
  );
}
