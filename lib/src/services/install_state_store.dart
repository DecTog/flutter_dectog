import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../version.dart';
import 'sdk_storage.dart';

/// Install sentinel v2 — the SDK's record of the first-launch
/// install registration, in the backup-excluded storage directory.
///
/// What changed from the earlier `.adto_install_tracked` file and why:
///  - `install_attempt_id`: a client idempotency key sent with every attempt
///    of the install POST. The old pending/failed retry was at-least-once
///    with nothing to dedupe on, so a launch that died after the server
///    wrote the row produced a second install. Branch sends a
///    `branch_sdk_request_unique_id`, AppsFlyer a `request_id`; the worker
///    now keys the row on this id and replays return the stored verdict.
///  - `package_first_install_ts`: the package manager's first-install time
///    (Android) / the container creation date (iOS) at the time the sentinel
///    was written. A restored backup that still carries the file is detected
///    because the value no longer matches — the flow starts over instead of
///    silently skipping the install (the directory is also excluded from
///    backup, this is the second line of defence).
///  - `attempt` + `abandoned`: cross-launch retries are bounded (Adjust's
///    package queue backs off; Branch re-runs on the next foreground) — ten
///    launches without a 2xx and the SDK stops trying.
///  - `referrer_claimed` / `referrer_status` / `referrer_launches`: the Play
///    referrer is re-read on later launches until it is definitive, and the
///    "claimed" flag is written only after the server acknowledged the
///    claim (Adjust's ActivityState install-referrer flag is set only after
///    the sdk_click is sent).
///
/// Pure JSON, best-effort I/O (never throws into app code), test-injectable
/// directory like the other stores.
enum InstallStatus { pending, tracked, failed, abandoned }

class InstallState {
  const InstallState({
    required this.status,
    required this.installAttemptId,
    required this.attempt,
    required this.createdAt,
    this.attemptedAt,
    this.trackedAt,
    this.lastAttemptAt,
    this.lastError,
    this.installId,
    this.packageFirstInstallTs,
    this.referrerClaimed = false,
    this.referrerStatus,
    this.referrerLaunches = 0,
    this.asaClaimed = false,
    this.recoveredFrom,
    this.pluginVersion = packageVersion,
  });

  final InstallStatus status;
  final String installAttemptId;
  final int attempt;

  /// When the install flow first started on this device (attempt 1).
  final DateTime createdAt;
  final DateTime? attemptedAt;
  final DateTime? trackedAt;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final String? installId;
  final int? packageFirstInstallTs;
  final bool referrerClaimed;
  final String? referrerStatus;
  final int referrerLaunches;

  /// Apple Search Ads token delivered (or not applicable) — same ack-gated
  /// pattern as the referrer, Branch retries the token every open until
  /// obtained.
  final bool asaClaimed;

  /// The install id the server answered `install_not_found` for; this
  /// registration replaces it.
  final String? recoveredFrom;
  final String pluginVersion;

  static const int version = 2;

  InstallState copyWith({
    InstallStatus? status,
    int? attempt,
    DateTime? attemptedAt,
    DateTime? trackedAt,
    DateTime? lastAttemptAt,
    String? lastError,
    bool clearLastError = false,
    String? installId,
    int? packageFirstInstallTs,
    bool? referrerClaimed,
    String? referrerStatus,
    int? referrerLaunches,
    bool? asaClaimed,
  }) {
    return InstallState(
      status: status ?? this.status,
      installAttemptId: installAttemptId,
      attempt: attempt ?? this.attempt,
      createdAt: createdAt,
      attemptedAt: attemptedAt ?? this.attemptedAt,
      trackedAt: trackedAt ?? this.trackedAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      installId: installId ?? this.installId,
      packageFirstInstallTs:
          packageFirstInstallTs ?? this.packageFirstInstallTs,
      referrerClaimed: referrerClaimed ?? this.referrerClaimed,
      referrerStatus: referrerStatus ?? this.referrerStatus,
      referrerLaunches: referrerLaunches ?? this.referrerLaunches,
      asaClaimed: asaClaimed ?? this.asaClaimed,
      recoveredFrom: recoveredFrom,
      pluginVersion: pluginVersion,
    );
  }

  Map<String, dynamic> toJson() => {
    'v': version,
    'status': status.name,
    'install_attempt_id': installAttemptId,
    'attempt': attempt,
    'created_at': createdAt.toIso8601String(),
    if (attemptedAt != null) 'attempted_at': attemptedAt!.toIso8601String(),
    if (trackedAt != null) 'tracked_at': trackedAt!.toIso8601String(),
    if (lastAttemptAt != null)
      'last_attempt_at': lastAttemptAt!.toIso8601String(),
    if (lastError != null) 'last_error': lastError,
    if (installId != null) 'install_id': installId,
    if (packageFirstInstallTs != null)
      'package_first_install_ts': packageFirstInstallTs,
    'referrer_claimed': referrerClaimed,
    if (referrerStatus != null) 'referrer_status': referrerStatus,
    'referrer_launches': referrerLaunches,
    'asa_claimed': asaClaimed,
    if (recoveredFrom != null) 'recovered_from': recoveredFrom,
    'plugin_version': pluginVersion,
  };

