/// What the SDK may collect, declared in one place.
///
/// Pass a set as `AdtoConfig.collect` to say exactly what this build
/// collects: a value left out is never collected, whatever the dashboard
/// says. Leave `collect` null for the defaults: [deviceTier] on, [pasteboard]
/// and [oemReferrers] as set on the dashboard's Apps page (else the pasteboard
/// read on iOS only, the OEM referrers on), [appleSearchAdsToken] off, and
/// [adId] only when an `advertisingIdProvider` is given.
///
/// Each value names the store disclosures it triggers; the full table is on
/// https://docs.adto.app/sdk/device-data-and-privacy/.
enum AdtoCollection {
  /// The device tier: a device id (IDFV / ANDROID_ID), model, manufacturer,
  /// CPU, OS build, screen, connectivity and carrier, and the settings: text
  /// size and Increase Contrast (iOS only), dark mode and Reduce Motion
  /// (Android: Remove animations). Apple: Device ID, Product Interaction.
  /// Play Data safety: Device or other IDs, App activity.
  deviceTier,

  /// The first-launch pasteboard read for a copied AdTo link (iOS 16+
  /// shows the paste alert). Apple: no required-reason API; Play: the
  /// Android 12+ clipboard notice.
  pasteboard,

  /// The Huawei, Samsung, Xiaomi and vivo store referrers (Android). No
  /// Data safety type of its own: the store's referrer for this install.
  oemReferrers,

  /// The Apple Search Ads attribution token (AdServices, iOS 14.3+). No
  /// IDFA, no prompt. Apple: Advertising Data, used for app functionality /
  /// developer advertising.
  appleSearchAdsToken,

  /// The advertising identifier (IDFA after the ATT prompt, GAID), read by
  /// the separate `flutter_adto_adid` package through
  /// `AdtoConfig.advertisingIdProvider`. Apple: Device ID used for
  /// tracking unless your use is first-party only; Play: Advertising ID and
  /// the AD_ID permission. The core package never links AdSupport,
  /// AppTrackingTransparency or Play services ads.
  adId,
}

/// An advertising identifier as `flutter_adto_adid` reads it.
class AdtoAdvertisingId {
  const AdtoAdvertisingId({this.id, this.limited = false});

  /// The IDFA or GAID; null when [limited].
  final String? id;

  /// The user limited ad tracking (Android opt-out or deleted id, iOS ATT
  /// not authorized). The SDK then sends no id, only the flag.
  final bool limited;
}

/// Reads the advertising identifier; `flutter_adto_adid` provides one.
typedef AdvertisingIdProvider = Future<AdtoAdvertisingId?> Function();
