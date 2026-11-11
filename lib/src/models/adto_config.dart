import 'adto_collection.dart';
import 'adto_environment.dart';

/// Signature of a callback that returns the raw Google Play Install
/// Referrer string, for example via the `android_play_install_referrer`
/// package. Return null when the referrer is unavailable.
typedef InstallReferrerProvider = Future<String?> Function();

/// Configuration for initializing Flutter AdTo
class AdtoConfig {
  /// An SDK key (`dtg_pub_…`, dashboard Settings → SDK keys). It reports
  /// installs, clicks and events, reads links and makes temporary links;
  /// creating or changing links needs a key with the links:write option.
  /// Never ship the account key (`dtg_…`): it can delete links.
  final String apiKey;

  /// The API base URL. When omitted the SDK talks to AdTo at
  /// https://app.adto.app. An account on the old DecTog service sets
  /// `https://app.dectog.com` (with [linkRootDomain] `dectog.com`).
  final String? baseUrl;

  /// Whether to enable debug logging
  final bool enableDebugLogging;

  /// Optional override for how the Google Play Install Referrer is read
  /// (Android only).
  ///
  /// By default the SDK reads the referrer itself through its own native
  /// reader (Adjust-style retries, every store the device offers);
  /// when an install came through an AdTo Play Store redirect, the
  /// referrer carries the click identifier, which makes deferred deep link
  /// attribution deterministic instead of relying on the server side IP
  /// fingerprint. Supply this callback only if you need a custom referrer
  /// source; returning null (or Play's organic marker) reports an organic
  /// install and the backend falls back to fingerprint matching.
  final InstallReferrerProvider? installReferrerProvider;

  /// How long the first-launch install registration waits for the install
  /// referrer before shipping without it (default 5 s). A referrer that
  /// arrives later — in this process or on a later launch — is sent as a
  /// late claim and upgrades the stored verdict (Adjust re-reads the
  /// referrer every session until it is delivered; AppsFlyer's
  /// `setDeepLinkTimeout` defaults to 3 s). Android only.
  final Duration installReferrerTimeout;

  /// Facebook App ID (optional). When set, the Android SDK also
  /// queries Meta's on-device install-referrer providers (the Facebook /
  /// Instagram / Facebook-Lite apps) for THIS app id and sends the result as
  /// an extra deterministic attribution signal. iOS has no equivalent.
  /// Null (the default) takes the Facebook App ID saved for the app in the
  /// dashboard.
  final String? fbAppId;

  /// Persist the iOS device id across uninstall/reinstall (default
  /// **true**). The first IDFV the SDK reads is stored in the Keychain
  /// (this-device-only) and reused, so a reinstall keeps its device_id and
  /// is reported as a reinstall rather than a new device. Set to `false`
  /// to send the plain IDFV, which changes on reinstall. No effect on
  /// Android, where `ANDROID_ID` already survives reinstall for the same
  /// signing key. Only applies when the device tier is collected; declare the
  /// persisted identifier in your App Store privacy answers.
  final bool persistDeviceId;

  /// What this build collects. Null (the default): the device tier,
  /// the pasteboard and OEM referrers as set on the dashboard (else the
  /// pasteboard read on iOS only and the OEM referrers on), no Apple Search
  /// Ads token, and the advertising id only when [advertisingIdProvider] is
  /// given. A set is exact: what it leaves out is never collected, whatever
  /// the dashboard says. See [AdtoCollection] for what each value sends
  /// and the store disclosures it triggers.
  ///
  /// On iOS 16+ the pasteboard read shows the system "Allow paste from …?"
  /// alert, but only when the pasteboard holds a URL (a silent check runs
  /// first). Call `FlutterAdto().willShowPasteboardPrompt()` before
  /// `initialize()` to explain it to the user first. Only an AdTo link that
  /// names a click is ever sent.
  final Set<AdtoCollection>? collect;

  /// Reads the advertising identifier; pass
  /// `AdtoAdId.provider` from the separate `flutter_adto_adid` package.
  /// The core package never reads it.
  final AdvertisingIdProvider? advertisingIdProvider;

  /// Whether collection is on before the app has called
  /// `setEnabled` (default true). Pass false to wait for the user's
  /// consent: until `setEnabled(true)` the SDK makes no request of its own
  /// and never reads the pasteboard, holds events on the device, and keeps
  /// the click and open of a link that opened the app to report on
  /// consent. Links still reach `onLinkClick`. The app's `setEnabled`
  /// choice is stored and wins over this value on every later launch.
  final bool enabled;