  /// Null for anything that is not a well-formed v2 sentinel.
  static InstallState? fromJson(Map<String, dynamic> json) {
    if (json['v'] != version) return null;
    final status = InstallStatus.values.cast<InstallStatus?>().firstWhere(
      (s) => s!.name == json['status'],
      orElse: () => null,
    );
    final id = json['install_attempt_id'];
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    if (status == null || id is! String || id.isEmpty || createdAt == null)
      return null;
    DateTime? date(String key) => DateTime.tryParse(json[key] as String? ?? '');
    return InstallState(
      status: status,
      installAttemptId: id,
      attempt: (json['attempt'] as num?)?.toInt() ?? 1,
      createdAt: createdAt,
      attemptedAt: date('attempted_at'),
      trackedAt: date('tracked_at'),
      lastAttemptAt: date('last_attempt_at'),
      lastError: json['last_error'] as String?,
      installId: json['install_id'] as String?,
      packageFirstInstallTs:
          (json['package_first_install_ts'] as num?)?.toInt(),
      referrerClaimed: json['referrer_claimed'] == true,
      referrerStatus: json['referrer_status'] as String?,
      referrerLaunches: (json['referrer_launches'] as num?)?.toInt() ?? 0,
      asaClaimed: json['asa_claimed'] == true,
      recoveredFrom: json['recovered_from'] as String?,
      pluginVersion: json['plugin_version'] as String? ?? packageVersion,
    );
  }
}

/// What [InstallStateStore.begin] decided for this launch.
enum InstallDecisionKind {
  /// Run the install registration now (fresh install, or a retry).
  start,

  /// A recent `pending` claim belongs to a launch that is probably still in
  /// flight (another isolate, a killed-and-restarted process inside the
  /// TTL): skip this launch.
  inFlight,

  /// The install was registered before.
  alreadyTracked,

  /// Ten launches without a success: the SDK stopped trying.
  abandoned,
}

class InstallDecision {
  const InstallDecision(this.kind, this.state);
  final InstallDecisionKind kind;
  final InstallState? state;
}

