import 'dart:async';
import 'dart:io';

import '../models/adto_config.dart';
import 'identifier_channel.dart';

/// Wire statuses of an install-referrer read, as the native reader
/// reports them and as the install row stores them (`referrer_status`).
abstract final class ReferrerStatus {
  static const String ok = 'ok';
  static const String organic = 'organic';
  static const String featureNotSupported = 'feature_not_supported';
  static const String serviceUnavailable = 'service_unavailable';
  static const String developerError = 'developer_error';
  static const String permissionError = 'permission_error';
  static const String timeout = 'timeout';
  static const String error = 'error';
  static const String notAvailable = 'not_available';
  static const String notAndroid = 'not_android';

  /// Definitive answers are never re-read on later launches: the referrer
  /// was delivered, Play reported an organic install, or the API can never
  /// answer on this device. `service_unavailable`, `timeout` and `error`
  /// are transient (Adjust retries these, and re-reads every session until
  /// the referrer is sent).
  static bool isDefinitive(String status) => switch (status) {
    ok ||
    organic ||
    featureNotSupported ||
    permissionError ||
    developerError ||
    notAvailable ||
    notAndroid => true,
    _ => false,
  };
}

/// The referrer the install registration carries: the winning store's
/// values plus the read telemetry (AppsFlyer's `rfr_wait`, Adjust's retry
/// counters) and every store's raw result for diagnostics.
class ReferrerResult {
  const ReferrerResult({
    required this.status,
    this.store,
    this.referrer,
    this.clickTs,
    this.installBeginTs,
    this.clickServerTs,
    this.installBeginServerTs,
    this.installVersion,
    this.instant,
    this.attempts = 0,
    this.waitMs = 0,
    this.all = const {},
  });

  const ReferrerResult.none(this.status, {this.waitMs = 0, this.attempts = 0})
    : store = null,
      referrer = null,
      clickTs = null,
      installBeginTs = null,
      clickServerTs = null,
      installBeginServerTs = null,
      installVersion = null,
      instant = null,
      all = const {};

  final String status;
  final String? store;
  final String? referrer;
  final int? clickTs;
  final int? installBeginTs;
  final int? clickServerTs;
  final int? installBeginServerTs;
  final String? installVersion;
  final bool? instant;
  final int attempts;
  final int waitMs;
  final Map<String, StoreReferrer> all;

  bool get hasReferrer => referrer != null && referrer!.isNotEmpty;
  bool get isDefinitive => ReferrerStatus.isDefinitive(status);

  /// Play's referrer for an install that came from no campaign link.
  static const String organicPlayReferrer =
      'utm_source=google-play&utm_medium=organic';

  /// Whether [referrer] is Play's organic marker (or empty).
  static bool isOrganicReferrer(String? referrer) {
    final v = referrer?.trim() ?? '';
    return v.isEmpty || v == organicPlayReferrer;
  }

  @override
  String toString() =>
      'ReferrerResult(status: $status, store: $store, referrer: $referrer, attempts: $attempts, waitMs: $waitMs)';
}

/// A read that may still be in flight natively after the Dart-side wait
/// expired: [result] is what the install POST ships now; [late] (when set)
/// completes with the real answer once the native reader returns, so the
/// SDK can send it as a late claim in the same process.
class ReferrerRead {
  const ReferrerRead(this.result, {this.late});
  final ReferrerResult result;
  final Future<ReferrerResult>? late;
}

/// Reads every store's install referrer through the native plugin and picks
/// the one the install registration carries.
///
/// Winner rule (Branch `InstallReferrers.kt`): among stores that returned a
/// non-empty referrer, the latest `installBeginTimestamp` wins; Google Play
/// wins ties and unknown timestamps. Meta's provider stays on its own
/// channel call (it is a click record, not a store referrer).
class InstallReferrerService {
  InstallReferrerService({IdentifierChannel? channel})
    : _channel = channel ?? IdentifierChannel();

  final IdentifierChannel _channel;

  static const List<String> playOnly = ['google_play'];
  static const List<String> allStores = [
    'google_play',
    'huawei',
    'samsung',
    'xiaomi',
    'vivo',
  ];

  /// Native reads get this much extra room over [timeout] before the Dart
  /// side gives up on the call for the first POST (the native reader has
  /// its own deadline; the slack covers the channel hop).
  static const Duration _channelSlack = Duration(milliseconds: 750);