  /// A check, not a switch: [apiKey] alone decides which account (live or
  /// test) gets the data, and this field changes nothing at runtime.
  ///
  /// The environment this build's [apiKey] should belong to, for example
  /// `test` in debug builds that use the test environment's key. When the app
  /// calls `diagnostics()`, it warns if the key belongs to the other one.
  /// Null (the default): no check, except that a release build with a test
  /// key warns.
  final AdtoEnvironment? environment;

  const AdtoConfig({
    required this.apiKey,
    this.baseUrl,
    this.linkRootDomain,
    this.linkDomains = const [],
    this.enableDebugLogging = false,
    this.installReferrerProvider,
    this.installReferrerTimeout = const Duration(seconds: 5),
    this.collect,
    this.advertisingIdProvider,
    this.fbAppId,
    this.persistDeviceId = true,
    this.enabled = true,
    this.environment,
  });

  /// Whether [value] is collected: the set when given, else [fallback].
  bool _has(AdtoCollection value, bool fallback) =>
      collect == null ? fallback : collect!.contains(value);

  /// The device tier (device id, hardware, screen, network, carrier).
  bool get collectsDeviceTier => _has(AdtoCollection.deviceTier, true);

  /// The Apple Search Ads attribution token.
  bool get collectsAppleSearchAdsToken =>
      _has(AdtoCollection.appleSearchAdsToken, false);

  /// The advertising id, which also needs an [advertisingIdProvider].
  bool get collectsAdId =>
      advertisingIdProvider != null && _has(AdtoCollection.adId, true);

  /// The pasteboard read as this build sets it; null leaves it to the
  /// dashboard, then the platform default.
  bool? get pasteboardSetting =>
      collect == null ? null : collect!.contains(AdtoCollection.pasteboard);

  /// The OEM store referrers as this build sets them; null leaves them to
  /// the dashboard, then on.
  bool? get oemReferrersSetting =>
      collect == null ? null : collect!.contains(AdtoCollection.oemReferrers);

  /// Hosted AdTo: the API lives on `app.adto.app`, links on
  /// `{username}.adto.app`.
  static const String defaultBaseUrl = 'https://app.adto.app';
  static const String defaultLinkRootDomain = 'adto.app';

  /// Get the effective base URL (trailing slashes stripped)
  String get effectiveBaseUrl {
    final b = baseUrl?.trim().replaceAll(RegExp(r'/+$'), '');
    return (b == null || b.isEmpty) ? defaultBaseUrl : b;
  }

  /// Root domain that tenant link subdomains hang off
  /// (`{username}.$linkRootDomain/{slug}`). Defaults to `adto.app` when
  /// [baseUrl] is unset, else to the host of [baseUrl]; set it when the
  /// links live on a different host than the API (the old DecTog service:
  /// API at `app.dectog.com`, links at `{username}.dectog.com`).
  final String? linkRootDomain;

  /// The account's custom link domains (`go.yourbrand.com`), whose
  /// links are `https://go.yourbrand.com/{slug}`. The SDK also learns the
  /// active one from the server; listing it here makes a link that opens
  /// the app before the first server answer work too. Add the same hosts to
  /// the Associated Domains and the Android intent filter.
  final List<String> linkDomains;

  /// Effective link root domain (trailing dots stripped), or null to use
  /// the API host.
  String? get effectiveLinkRootDomain {
    final d = linkRootDomain?.trim().replaceAll(RegExp(r'[.]+$'), '') ?? '';
    if (d.isNotEmpty) return d;
    final b = baseUrl?.trim() ?? '';
    return b.isEmpty ? defaultLinkRootDomain : null;
  }

  /// Whether the first-launch pasteboard read runs on the given platform:
  /// [value] when set, else the platform default (iOS on, Android and
  /// desktop off).
  static bool resolveReadClipboard(bool? value, {required bool isIOS}) =>
      value ?? isIOS;

  /// The pasteboard read as this build alone resolves it (no dashboard).
  bool readClipboardFor({required bool isIOS}) =>
      resolveReadClipboard(pasteboardSetting, isIOS: isIOS);

  @override
  String toString() {
    final key = apiKey.length > 8 ? '${apiKey.substring(0, 8)}...' : '***';
    return 'AdtoConfig(apiKey: $key, baseUrl: $effectiveBaseUrl, '
        'linkRoot: ${effectiveLinkRootDomain ?? '(api host)'}, '
        'linkDomains: ${linkDomains.isEmpty ? '-' : linkDomains.join(',')}, debug: $enableDebugLogging, '
        'referrerTimeout: ${installReferrerTimeout.inMilliseconds}ms, '
        'collect: ${collect == null ? 'defaults' : collect!.map((c) => c.name).join(',')}, '
        'adId: ${advertisingIdProvider != null})';
  }
}
