import 'dart:math';

/// Transport decisions for the install POST, modelled on the Adjust
/// package handler (jittered exponential backoff, server `retry_in` honoured)
/// and the Branch request queue (4xx responses are not retried).
///
/// Pure functions so the policy is unit-testable without HTTP.
enum RetryDecision {
  /// Transient: try again in this process after a backoff.
  retryNow,

  /// Not worth another in-process attempt; the next launch retries (the
  /// sentinel goes to `failed`).
  retryLater,

  /// Accepted: nothing to retry.
  done,
}

/// How a failed install POST should be handled. [statusCode] is null for
/// network errors and timeouts.
RetryDecision installRetryDecision(int? statusCode) {
  if (statusCode == null) return RetryDecision.retryNow; // network / timeout
  if (statusCode >= 200 && statusCode < 300) return RetryDecision.done;
  // 408 (request timeout) and 429 (rate limited) are transient like 5xx —
  // 429 additionally carries Retry-After, which the caller applies.
  if (statusCode == 408 || statusCode == 429 || statusCode >= 500) {
    return RetryDecision.retryNow;
  }
  // 401 (bad key — the app may ship a fix), 400/404/413… (nothing a repeat
  // of the same body can fix right now): the next launch gets one more try,
  // bounded by the cross-launch attempt cap.
  return RetryDecision.retryLater;
}

/// Whether an event batch rejected with [statusCode] should be dropped
/// (Branch drops 400–451): malformed batches must not wedge the queue head
/// forever. 401 (key), 408 (timeout) and 429 (rate limit) stay queued.
bool shouldDropEventBatch(int statusCode) {
  if (statusCode < 400 || statusCode >= 500) return false;
  return statusCode != 401 && statusCode != 408 && statusCode != 429;
}

/// Adjust-style backoff for attempt [attempt] (1-based): 1 s · 2^(attempt−1),
/// scaled by a random factor in [0.5, 1) so retries from many devices never
/// align, capped at [max].
Duration backoffDelay(
  int attempt, {
  Duration base = const Duration(seconds: 1),
  Duration max = const Duration(minutes: 1),
  Random? random,
}) {
  final n = attempt < 1 ? 1 : attempt;
  final exp = base.inMilliseconds * (1 << (n - 1).clamp(0, 20));
  final jitter = 0.5 + (random ?? Random()).nextDouble() * 0.5;
  final ms = (exp * jitter).round();
  return Duration(
    milliseconds: ms > max.inMilliseconds ? max.inMilliseconds : ms,
  );
}

/// A `Retry-After` header as a delay: either delta-seconds or an HTTP date.
/// Null when absent or unparseable; negative dates clamp to zero.
Duration? parseRetryAfter(String? header, {DateTime? now}) {
  final v = header?.trim();
  if (v == null || v.isEmpty) return null;
  final seconds = int.tryParse(v);
  if (seconds != null) {
    return Duration(seconds: seconds < 0 ? 0 : seconds);
  }
  final date = _parseHttpDate(v);
  if (date == null) return null;
  final delta = date.difference(now ?? DateTime.now());
  return delta.isNegative ? Duration.zero : delta;
}

/// RFC 7231 IMF-fixdate ("Sun, 06 Nov 1994 08:49:37 GMT"); other legacy
/// forms are rare on modern edges and simply yield null.
DateTime? _parseHttpDate(String value) {
  final m = RegExp(
    r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value);
  if (m == null) return null;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return DateTime.utc(
    int.parse(m.group(3)!),
    months.indexOf(m.group(2)!) + 1,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}
