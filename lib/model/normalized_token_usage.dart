/// Token usage normalized to Anthropic's mutually-exclusive input categories.
///
/// [inputTokens] contains only uncached input. Cache creation and cache reads
/// live in their own fields, so total input is always the sum of all three.
class NormalizedTokenUsage {
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;

  const NormalizedTokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheCreationInputTokens,
    required this.cacheReadInputTokens,
  });

  static const zero = NormalizedTokenUsage(
    inputTokens: 0,
    outputTokens: 0,
    cacheCreationInputTokens: 0,
    cacheReadInputTokens: 0,
  );

  int get totalInputTokens =>
      inputTokens + cacheCreationInputTokens + cacheReadInputTokens;

  int get totalTokens => totalInputTokens + outputTokens;

  /// Converts OpenAI usage into the internal Anthropic-compatible breakdown.
  ///
  /// OpenAI reports total input in `prompt_tokens` / `input_tokens`; cached
  /// reads and (on APIs that expose it) cache writes are subsets of that total.
  /// Anthropic instead reports uncached input, cache writes, and cache reads as
  /// disjoint fields. This method performs that subtraction exactly once at
  /// the protocol boundary.
  static NormalizedTokenUsage? fromOpenAi({
    required Object? totalInputTokens,
    required Object? outputTokens,
    Object? cacheCreationInputTokens,
    Object? cacheReadInputTokens,
  }) {
    final totalInput = _nonNegativeInt(totalInputTokens);
    final output = _nonNegativeInt(outputTokens);
    final cacheCreation = _nonNegativeInt(cacheCreationInputTokens);
    final cacheRead = _nonNegativeInt(cacheReadInputTokens);

    if (totalInput == null &&
        output == null &&
        cacheCreation == null &&
        cacheRead == null) {
      return null;
    }

    // When a malformed response claims more cached tokens than total input,
    // cap each category to the remaining total. This keeps all stored counts
    // non-negative and preserves the invariant that the parts sum to total.
    var remainingInput = totalInput ?? (cacheCreation ?? 0) + (cacheRead ?? 0);
    final normalizedCacheRead = (cacheRead ?? 0).clamp(0, remainingInput);
    remainingInput -= normalizedCacheRead;
    final normalizedCacheCreation = (cacheCreation ?? 0).clamp(
      0,
      remainingInput,
    );
    remainingInput -= normalizedCacheCreation;

    return NormalizedTokenUsage(
      inputTokens: remainingInput,
      outputTokens: output ?? 0,
      cacheCreationInputTokens: normalizedCacheCreation,
      cacheReadInputTokens: normalizedCacheRead,
    );
  }

  Map<String, dynamic> toAnthropicUsage() => {
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    if (cacheReadInputTokens > 0)
      'cache_read_input_tokens': cacheReadInputTokens,
    'cache_creation_input_tokens': cacheCreationInputTokens,
  };

  static int? _nonNegativeInt(Object? value) {
    final parsed = switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value),
      _ => null,
    };
    if (parsed == null) return null;
    return parsed < 0 ? 0 : parsed;
  }
}
