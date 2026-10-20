import 'dart:async';

import 'package:flutter/services.dart';

/// The SDK's only authored platform channel: consent-tier identifiers,
/// carrier info and the install-referrer readers, the
/// backup-excluded storage location, package/install provenance, the
/// pasteboard and the launch intent.
///
/// Native implementations (android/, ios/):
///  - getDeviceId({persist}) → String | null
///      Android: Settings.Secure.ANDROID_ID (persist ignored). iOS: the
///      IDFV (identifierForVendor). With persist: true (the default via
///      DectogConfig.persistDeviceId) it is kept in the Keychain and
///      survives reinstall; otherwise the plain IDFV changes on reinstall.
///  - getCarrierInfo → { mcc: String, mnc: String } | null (Android only)
///  - getWebViewUserAgent → String | null (Android only)
///  - getMetaReferrer(fbAppId) → { referrer, ts?, isCt? } | null (Android)
///
/// Contract v2 (attribution reliability plan, "Method channel additions"):
///  - getInstallReferrers({timeoutMs, stores}) → { "<store>": {...} }
///      Android. One entry per attempted store (google_play, huawei, samsung,
///      xiaomi, vivo): status, referrer?, clickTs?, installBeginTs?,
///      clickServerTs?, installBeginServerTs?, installVersion?, instant?,
///      attempts, waitMs, error?. The Play reader retries like Adjust (3 × 3 s
///      on transient errors) — the plugin never gives up on the first
///      SERVICE_UNAVAILABLE.
///  - getNoBackupDirectory → String (Android noBackupFilesDir)
///  - getPackageInstallInfo → { firstInstallTime, lastUpdateTime, installer?, versionCode } (ms)
///  - getLaunchInfo → { referrer?, fromHistory, hasIntentData } | null
///  - pasteboardHasUrl → bool (silent check) · readPasteboardUrl → String?
///    (iOS 16+ shows the system paste alert) · clearPasteboard → bool
///  - getInstallDates → { executableCtime?, libraryCtime?, documentsCtime?,
///    keychainFirstInstall?, keychainLatestInstall? } (iOS, ms)
///  - excludeFromBackup({path}) → bool (iOS)
///  - getAttributionToken → String? (iOS 14.3+, AdServices)
///  - native → Dart: onPasteControlUrl({url}) from the UIPasteControl view.
///
/// Every call returns null/false on unsupported platforms, on
/// PlatformException and on MissingPluginException (a native side that
/// has not shipped the method yet) — enrichment must never break install
/// tracking.
class IdentifierChannel {
  IdentifierChannel._internal();
  static final IdentifierChannel _instance = IdentifierChannel._internal();
  factory IdentifierChannel() => _instance;

  static const MethodChannel _channel = MethodChannel(
    'dectog_device_identifiers',
  );

  final StreamController<String> _pasteControl =
      StreamController<String>.broadcast();
  bool _handlerInstalled = false;

  /// URLs the native paste control (UIPasteControl) handed us. Installing
  /// the native→Dart handler needs a live binding, so it happens lazily on
  /// first access (or via [ensurePasteControlHandler]).
  Stream<String> get onPasteControlUrl {
    ensurePasteControlHandler();
    return _pasteControl.stream;
  }

  /// Install the handler for calls FROM the platform side. Idempotent.
  void ensurePasteControlHandler() {
    if (_handlerInstalled) return;
    try {
      _channel.setMethodCallHandler(_handleNativeCall);
      _handlerInstalled = true;
    } catch (_) {
      // No binding yet (called before runApp) — the next access retries.
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onPasteControlUrl':
        final url =
            (call.arguments is Map
                    ? (call.arguments as Map)['url']
                    : call.arguments)
                ?.toString()
                .trim() ??
            '';
        if (url.isNotEmpty) _pasteControl.add(url);
        return null;
      default:
        throw MissingPluginException(
          '${call.method} is not handled by the Dart side',
        );
    }
  }

  // ---- helpers -----------------------------------------------------------

