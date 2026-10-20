library flutter_dectog;

import 'dart:async';

import 'src/dectog_impl.dart';
import 'src/models/models.dart';

// Export all models and types
export 'src/models/models.dart';
export 'src/models/dectog_link_extension.dart';
export 'src/widgets/dectog_navigator_observer.dart';
export 'src/widgets/dectog_paste_button.dart';

/// Abstract interface for Flutter DecTog plugin
///
/// This interface provides functionality similar to Firebase Dynamic Links
/// but using your own DecTog backend.
abstract interface class FlutterDectog {
  /// Factory constructor that returns the singleton instance
  factory FlutterDectog() => FlutterDectogImpl.instance;

  /// Initialize the plugin with configuration
  Future<void> initialize(DectogConfig config);

  /// Create a permanent link. Only [slug] is required: a null [target]
  /// inherits the app's fallback URL. The routing, social-preview and
  /// tracking fields match the dashboard's create form.
  Future<DectogLink> createLink({
    required String slug,
    String? target,
    Map<String, dynamic>? metadata,
    String? appId,
    String? iosDeepLinkPath,
    String? androidDeepLinkPath,
    String? redirectUrl,
    String? fallbackUrl,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
    String? label,
    String? campaign,
    String? adgroup,
    String? creative,
  });

  /// Compare this build with the dashboard's record of the app: the
  /// bundle ID or package, the iOS URL scheme in Info.plist, and on Android
  /// 12+ whether the system verified App Links for each link host. Warnings
  /// are also logged with `enableDebugLogging`. Never throws for a setup
  /// problem and never blocks the SDK: it only reports.
  Future<DectogDiagnostics> diagnostics();

  /// The referral link of one of your customers ([customerId], the id
  /// you pass to [identify]). Created on the first call, the same link on
  /// every later one; needs no `links:write` key. A new user who installs
  /// through it and signs up is recorded as their referral, and your webhook
  /// receives `referral.converted`.
  Future<DectogLink> createReferralLink({
    required String customerId,
    String? campaign,
  });

  /// Update a permanent link. A null argument keeps the stored value; pass
  /// `''` to clear a field (e.g. `target: ''` to inherit the app fallback).
  Future<DectogLink> updateLink(
    String slug, {
    String? target,
    Map<String, dynamic>? metadata,
    String? iosDeepLinkPath,
    String? androidDeepLinkPath,
    String? redirectUrl,
    String? fallbackUrl,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
    String? label,
    String? campaign,
    String? adgroup,
    String? creative,
  });

  /// One page of permanent links, newest first. [limit] is 1 to 200
  /// (default 50); pass the previous page's [DectogLinkPage.nextCursor] as
  /// [cursor] for the next one.
  Future<DectogLinkPage> getLinks({int? limit, String? cursor});

  /// Get a specific permanent link by slug
  Future<DectogLink> getLink(String slug);

  /// Delete a permanent link: it stops working and leaves the lists, while
  /// its clicks and the installs, events and app opens attributed to it
  /// stay (the dashboard can restore it). [permanently] also deletes that
  /// history, which cannot be undone.
  Future<void> deleteLink(String slug, {bool permanently = false});

  /// Create a temporary link ([ttlSeconds] is clamped to 60 s – 30 days).
  Future<DectogTempLink> createTempLink({
    String? target,
    String? slug,
    int ttlSeconds = 900,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  });

  /// Update a temporary link (null keeps, `''` clears).
  Future<DectogTempLink> updateTempLink(
    String slug, {
    String? target,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  });

  /// Get a specific temporary link by slug
  Future<DectogTempLink> getTempLink(String slug);

  /// Delete a temporary link, like [deleteLink]: [permanently] also deletes
  /// its recorded data.
  Future<void> deleteTempLink(String slug, {bool permanently = false});

  /// Resolve a link by username and slug (public endpoint)
  Future<DectogLinkResolution> resolveLink(String username, String slug);

  /// Stream of incoming link clicks
  Stream<DectogLinkClick> get onLinkClick;

  /// Stream of app install events
  Stream<DectogAppInstallResponse> get onAppInstalled;

  /// Get the current app install response (if available)
  DectogAppInstallResponse? get currentAppInstall;

  /// Get the initial link if app was opened via a link
  Future<DectogLinkClick?> getInitialLink();

  /// A DecTog link tapped inside the app's own UI, such as a link in
  /// a chat message or a feed. iOS and Android never hand a Universal Link or
  /// an App Link back to the app that shows it, so pass the URL here: it is
  /// routed like a link that opened the app ([onLinkClick] emits it, with
  /// `inApp` true, once), and counted as an app open, not as a click.
  /// Returns null for a URL that is not a DecTog link (open
  /// it yourself) and for an authentication callback.
  Future<DectogLinkClick?> handleUrl(String url);

