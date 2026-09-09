import 'dart:io';
import 'dart:math';

import 'package:code_proxy/service/proxy_server/routing/proxy_server_retry_delay.dart';
import 'package:flutter_test/flutter_test.dart';

class _SamplingRandom implements Random {
  final int Function(int) sample;

  _SamplingRandom(this.sample);

  @override
  int nextInt(int max) => sample(max);

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}

void main() {
  test('the first attempt is immediate without drawing randomness', () {
    final random = _SamplingRandom((_) => throw StateError('Unexpected draw'));
    expect(calculateProxyRetryDelayMs(1, random: random), 0);
  });

  test('full jitter includes zero and each exponential upper bound', () {
    const caps = [1000, 2000, 4000, 8000, 16000, 32000, 32000, 32000];
    for (var i = 0; i < caps.length; i++) {
      final random = _SamplingRandom((max) {
        expect(max, caps[i] + 1);
        return max - 1;
      });
      expect(calculateProxyRetryDelayMs(i + 2, random: random), caps[i]);
      expect(
        calculateProxyRetryDelayMs(i + 2, random: _SamplingRandom((_) => 0)),
        0,
      );
    }
  });

  test('capped retries draw again across the full range indefinitely', () {
    final samples = [0, 32000, 400, 19500, 1, 31999];
    var draws = 0;
    final random = _SamplingRandom((max) {
      expect(max, 32001);
      return samples[draws++];
    });
    expect([
      for (final attempt in [7, 8, 9, 10, 1000000, 1000001])
        calculateProxyRetryDelayMs(attempt, random: random),
    ], samples);
    expect(draws, samples.length);
  });

  test('a seeded generator produces varied delays within the capped range', () {
    final random = Random(42);
    final samples = [
      for (var i = 0; i < 100; i++)
        calculateProxyRetryDelayMs(20, random: random),
    ];
    expect(samples, everyElement(inInclusiveRange(0, 32000)));
    expect(samples.toSet().length, greaterThan(1));
    expect(samples.any((value) => value < 16000), isTrue);
    expect(samples.any((value) => value > 16000), isTrue);
  });
  test('Retry-After uses the longer server delay or sampled jitter', () {
    final now = DateTime.utc(2026, 9, 8);
    final random = _SamplingRandom((_) => 500);
    for (final retryAfter in ['0', '-1', 'invalid', HttpDate.format(now)]) {
      expect(
        calculateProxyRetryDelayMs(
          2,
          retryAfter: retryAfter,
          random: random,
          now: now,
        ),
        500,
      );
    }
    expect(
      calculateProxyRetryDelayMs(2, retryAfter: ' 3 ', random: random),
      3000,
    );
    expect(
      calculateProxyRetryDelayMs(
        2,
        retryAfter: HttpDate.format(now.add(const Duration(seconds: 5))),
        now: now,
        random: random,
      ),
      5000,
    );
    expect(
      calculateProxyRetryDelayMs(
        8,
        retryAfter: '3',
        random: _SamplingRandom((_) => 32000),
      ),
      32000,
    );
    expect(calculateProxyRetryDelayMs(8, retryAfter: '60'), 60000);
    expect(calculateProxyRetryDelayMs(2, retryAfter: '999999'), 3600000);
    expect(calculateProxyRetryDelayMs(1, retryAfter: '60'), 0);
  });
}