  /// One channel call that degrades to null on every failure.
  Future<T?> _invoke<T>(String method, [dynamic arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _str(Object? value) {
    final s = value?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static int? _int(Object? value) {
    if (value is num) {
      final n = value.toInt();
      return n > 0 ? n : null;
    }
    if (value is String) {
      final n = int.tryParse(value.trim());
      return n != null && n > 0 ? n : null;
    }
    return null;
  }

  static bool? _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return null;
  }

  // ---- identifiers ----------------------------------------

  /// First-party device identifier (ANDROID_ID / IDFV). [persist] asks iOS
  /// to keep the IDFV in the Keychain so it survives reinstall.
  Future<String?> getDeviceId({bool persist = false}) async =>
      _str(await _invoke<String>('getDeviceId', {'persist': persist}));

  /// Mobile country/network code of the current carrier (Android only).
  Future<CarrierInfo?> getCarrierInfo() async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getCarrierInfo');
    if (raw == null) return null;
    final mcc = _str(raw['mcc']);
    final mnc = _str(raw['mnc']);
    if (mcc == null) return null;
    return CarrierInfo(mcc: mcc, mnc: mnc);
  }

  /// The device's WebView User-Agent (Android only). Null on iOS.
  Future<String?> getWebViewUserAgent() async =>
      _str(await _invoke<String>('getWebViewUserAgent'));

  /// Meta's on-device install referrer for [fbAppId] (Android only): what
  /// the Facebook / Instagram / Facebook-Lite app recorded as the install
  /// source for this app, with its timestamp. Null when no provider has
  /// data (FB apps absent, no ad click recorded, or non-Android).
  Future<MetaReferrer?> getMetaReferrer(String fbAppId) async {
    if (fbAppId.trim().isEmpty) return null;
    final raw = await _invoke<Map<dynamic, dynamic>>('getMetaReferrer', {
      'fbAppId': fbAppId.trim(),
    });
    if (raw == null) return null;
    final referrer = _str(raw['referrer']);
    if (referrer == null) return null;
    return MetaReferrer(
      referrer: referrer,
      ts: (raw['ts'] as num?)?.toInt(),
      isCt: raw['isCt'] as bool?,
    );
  }

  // ---- install referrers --------------------------------------------

  /// Every store's install referrer the native side could read, keyed by
  /// store id. Null when the platform has no reader (iOS, old native).
  Future<Map<String, StoreReferrer>?> getInstallReferrers({
    required int timeoutMs,
    required List<String> stores,
  }) async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getInstallReferrers', {
      'timeoutMs': timeoutMs,
      'stores': stores,
    });
    if (raw == null) return null;
    final out = <String, StoreReferrer>{};
    for (final entry in raw.entries) {
      final store = entry.key?.toString() ?? '';
      final value = entry.value;
      if (store.isEmpty || value is! Map) continue;
      out[store] = StoreReferrer.fromMap(store, value);
    }
    return out;
  }

  // ---- storage + provenance -----------------------------------------

  /// Android `Context.getNoBackupFilesDir()`; null elsewhere.
  Future<String?> getNoBackupDirectory() async =>
      _str(await _invoke<String>('getNoBackupDirectory'));

  /// PackageManager install provenance (Android); null elsewhere.
  Future<PackageInstallInfo?> getPackageInstallInfo() async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getPackageInstallInfo');
    if (raw == null) return null;
    return PackageInstallInfo(
      firstInstallTime: _int(raw['firstInstallTime']),
      lastUpdateTime: _int(raw['lastUpdateTime']),
      installer: _str(raw['installer']),
      versionCode: (raw['versionCode'] as num?)?.toInt(),
    );
  }

  /// The launching intent's provenance (Android): `Activity.getReferrer()`
  /// and whether the task was re-launched from recents (history), in which
  /// case the intent data is a stale replay (Branch's
  /// FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY guard). Null without an activity.
  Future<LaunchInfo?> getLaunchInfo() async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getLaunchInfo');
    if (raw == null) return null;
    return LaunchInfo(
      referrer: _str(raw['referrer']),
      fromHistory: _bool(raw['fromHistory']) ?? false,
      hasIntentData: _bool(raw['hasIntentData']) ?? false,
    );
  }

  /// iOS install dates (Branch's four-timestamp model), epoch ms. The
  /// native side writes the keychain first-install date on first sight.
  Future<InstallDates?> getInstallDates() async {
    final raw = await _invoke<Map<dynamic, dynamic>>('getInstallDates');
    if (raw == null) return null;
    return InstallDates(
      executableCtime: _int(raw['executableCtime']),
      libraryCtime: _int(raw['libraryCtime']),
      documentsCtime: _int(raw['documentsCtime']),
      keychainFirstInstall: _int(raw['keychainFirstInstall']),
      keychainLatestInstall: _int(raw['keychainLatestInstall']),
    );
  }

  /// iOS: set NSURLIsExcludedFromBackupKey on [path]. False on failure.
  Future<bool> excludeFromBackup(String path) async =>
      await _invoke<bool>('excludeFromBackup', {'path': path}) ?? false;

  /// iOS 14.3+: the AdServices attribution token (Apple Search Ads). Null
  /// when unavailable, denied or on Android.
  Future<String?> getAttributionToken() async =>
      _str(await _invoke<String>('getAttributionToken'));

  // ---- pasteboard ----------------------------------------------------

  /// Silent check whether the pasteboard holds a URL (`UIPasteboard.hasURLs`
  /// on iOS — no alert; best effort on Android).
  Future<bool> pasteboardHasUrl() async =>
      await _invoke<bool>('pasteboardHasUrl') ?? false;

  /// The pasteboard's URL/text. On iOS 16+ this is what shows the system
  /// "Allow paste" alert — only call it after [pasteboardHasUrl].
  Future<String?> readPasteboardUrl() async =>
      _str(await _invoke<String>('readPasteboardUrl'));

  /// Clear the pasteboard (after a DecTog link was credited, like Branch's
  /// NativeLink). False on failure.
  Future<bool> clearPasteboard() async =>
      await _invoke<bool>('clearPasteboard') ?? false;

  /// The pasteboard's change counter (`UIPasteboard.changeCount`; the
  /// primary clip's description timestamp on Android 8+), read without
  /// touching the content. Null when unavailable.
  Future<int?> pasteboardChangeCount() async =>
      await _invoke<int>('pasteboardChangeCount');

  /// iOS: the URL schemes in Info.plist CFBundleURLTypes.
  Future<List<String>> getUrlSchemes() async =>
      ((await _invoke<List<Object?>>('getUrlSchemes')) ?? const [])
          .whereType<String>()
          .toList();

  /// Android 12+: App Links verification state per declared host:
  /// `verified`, `none` (not verified), `selected` (user-approved) or another
  /// DomainVerificationUserState name. Null below Android 12.
  Future<Map<String, String>?> getDomainVerification() async {
    final raw = await _invoke<Map<Object?, Object?>>('getDomainVerification');
    if (raw == null) return null;
    return {
      for (final e in raw.entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
  }
}

/// One store's install-referrer read.
class StoreReferrer {
  const StoreReferrer({
    required this.store,
    required this.status,
    this.referrer,
    this.clickTs,
    this.installBeginTs,
    this.clickServerTs,
    this.installBeginServerTs,
    this.installVersion,
    this.instant,
    this.attempts = 0,
    this.waitMs = 0,
    this.error,
  });

  /// 'google_play' | 'huawei' | 'samsung' | 'xiaomi' | 'vivo'
  final String store;

  /// Wire status (see [ReferrerStatus] in install_referrer_service.dart).
  final String status;
  final String? referrer;

  /// Device-clock timestamps (epoch ms) as the store reports them.
  final int? clickTs;
  final int? installBeginTs;

  /// Server-side timestamps (epoch ms) — Play only; the ones fraud timing trusts.
  final int? clickServerTs;
  final int? installBeginServerTs;
  final String? installVersion;
  final bool? instant;
  final int attempts;
  final int waitMs;
  final String? error;

  bool get hasReferrer => referrer != null && referrer!.trim().isNotEmpty;

  factory StoreReferrer.fromMap(String store, Map<dynamic, dynamic> m) {
    int? ms(Object? v) => IdentifierChannel._int(v);
    return StoreReferrer(
      store: store,
      status: IdentifierChannel._str(m['status']) ?? 'error',
      referrer: IdentifierChannel._str(m['referrer']),
      clickTs: ms(m['clickTs']),
      installBeginTs: ms(m['installBeginTs']),
      clickServerTs: ms(m['clickServerTs']),
      installBeginServerTs: ms(m['installBeginServerTs']),
      installVersion: IdentifierChannel._str(m['installVersion']),
      instant: IdentifierChannel._bool(m['instant']),
      attempts: (m['attempts'] as num?)?.toInt() ?? 0,
      waitMs: (m['waitMs'] as num?)?.toInt() ?? 0,
      error: IdentifierChannel._str(m['error']),
    );
  }
}

class PackageInstallInfo {
  const PackageInstallInfo({
    this.firstInstallTime,
    this.lastUpdateTime,
    this.installer,
    this.versionCode,
  });

  /// PackageManager.firstInstallTime / lastUpdateTime, epoch ms.
  final int? firstInstallTime;
  final int? lastUpdateTime;
  final String? installer;
  final int? versionCode;
}

class LaunchInfo {
  const LaunchInfo({
    this.referrer,
    required this.fromHistory,
    required this.hasIntentData,
  });

  /// Activity.getReferrer() — the package/URL that launched us.
  final String? referrer;
  final bool fromHistory;
  final bool hasIntentData;
}

class InstallDates {
  const InstallDates({
    this.executableCtime,
    this.libraryCtime,
    this.documentsCtime,
    this.keychainFirstInstall,
    this.keychainLatestInstall,
  });

  final int? executableCtime;
  final int? libraryCtime;
  final int? documentsCtime;
  final int? keychainFirstInstall;
  final int? keychainLatestInstall;
}

class MetaReferrer {
  const MetaReferrer({required this.referrer, this.ts, this.isCt});

  /// The raw referrer string Meta recorded (utm params; a DecTog link
  /// click carries dtg_click inside it).
  final String referrer;

  /// Epoch milliseconds of Meta's click record, when present.
  final int? ts;

  /// Meta's `is_ct`: true for a click-through, false for a view-through,
  /// null when the provider did not report it.
  final bool? isCt;
}

class CarrierInfo {
  const CarrierInfo({required this.mcc, this.mnc});

  final String mcc;
  final String? mnc;
}