  /// Bind the app's own user identity to this device's install attribution.
  ///
  /// [customerId] is your user id; [name], [email] and [phone] are optional
  /// and stored server-side with the customer record. Later conversion and
  /// custom events carry the id until [logout].
  ///
  /// The first identify of a new [customerId] on a fresh install (≤ 30 days)
  /// is the customer's 'signup' lead — call it right after signup and login.
  /// Existing users identified for the first time on an older install are
  /// not counted.
  ///
  /// A repeat call with the same [customerId], [name], [email] and [phone]
  /// as the last one is skipped, so calling this on every launch is safe;
  /// changing any field (or a [logout]) sends a new identify.
  Future<void> identify({
    required String customerId,
    String? name,
    String? email,
    String? phone,
  });

  /// Track a revenue conversion; revenue reaches the dashboard's per-link
  /// analytics, converted to the account's currency.
  ///
  /// Pass the store's [transactionId] (and [store]) so a purchase reported
  /// twice, after a restore or a reinstall, counts once. A renewal names the
  /// subscription's first purchase as [originalTransactionId] and is credited
  /// to the same link. Report a refund with [transactionType]
  /// `DectogTransactionType.refund` and the refunded amount as [revenue]; it
  /// is subtracted. A `cancel` (auto-renew turned off) counts nothing.
  ///
  /// On iOS with StoreKit 2, pass the transaction's `jwsRepresentation` as
  /// [appStoreJws] (with `in_app_purchase`, the purchase's
  /// `verificationData.serverVerificationData`): the server verifies Apple's
  /// signature and takes the transaction id, price and currency from it, so
  /// the purchase counts as store-verified.
  Future<void> trackConversion({
    required double revenue,
    String? currency,
    String? eventName,
    String? productId,
    String? transactionId,
    String? originalTransactionId,
    DectogStore? store,
    DectogPurchaseType? purchaseType,
    int? quantity,
    String? appStoreJws,
    DectogTransactionType transactionType = DectogTransactionType.purchase,
    Map<String, dynamic>? metadata,
  });

  /// Track a custom event.
  Future<void> trackEvent(String eventName, {Map<String, dynamic>? data});

  /// Report a screen the app showed: the dashboard lists the screens
  /// people reached after a link opened the app. Screen views count in no
  /// event total. [name] is cut to 200 characters; [params] keeps only
  /// strings (cut to 256 characters), finite numbers and booleans. Keep
  /// personal data out of both. `DectogNavigatorObserver` calls this for
  /// every page route.
  Future<void> trackScreenView(String name, {Map<String, Object?>? params});

  /// Force-send the queued events now (they otherwise flush at 20 events
  /// or every 30 seconds).
  Future<void> flush();

  /// Flush queued events and forget the customer identity set by [identify].
  Future<void> logout();

  /// Turn all SDK collection off (false) or back on (true). The choice is
  /// persisted, so it holds across restarts until changed.
  ///
  /// While disabled the SDK records nothing: no click or app-open reports, no
  /// install registration, no late claims, no pasteboard reads, no device
  /// pings, and new events are discarded (the queue is cleared when
  /// disabling). Incoming links are still parsed and delivered to
  /// [onLinkClick]. Enabling again registers the install if it never was:
  /// the store referrer still attributes it deterministically, while the
  /// fingerprint window may have passed.
  Future<void> setEnabled(bool enabled);

  /// Whether collection is enabled (see [setEnabled]). True by default.
  Future<bool> isEnabled();

  /// The install verdict: the cached first-launch response, re-pulled from
  /// GET /api/v1/attribution when the cache is empty (app restarts, a
  /// failed first call). Organic installs come back with `matched: false`;
  /// null only when the server knows no install for this device.
  Future<DectogAppInstallResponse?> getAttributionData();

  /// Whether the first-launch pasteboard read would show the iOS 16+
  /// system "Allow paste" alert on this launch: iOS 16+, the read enabled
  /// for the platform ([collect] stands in for `DectogConfig.collect` before
  /// [initialize]; else the config, the dashboard, then the platform
  /// default), the install not yet registered, and the pasteboard
  /// holding a URL (checked silently). Callable before [initialize], so an
  /// onboarding screen can explain the alert first (Branch's
  /// `willShowPasteboardToast`). Always false on Android.
  Future<bool> willShowPasteboardPrompt({Set<DectogCollection>? collect});

  /// Dispose resources
  Future<void> dispose();
}
