import 'dart:math';

final _retryRandom = Random();

/// Full jitter before a one-based attempt; the first attempt is immediate.
///
/// Each retry samples 0..cap milliseconds, with caps of 1s, 2s, 4s, 8s, 16s, 32s.
/// Subsequent retries keep sampling the full 0..32s range.
int calculateProxyRetryDelayMs(int attempt, {Random? random}) {
  if (attempt <= 1) return 0;
  // Clamp before shifting so unlimited retries cannot overflow the integer.
  final shift = (attempt - 2).clamp(0, 5);
  final capMs = 1000 * (1 << shift);
  return (random ?? _retryRandom).nextInt(capMs + 1);
}
