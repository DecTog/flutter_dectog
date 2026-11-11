import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sdk_storage.dart';

/// Persisted SDK identity/preferences: the tenant's customer id set
/// by `identify()` (stamped onto later events until `logout()`), the
/// `enabled` flag (`setEnabled`) that stops all collection while false, the
/// install id, the link that last opened the app, and the day of the last
/// device ping.
///
/// Same file-per-fact pattern as the install sentinel: a JSON file in the
/// SDK's backup-excluded storage directory ([SdkStorage] — a
/// restored backup must not resurrect another install's customer id),
/// best-effort, never throws into app code.
/// The AdTo link that last opened the app, stamped on every later
/// event so the server can credit a re-engagement.
class LastOpen {
  const LastOpen({required this.slug, this.clickId, required this.openedAt});

  final String slug;
  final String? clickId;
  final DateTime openedAt;

  Map<String, Object?> toJson() => {
    'slug': slug,
    if (clickId != null) 'click_id': clickId,
    'opened_at': openedAt.toUtc().toIso8601String(),
  };

  static LastOpen? fromJson(Object? json) {
    if (json is! Map) return null;
    final slug = json['slug'];
    final at = DateTime.tryParse(json['opened_at'] as String? ?? '');
    if (slug is! String || slug.isEmpty || at == null) return null;
    return LastOpen(
      slug: slug,
      clickId: validClickId(json['click_id']),
      openedAt: at,
    );
  }
}

/// A click id as the server writes it (`CLICK_ID_RE` in the server's
/// util.ts), or null. A link's malformed `dtg_click` is never kept
/// or sent; the server once refused every event that named one.
String? validClickId(Object? id) =>
    id is String && RegExp(r'^[A-Za-z0-9_-]{8,32}$').hasMatch(id) ? id : null;

class SdkStateStore {
  SdkStateStore._internal();
  static final SdkStateStore _instance = SdkStateStore._internal();

  factory SdkStateStore() => _instance;

  static const String _stateFileName = '.dectog_sdk_state.json';

  File? _file;
  String? _customerId;
  bool? _enabled;
  String? _installId;
  String? _lastIdentify;
  LastOpen? _lastOpen;
  String? _pingDay;
  Future<void>? _loading;

  /// Getters read the in-memory copy: call [load] (initialize does) first.
  String? get customerId => _customerId;

  /// Collection consent: the app's last `setEnabled` choice, which survives
  /// restarts; until it made one, [defaultEnabled] (`AdtoConfig.enabled`).
  bool get enabled => _enabled ?? defaultEnabled;

  /// `AdtoConfig.enabled`, set by initialize.
  bool defaultEnabled = true;

  /// The install verdict's id, persisted after the first-launch install
  /// POST so later launches can stamp event batches and app-opens
  /// without a server round-trip.
  String? get installId => _installId;

  /// Fingerprint of the last identify event queued for [customerId], so a
  /// repeat identify with unchanged fields is skipped.
  String? get lastIdentify => _lastIdentify;

  /// The link that last opened the app (null until one did).
  LastOpen? get lastOpen => _lastOpen;

  /// The UTC day ('YYYY-MM-DD') of the last device ping the server took. It
  /// keeps one row per device per day, so one ping a day is enough.
  String? get pingDay => _pingDay;

  @visibleForTesting
  Future<void> resetForTest({
    Future<Directory> Function()? directoryProvider,
    bool simulateRestart = false,
  }) async {
    _file = null;
    _customerId = null;
    _enabled = null;
    defaultEnabled = true;
    _installId = null;
    _lastIdentify = null;
    _lastOpen = null;
    _pingDay = null;
    _loading = null;
    if (directoryProvider != null) {
      final dir = await directoryProvider();
      _file = File('${dir.path}/$_stateFileName');
      // A simulated restart keeps the file and leaves it for load() to read.
      if (simulateRestart) return;
      _loading = Future.value(); // the test dir starts empty by definition
      if (await _file!.exists()) {
        await _file!.delete();
      }
    }
  }

  Future<File> _fileRef() async {
    if (_file == null) {
      final dir = await SdkStorage().directory();
      _file = File('${dir.path}/$_stateFileName');
    }
    return _file!;
  }

  /// Read the persisted state once per process. Concurrent callers share
  /// one read, so a setter racing the first load can't be overwritten by it.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final file = await _fileRef();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          _customerId = decoded['customer_id'] as String?;
          _enabled = decoded['enabled'] as bool?;
          _installId = decoded['install_id'] as String?;
          _lastIdentify = decoded['last_identify'] as String?;
          _lastOpen = LastOpen.fromJson(decoded['last_open']);
          _pingDay = decoded['ping_day'] as String?;
        }
      }
    } catch (_) {}
  }

  /// Set the customer id; [identifyKey] is the fingerprint of the identify
  /// event queued with it (null when none was queued, e.g. on logout).
  Future<void> setCustomerId(String? customerId, {String? identifyKey}) async {
    await load();
    _customerId = customerId;
    _lastIdentify = identifyKey;
    await _persist();
  }

  Future<void> setEnabled(bool enabled) async {
    await load();
    _enabled = enabled;
    await _persist();
  }

  Future<void> setInstallId(String? installId) async {
    await load();
    if (_installId == installId) return;
    _installId = installId;
    await _persist();
  }

  /// The server took a device ping on [day] (UTC, 'YYYY-MM-DD').
  Future<void> setPingDay(String day) async {
    await load();
    if (_pingDay == day) return;
    _pingDay = day;
    await _persist();
  }

  /// Remember the link that just opened the app.
  Future<void> setLastOpen(LastOpen open) async {
    await load();
    _lastOpen = open;
    await _persist();
  }

  /// The server refused [refused] (404 or 410: a paused, expired,
  /// deleted or unknown link), so the open before it, [previous], stands
  /// again, unless a newer open has replaced [refused] meanwhile.
  Future<void> undoLastOpen(LastOpen refused, LastOpen? previous) async {
    await load();
    if (!identical(_lastOpen, refused)) return;
    _lastOpen = previous;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final file = await _fileRef();
      await file.writeAsString(
        jsonEncode({
          if (_customerId != null) 'customer_id': _customerId,
          if (_enabled != null) 'enabled': _enabled,
          if (_installId != null) 'install_id': _installId,
          if (_lastIdentify != null) 'last_identify': _lastIdentify,
          if (_lastOpen != null) 'last_open': _lastOpen!.toJson(),
          if (_pingDay != null) 'ping_day': _pingDay,
        }),
      );
    } catch (_) {}
  }
}