/// RFC 4122 v4 from `Random.secure()` — no dependency needed.
String uuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class InstallStateStore {
  InstallStateStore._internal();
  static final InstallStateStore _instance = InstallStateStore._internal();

  factory InstallStateStore() => _instance;

  static const String fileName = '.adto_install.json';

  /// How long a `pending` claim suppresses a re-POST before it is assumed
  /// to belong to a launch that died mid-flight.
  static const Duration pendingClaimTtl = Duration(minutes: 5);

  /// Cross-launch cap on install POST attempts (Adjust keeps retrying with
  /// backoff; ten launches is our bound — after that the install is
  /// abandoned client-side and the server never hears about it).
  static const int maxAttempts = 10;

  /// How many later launches re-read a non-definitive referrer.
  static const int maxReferrerLaunches = 5;

  File? _file;
  InstallState? _current;
  Future<Directory> Function()? _directoryProvider;

  /// The in-memory copy after [load] / [begin] (null until then).
  InstallState? get current => _current;

  @visibleForTesting
  Future<void> resetForTest({
    Future<Directory> Function()? directoryProvider,
    bool keepFile = false,
  }) async {
    _file = null;
    _current = null;
    _directoryProvider = directoryProvider;
    if (directoryProvider != null && !keepFile) {
      final f = File('${(await directoryProvider()).path}/$fileName');
      if (await f.exists()) await f.delete();
    }
  }

  Future<File> _fileRef() async {
    if (_file == null) {
      final dir =
          await (_directoryProvider?.call() ?? SdkStorage().directory());
      _file = File('${dir.path}/$fileName');
    }
    return _file!;
  }

  /// Read the sentinel. [packageFirstInstallTs] (when known) must match the
  /// stored value — a mismatch is a restored backup from a previous install
  /// of the app, treated as "no sentinel" (and the stale file is removed).
  /// Any unreadable file is also "no sentinel": with the idempotency key a
  /// repeated POST is harmless, whereas skipping an install is a lost
  /// attribution.
  Future<InstallState?> load({int? packageFirstInstallTs}) async {
    try {
      final file = await _fileRef();
      if (!await file.exists()) return _current = null;
      final decoded = jsonDecode(await file.readAsString());
      final state =
          decoded is Map<String, dynamic>
              ? InstallState.fromJson(decoded)
              : null;
      if (state == null) return _current = null;
      if (packageFirstInstallTs != null &&
          state.packageFirstInstallTs != null &&
          state.packageFirstInstallTs != packageFirstInstallTs) {
        try {
          await file.delete();
        } catch (_) {}
        return _current = null;
      }
      return _current = state;
    } catch (_) {
      return _current = null;
    }
  }

  /// Decide what this launch does and claim the attempt (`pending`) when it
  /// should run. [now] is injectable for tests.
  Future<InstallDecision> begin({
    int? packageFirstInstallTs,
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    final existing = await load(packageFirstInstallTs: packageFirstInstallTs);
    if (existing == null) {
      final fresh = InstallState(
        status: InstallStatus.pending,
        installAttemptId: uuidV4(),
        attempt: 1,
        createdAt: t,
        attemptedAt: t,
        packageFirstInstallTs: packageFirstInstallTs,
      );
      await _persist(fresh);
      return InstallDecision(InstallDecisionKind.start, fresh);
    }
    switch (existing.status) {
      case InstallStatus.tracked:
        return InstallDecision(InstallDecisionKind.alreadyTracked, existing);
      case InstallStatus.abandoned:
        return InstallDecision(InstallDecisionKind.abandoned, existing);
      case InstallStatus.pending:
        final attemptedAt = existing.attemptedAt;
        if (attemptedAt != null &&
            t.difference(attemptedAt) < pendingClaimTtl &&
            !t.isBefore(attemptedAt)) {
          return InstallDecision(InstallDecisionKind.inFlight, existing);
        }
        return _retry(existing, t);
      case InstallStatus.failed:
        return _retry(existing, t);
    }
  }

  /// The server no longer knows [lostInstallId] (a database restore,
  /// a retention purge, a build pointed at a fresh database). Reset the
  /// sentinel so the next registration runs with a NEW attempt id, names the
  /// lost id as `recovered_from` and reports `install_state: reinstall`; the
  /// server never fingerprints it. A second signal for the same id is a
  /// no-op. Returns whether a recovery was started.
  Future<bool> beginRecovery(String lostInstallId, {DateTime? now}) async {
    final existing = _current ?? await load();
    if (existing?.recoveredFrom == lostInstallId) return false;
    final t = now ?? DateTime.now();
    await _persist(
      InstallState(
        status: InstallStatus.failed,
        installAttemptId: uuidV4(),
        attempt: 0,
        createdAt: t,
        packageFirstInstallTs: existing?.packageFirstInstallTs,
        referrerClaimed: existing?.referrerClaimed ?? false,
        referrerStatus: existing?.referrerStatus,
        asaClaimed: existing?.asaClaimed ?? false,
        recoveredFrom: lostInstallId,
      ),
    );
    return true;
  }

  Future<InstallDecision> _retry(InstallState existing, DateTime now) async {
    if (existing.attempt >= maxAttempts) {
      final gone = existing.copyWith(
        status: InstallStatus.abandoned,
        lastAttemptAt: now,
      );
      await _persist(gone);
      return InstallDecision(InstallDecisionKind.abandoned, gone);
    }
    final next = existing.copyWith(
      status: InstallStatus.pending,
      attempt: existing.attempt + 1,
      attemptedAt: now,
    );
    await _persist(next);
    return InstallDecision(InstallDecisionKind.start, next);
  }

  /// The server accepted the install.
  Future<InstallState?> markTracked({
    required String? installId,
    required bool referrerClaimed,
    String? referrerStatus,
    DateTime? now,
  }) async {
    final s = _current;
    if (s == null) return null;
    final next = s.copyWith(
      status: InstallStatus.tracked,
      trackedAt: now ?? DateTime.now(),
      installId: installId,
      referrerClaimed: referrerClaimed,
      referrerStatus: referrerStatus,
      clearLastError: true,
    );
    await _persist(next);
    return next;
  }

  /// The POST failed for this launch: the next launch retries (bounded).
  Future<InstallState?> markFailed(String error, {DateTime? now}) async {
    final s = _current;
    if (s == null) return null;
    final next = s.copyWith(
      status: InstallStatus.failed,
      lastAttemptAt: now ?? DateTime.now(),
      lastError: error.length > 512 ? error.substring(0, 512) : error,
    );
    await _persist(next);
    return next;
  }

  /// Ack-gated: call only after the server returned 200 for the claim (or
  /// 404 — nothing left to upgrade).
  Future<InstallState?> markReferrerClaimed(String? status) async {
    final s = _current;
    if (s == null) return null;
    final next = s.copyWith(referrerClaimed: true, referrerStatus: status);
    await _persist(next);
    return next;
  }

  Future<InstallState?> bumpReferrerLaunches() async {
    final s = _current;
    if (s == null) return null;
    final next = s.copyWith(referrerLaunches: s.referrerLaunches + 1);
    await _persist(next);
    return next;
  }

  Future<InstallState?> markAsaClaimed() async {
    final s = _current;
    if (s == null) return null;
    final next = s.copyWith(asaClaimed: true);
    await _persist(next);
    return next;
  }

  Future<void> _persist(InstallState state) async {
    _current = state;
    try {
      final file = await _fileRef();
      await file.writeAsString(jsonEncode(state.toJson()), flush: true);
    } catch (_) {
      // Best effort: the in-memory state still drives this process.
    }
  }
}
