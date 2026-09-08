import 'dart:io';
import 'dart:math';

final _retryRandom = Random();

/// Samples a capped full-jitter delay before the one-based [attempt].
///
/// Attempt 1 is immediate. Each retry uniformly samples 0..cap milliseconds,
/// with caps of 1s, 2s, 4s, 8s, 16s, then 32s for every subsequent retry.
/// Actual delays need not increase. The caller owns the per-request attempt
/// count and resets it when switching endpoints.
///
/// A valid [retryAfter] sets a lower bound on the sampled delay. Integer seconds
/// are clamped to 0..3600; HTTP dates are measured from [now] or the current time.
/// Invalid values and past dates do not shorten the sampled delay.
int calculateProxyRetryDelayMs(
  int attempt, {
  Random? random,
  String? retryAfter,
  DateTime? now,
}) {
  if (attempt <= 1) return 0;
  // Cap the exponent before shifting; long retry sequences stay within 32s.
  final shift = (attempt - 2).clamp(0, 5);
  final capMs = 1000 * (1 << shift);
  final jitterMs = (random ?? _retryRandom).nextInt(capMs + 1);
  if (retryAfter == null) return jitterMs;
  final seconds = int.tryParse(retryAfter.trim());
  final int serverDelayMs;
  if (seconds != null) {
    // Keep upstream-directed waits within the existing one-hour limit.
    serverDelayMs = seconds.clamp(0, 3600) * 1000;
  } else {
    try {
      serverDelayMs = HttpDate.parse(
        retryAfter,
      ).difference(now ?? DateTime.now()).inMilliseconds;
    } on HttpException {
      return jitterMs;
    }
  }
  return max(jitterMs, serverDelayMs);
}