  Future<ReferrerRead> read({
    required Duration timeout,
    required bool oemStores,
    InstallReferrerProvider? provider,
    bool? isAndroid,
  }) async {
    final android = isAndroid ?? Platform.isAndroid;
    if (!android)
      return const ReferrerRead(ReferrerResult.none(ReferrerStatus.notAndroid));
    final watch = Stopwatch()..start();

    if (provider != null) {
      // Host-supplied source: a string only, no timestamps; empty or Play's
      // organic marker is an organic install.
      try {
        final value = (await provider().timeout(timeout))?.trim();
        if (ReferrerResult.isOrganicReferrer(value)) {
          return ReferrerRead(
            ReferrerResult.none(
              ReferrerStatus.organic,
              waitMs: watch.elapsedMilliseconds,
              attempts: 1,
            ),
          );
        }
        return ReferrerRead(
          ReferrerResult(
            status: ReferrerStatus.ok,
            store: 'google_play',
            referrer: value,
            attempts: 1,
            waitMs: watch.elapsedMilliseconds,
          ),
        );
      } on TimeoutException {
        return ReferrerRead(
          ReferrerResult.none(
            ReferrerStatus.timeout,
            waitMs: watch.elapsedMilliseconds,
            attempts: 1,
          ),
        );
      } catch (_) {
        return ReferrerRead(
          ReferrerResult.none(
            ReferrerStatus.error,
            waitMs: watch.elapsedMilliseconds,
            attempts: 1,
          ),
        );
      }
    }

    final stores = oemStores ? allStores : playOnly;
    final pending = _channel.getInstallReferrers(
      timeoutMs: timeout.inMilliseconds,
      stores: stores,
    );
    try {
      final raw = await pending.timeout(timeout + _channelSlack);
      return ReferrerRead(_fromRaw(raw, watch.elapsedMilliseconds));
    } on TimeoutException {
      // The native call keeps running; whoever holds `late` can claim the
      // answer when it lands (Adjust sends the referrer whenever the
      // retry eventually succeeds).
      final late = pending
          .then((raw) => _fromRaw(raw, watch.elapsedMilliseconds))
          .catchError(
            (_) => ReferrerResult.none(
              ReferrerStatus.error,
              waitMs: watch.elapsedMilliseconds,
            ),
          );
      return ReferrerRead(
        ReferrerResult.none(
          ReferrerStatus.timeout,
          waitMs: watch.elapsedMilliseconds,
        ),
        late: late,
      );
    } catch (_) {
      return ReferrerRead(
        ReferrerResult.none(
          ReferrerStatus.error,
          waitMs: watch.elapsedMilliseconds,
        ),
      );
    }
  }

  static ReferrerResult _fromRaw(Map<String, StoreReferrer>? raw, int waitMs) {
    if (raw == null)
      return ReferrerResult.none(ReferrerStatus.notAvailable, waitMs: waitMs);
    return pickWinner(raw, waitMs: waitMs);
  }

  /// Pure winner selection over every store's read.
  static ReferrerResult pickWinner(
    Map<String, StoreReferrer> all, {
    int? waitMs,
  }) {
    final candidates =
        all.values
            .where(
              (s) =>
                  s.hasReferrer &&
                  !ReferrerResult.isOrganicReferrer(s.referrer),
            )
            .toList();
    final totalWait =
        waitMs ??
        all.values.fold<int>(0, (m, s) => s.waitMs > m ? s.waitMs : m);
    final totalAttempts = all.values.fold<int>(0, (m, s) => m + s.attempts);
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final ta = a.installBeginTs ?? 0;
        final tb = b.installBeginTs ?? 0;
        if (ta != tb) return tb.compareTo(ta); // latest install-begin first
        if (a.store == 'google_play') return -1;
        if (b.store == 'google_play') return 1;
        return allStores.indexOf(a.store).compareTo(allStores.indexOf(b.store));
      });
      final w = candidates.first;
      return ReferrerResult(
        status: ReferrerStatus.ok,
        store: w.store,
        referrer: w.referrer!.trim(),
        clickTs: w.clickTs,
        installBeginTs: w.installBeginTs,
        clickServerTs: w.clickServerTs,
        installBeginServerTs: w.installBeginServerTs,
        installVersion: w.installVersion,
        instant: w.instant,
        attempts: totalAttempts,
        waitMs: totalWait,
        all: all,
      );
    }
    // No referrer anywhere: Play's own status describes the read (organic,
    // feature_not_supported, …); without a Play entry take the first one.
    final play = all['google_play'];
    final primary = play ?? (all.values.isEmpty ? null : all.values.first);
    if (primary == null)
      return ReferrerResult.none(
        ReferrerStatus.notAvailable,
        waitMs: totalWait,
      );
    var status = primary.status;
    // A Play read that returned its organic marker (or an empty string
    // with status ok) is an organic install, whatever the native side
    // labelled it.
    if (status == ReferrerStatus.ok) status = ReferrerStatus.organic;
    return ReferrerResult(
      status: status,
      store: primary.store,
      referrer: null,
      clickTs: primary.clickTs,
      installBeginTs: primary.installBeginTs,
      clickServerTs: primary.clickServerTs,
      installBeginServerTs: primary.installBeginServerTs,
      installVersion: primary.installVersion,
      instant: primary.instant,
      attempts: totalAttempts,
      waitMs: totalWait,
      all: all,
    );
  }
}
