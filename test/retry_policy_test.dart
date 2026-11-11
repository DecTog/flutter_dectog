import 'dart:math';

import 'package:flutter_adto/src/services/retry_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('installRetryDecision', () {
    test('network errors, 408, 429 and 5xx retry in-process', () {
      for (final s in [null, 408, 429, 500, 502, 503]) {
        expect(installRetryDecision(s), RetryDecision.retryNow, reason: '$s');
      }
    });

    test('other 4xx (incl. 401) defer to the next launch', () {
      for (final s in [400, 401, 403, 404, 413, 422]) {
        expect(installRetryDecision(s), RetryDecision.retryLater, reason: '$s');
      }
    });

    test('2xx is done', () {
      expect(installRetryDecision(200), RetryDecision.done);
    });
  });

  group('shouldDropEventBatch', () {
    test('drops 400–499 except 401/408/429; never drops 5xx', () {
      expect(shouldDropEventBatch(400), isTrue);
      expect(shouldDropEventBatch(413), isTrue);
      expect(shouldDropEventBatch(401), isFalse);
      expect(shouldDropEventBatch(408), isFalse);
      expect(shouldDropEventBatch(429), isFalse);
      expect(shouldDropEventBatch(500), isFalse);
      expect(shouldDropEventBatch(503), isFalse);
    });
  });

  group('backoffDelay', () {
    test('doubles per attempt with jitter in [0.5, 1) of the exponential', () {
      final r = Random(42);
      for (var attempt = 1; attempt <= 4; attempt++) {
        final exp = 1000 * (1 << (attempt - 1));
        for (var i = 0; i < 20; i++) {
          final d = backoffDelay(attempt, random: r).inMilliseconds;
          expect(d, greaterThanOrEqualTo(exp ~/ 2), reason: 'attempt $attempt');
          expect(d, lessThan(exp), reason: 'attempt $attempt');
        }
      }
    });

    test('is capped', () {
      expect(
        backoffDelay(30, max: const Duration(seconds: 5)),
        lessThanOrEqualTo(const Duration(seconds: 5)),
      );
    });
  });

  group('parseRetryAfter', () {
    test('delta seconds', () {
      expect(parseRetryAfter('7'), const Duration(seconds: 7));
      expect(parseRetryAfter(' 0 '), Duration.zero);
      expect(parseRetryAfter('-3'), Duration.zero);
    });

    test('HTTP date relative to now; past dates are zero', () {
      final now = DateTime.utc(1994, 11, 6, 8, 49, 37);
      expect(
        parseRetryAfter('Sun, 06 Nov 1994 08:50:07 GMT', now: now),
        const Duration(seconds: 30),
      );
      expect(
        parseRetryAfter('Sun, 06 Nov 1994 08:00:00 GMT', now: now),
        Duration.zero,
      );
    });

    test('absent or garbage is null', () {
      expect(parseRetryAfter(null), isNull);
      expect(parseRetryAfter(''), isNull);
      expect(parseRetryAfter('soon'), isNull);
    });
  });
}
