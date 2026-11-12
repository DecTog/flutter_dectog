<!-- The source of https://docs.adto.app/sdk/api-reference/ (synced by the docs repo's
     npm run sync:sdk-reference) and of llms.txt (dart run tool/gen_llms.dart). Edit here,
     with the code; test/llms_test.dart fails when a public member is missing. -->

# flutter_adto API reference

Everything below is exported by `package:flutter_adto/flutter_adto.dart`. Nullable types are marked with `?`. Methods on `FlutterAdto` throw `AdtoError` on failure; a method called before `initialize` throws a `configuration` error.

## FlutterAdto

`abstract interface class FlutterAdto`. The factory `FlutterAdto()` returns the process-wide singleton.

### Lifecycle

| Member | Signature | Notes |
|---|---|---|
| `initialize` | `Future<void> initialize(AdtoConfig config)` | Once per process. Throws `configuration` when called twice; a failed call can be retried. Resolves after the cold-start link and, on the first launch, the install registration. |
| `dispose` | `Future<void> dispose()` | Cancels link listening, closes both streams, flushes the event queue, closes the HTTP client. The SDK cannot be initialized again afterwards. |

### Links

| Member | Signature | Endpoint |
|---|---|---|
| `onLinkClick` | `Stream<AdtoLinkClick> get onLinkClick` | Broadcast stream. Emits for links opened while running and for the cold-start link. |
| `getInitialLink` | `Future<AdtoLinkClick?> getInitialLink()` | The link that launched the app, consumed once per process; `null` without one or after a relaunch from the Android recents screen. |
| `handleUrl` | `Future<AdtoLinkClick?> handleUrl(String url)` | An AdTo link tapped inside the app's own UI (chat, feed), which the system never hands back to the app: routed like an incoming link (`onLinkClick` emits it once, `inApp: true`) and counted as an app open, not a click. `null` for a URL that is not an AdTo link, and for an authentication callback. |
| `resolveLink` | `Future<AdtoLinkResolution> resolveLink(String username, String slug)` | `GET /api/v1/resolve/{username}/{slug}`, public, unsigned. |

### Link management

| Member | Signature | Endpoint |
|---|---|---|
| `createLink` | `Future<AdtoLink> createLink({required String slug, String? target, Map<String, dynamic>? metadata, String? appId, String? iosDeepLinkPath, String? androidDeepLinkPath, String? redirectUrl, String? fallbackUrl, String? ogTitle, String? ogDescription, String? ogImageUrl, String? label, String? campaign, String? adgroup, String? creative})` | `POST /api/v1/links`, expects 201 |
| `createReferralLink` | `Future<AdtoLink> createReferralLink({required String customerId, String? campaign})` | `POST /api/v1/referral-links`; 201 the first time, 200 with the same link afterwards. Works with a plain SDK key. A new user who installs through it and signs up is recorded as the customer's referral. On that user's device, `install.link?.referrerCustomerId` (in `onAppInstalled` and `getAttributionData()`) names the customer; a reinstall (`install.isReinstall`) never records a referral. See [Referral programs](https://docs.adto.app/guides/referral-programs/). |
| `updateLink` | `Future<AdtoLink> updateLink(String slug, {String? target, Map<String, dynamic>? metadata, String? iosDeepLinkPath, String? androidDeepLinkPath, String? redirectUrl, String? fallbackUrl, String? ogTitle, String? ogDescription, String? ogImageUrl, String? label, String? campaign, String? adgroup, String? creative})` | `PUT /api/v1/links/{slug}`. `null` keeps, `''` clears. |
| `getLinks` | `Future<AdtoLinkPage> getLinks({int? limit, String? cursor})` | `GET /api/v1/links`; one page, newest first. `AdtoLinkPage` has `links`, `nextCursor` (pass it back as `cursor`) and `hasMore`. |
| `getLink` | `Future<AdtoLink> getLink(String slug)` | `GET /api/v1/links/{slug}` |
| `deleteLink` | `Future<void> deleteLink(String slug, {bool permanently = false})` | `DELETE /api/v1/links/{slug}`. The link stops working and leaves the lists; its clicks and the installs, events and app opens attributed to it stay, and the dashboard can restore it. `permanently: true` also deletes that history. |
| `createTempLink` | `Future<AdtoTempLink> createTempLink({String? target, String? slug, int ttlSeconds = 900, String? ogTitle, String? ogDescription, String? ogImageUrl})` | `POST /api/v1/temp-links`, expects 201. TTL clamped to 60 seconds to 30 days. |
| `updateTempLink` | `Future<AdtoTempLink> updateTempLink(String slug, {String? target, String? ogTitle, String? ogDescription, String? ogImageUrl})` | `PUT /api/v1/temp-links/{slug}` |
| `getTempLink` | `Future<AdtoTempLink> getTempLink(String slug)` | `GET /api/v1/temp-links/{slug}` |
| `deleteTempLink` | `Future<void> deleteTempLink(String slug, {bool permanently = false})` | `DELETE /api/v1/temp-links/{slug}`, like `deleteLink` |

### Install attribution

| Member | Signature | Notes |
|---|---|---|
| `onAppInstalled` | `Stream<AdtoAppInstallResponse> get onAppInstalled` | Replays the latest verdict to late subscribers. Emits the first-launch verdict and every claim that upgraded it. |
| `currentAppInstall` | `AdtoAppInstallResponse? get currentAppInstall` | The latest emitted verdict, or `null`. |
| `getAttributionData` | `Future<AdtoAppInstallResponse?> getAttributionData()` | The cached verdict, else `GET /api/v1/attribution?device_id=` (device tier on) or `?install_id=`. Organic installs come back with `matched: false`; `null` when the server knows no install for this device, or when neither id is available. |
| `willShowPasteboardPrompt` | `Future<bool> willShowPasteboardPrompt({Set<AdtoCollection>? collect})` | Whether this launch's pasteboard read would show the iOS 16 alert. Callable before `initialize`; `collect` stands in for the config's until then. Always `false` on Android. |

### Events

| Member | Signature | Notes |
|---|---|---|
| `identify` | `Future<void> identify({required String customerId, String? name, String? email, String? phone})` | Queues an `identify` event unless identical to the previous one; persists the customer id. |
| `trackConversion` | `Future<void> trackConversion({required double revenue, String? currency, String? eventName, String? productId, String? transactionId, String? originalTransactionId, AdtoStore? store, AdtoPurchaseType? purchaseType, int? quantity, String? appStoreJws, AdtoTransactionType transactionType = AdtoTransactionType.purchase, Map<String, dynamic>? metadata})` | Queues a `conversion` event; `eventName` defaults to `purchase` (or `refund` / `cancel`). With `transactionId` and `store` a purchase reported twice counts once; a renewal names its first purchase as `originalTransactionId` and is credited to the same link; a refund is subtracted, a cancel counts nothing. `appStoreJws` is a StoreKit 2 `jwsRepresentation`: the server verifies it and takes the transaction id, price and currency from it. See [Revenue](#revenue-types). |
| `trackEvent` | `Future<void> trackEvent(String eventName, {Map<String, dynamic>? data})` | Queues a `custom` event. |
| `trackScreenView` | `Future<void> trackScreenView(String name, {Map<String, Object?>? params})` | Queues a `screen_view` event: `name` (trimmed, cut to 200 characters; an empty name sends nothing), the previous screen reported, and `params` reduced to strings (cut to 256 characters), finite numbers and booleans. Screen views count in no event total; the dashboard's **Screens after open** lists what people reached in the 30 minutes after a link opened the app, and a customer's and an install's **Screens** list their app sessions with the screens in each. `AdtoNavigatorObserver` calls it for you. |
| `flush` | `Future<void> flush()` | Sends up to 100 queued events now (`POST /api/v1/events`). |
| `logout` | `Future<void> logout()` | Flushes, then forgets the customer id. |
| `setEnabled` | `Future<void> setEnabled(bool enabled)` | Persisted; until the app first calls it, `AdtoConfig.enabled` decides (default `true`). `false` makes no request of the SDK's own: no click, app-open, install, claim, attribution, settings, resolve or device-ping request, no pasteboard read. Events are held on the device (up to the queue's 7 days), and the click and open of a link that arrives are held in memory. Links are still delivered to `onLinkClick`, as parsed, without `linkResolution`. `true` starts sending: the held events, the install registration if it never was, and the held link reports. A `false` in between drops the held link reports, not the held events. Calls the app makes itself (`createLink`, `getLinks`, `createTempLink`, `resolveLink`, …) still go out. |
| `diagnostics` | `Future<AdtoDiagnostics> diagnostics()` | Compares this build with the dashboard's record of the app (`GET /api/v1/sdk-config`): bundle ID or package, the iOS URL scheme in `CFBundleURLTypes`, and on Android 12+ the App Links verification of each link host. Returns the warnings and logs them with `enableDebugLogging`; never blocks the SDK. |
| `isEnabled` | `Future<bool> isEnabled()` | The stored choice, else `AdtoConfig.enabled`. |

Background calls the SDK makes on its own, none of them while collection is off: `POST /api/v1/clicks` and `POST /api/v1/app-opens` for every recognized link open, `POST /api/v1/app-installs` on the first launch, `POST /api/v1/app-installs/{id}/claim` for late signals, `POST /api/v1/device-ping` on the first initialize of each UTC day with the device tier on (the server keeps one row per device per day), `POST /api/v1/events` for the queue, `GET /api/v1/sdk-config` for the dashboard's settings, and `GET /api/v1/resolve/…` for a link's details.

## AdtoConfig

```dart
const AdtoConfig({
  required String apiKey,
  String? baseUrl,
  String? linkRootDomain,
  List<String> linkDomains = const [],
  bool enableDebugLogging = false,
  InstallReferrerProvider? installReferrerProvider,
  Duration installReferrerTimeout = const Duration(seconds: 5),
  Set<AdtoCollection>? collect,
  AdvertisingIdProvider? advertisingIdProvider,
  String? fbAppId,
  bool persistDeviceId = true,
  bool enabled = true,
  AdtoEnvironment? environment,
})
```

| Member | Type | Meaning |
|---|---|---|
| `apiKey` | `String` | An SDK key (`adto_pub_…`); also the HMAC key for request signing. |
| `baseUrl` | `String?` | The API base. `null` means `https://api.adto.app`. |
| `linkRootDomain` | `String?` | Root domain of tenant links. `null` means `adto.app` when `baseUrl` is unset, else the host of `baseUrl`. |
| `linkDomains` | `List<String>` | The account's custom link domains (`go.yourbrand.com`): `https://<domain>/<slug>` is a link of this key's account. The SDK also learns the active domain from the server (`AdtoSdkConfig.linkHosts`); listing it here covers a link that opens the app before the first server answer. |
| `enableDebugLogging` | `bool` | Print SDK logs. |
| `installReferrerProvider` | `InstallReferrerProvider?` | Custom Play referrer source, Android only. |
| `installReferrerTimeout` | `Duration` | First-launch wait for the Android referrer. |
| `collect` | `Set<AdtoCollection>?` | What this build collects. `null`: the device tier, the pasteboard and OEM referrers as set on the dashboard (else the pasteboard on iOS only, the OEM referrers on), no Apple Search Ads token, the ad id when `advertisingIdProvider` is set. A set is exact: what it leaves out is never collected, whatever the dashboard says. See [Collection](#collection). |
| `advertisingIdProvider` | `AdvertisingIdProvider?` | Reads the IDFA or GAID; pass `AdtoAdId.provider` from `flutter_adto_adid`. The core package never reads it. |
| `fbAppId` | `String?` | Enables Meta's on-device referrer on Android; `null` takes the Facebook App ID saved in the dashboard. |
| `persistDeviceId` | `bool` | Keep the first IDFV in the iOS Keychain. |
| `enabled` | `bool` | Whether collection is on until the app first calls `setEnabled` (default `true`). `false` waits for consent; see `setEnabled`. The app's stored choice wins on every later launch. |
| `environment` | `AdtoEnvironment?` | A check, not a switch: the key alone decides the account, and this changes nothing at runtime. The environment this build's key should belong to, for example `test` in debug builds with the test environment's key; when the app calls `diagnostics()`, it warns if the key belongs to the other one. `null`: no check, except that a release build with a test key warns. See [Environments](#environments). |
| `defaultBaseUrl` | `static const String` | `'https://api.adto.app'` |
| `defaultLinkRootDomain` | `static const String` | `'adto.app'` |
| `effectiveBaseUrl` | `String get` | `baseUrl` with trailing slashes removed, or the default. |
| `effectiveLinkRootDomain` | `String? get` | `linkRootDomain` with trailing dots removed; `adto.app` when both are unset; `null` (use the API host) when only `baseUrl` is set. |
| `collectsDeviceTier` | `bool get` | The device tier is collected: `collect` is `null` or names `deviceTier`. |
| `collectsAppleSearchAdsToken` | `bool get` | `collect` names `appleSearchAdsToken`. |
| `collectsAdId` | `bool get` | `advertisingIdProvider` is set and `collect` is `null` or names `adId`. |
| `pasteboardSetting` | `bool? get` | The pasteboard read as `collect` sets it; `null` defers to the dashboard. |
| `oemReferrersSetting` | `bool? get` | The OEM referrers as `collect` sets them; `null` defers to the dashboard. |
| `resolveReadClipboard` | `static bool resolveReadClipboard(bool? value, {required bool isIOS})` | `value ?? isIOS`. |
| `readClipboardFor` | `bool readClipboardFor({required bool isIOS})` | The read decision for this config alone (no dashboard) on the given platform. |
| `toString` | | Masks the key to its first 8 characters. |

`typedef InstallReferrerProvider = Future<String?> Function();` returns the raw Play referrer string, or `null` when unavailable.

### Environments

`enum AdtoEnvironment { live, test }`: which of an account's two environments a key belongs to. A test environment is a second account, `t-<username>`, with the same apps and link templates (dashboard Settings → Test environment). Put its SDK key in debug builds: their installs, events and links stay out of the live numbers, and its links live on `t-<username>.<root>`, so add that host to the debug build's associated domains. The SDK learns a key's environment from the server (`AdtoSdkConfig.environment`).

### Collection

`enum AdtoCollection` names what the SDK may collect. Each value and the store disclosures it triggers:

| Value | What it sends | Apple privacy (App Privacy answers) | Google Play Data safety |
|---|---|---|---|
| `deviceTier` | Device id (IDFV / `ANDROID_ID`), model, manufacturer, CPU, OS build, screen, connectivity, carrier; the settings: text size and Increase Contrast (iOS only), dark mode and Reduce Motion (Android: Remove animations); the device ping | Device ID (analytics, linked); Product Interaction | Device or other IDs; App activity |
| `pasteboard` | A copied AdTo link that names a click, read once at first launch | None (no required-reason API); iOS 16+ shows the paste alert | None; Android 12+ shows the clipboard notice |
| `oemReferrers` | The Huawei, Samsung, Xiaomi and vivo store referrers (Android) | Not applicable | None of its own: the store's referrer for this install |
| `appleSearchAdsToken` | The AdServices attribution token (iOS 14.3+); no IDFA, no prompt | Advertising Data (developer advertising) | Not applicable |
| `adId` | The IDFA after ATT, or the GAID, from `advertisingIdProvider` | Device ID used for tracking; the ATT prompt | Advertising ID; the `AD_ID` permission |

`class AdtoAdvertisingId` is an id as the provider reads it: `id` (`String?`, `null` when limited) and `limited` (`bool`, default `false`: the user limited ad tracking). A limited id is never sent; the install carries `ad_tracking_limited: true` instead.

`typedef AdvertisingIdProvider = Future<AdtoAdvertisingId?> Function();` reads the id; `null` when the platform has none.

## Link models

### AdtoLink

A permanent link as the API returns it. All fields are `final`; `AdtoLink.fromJson(Map<String, dynamic>)` parses the API shape. Equality compares `id`, `slug`, `target` and `url`.

| Field | Type | Meaning |
|---|---|---|
| `id` | `String` | Server id |
| `slug` | `String` | |
| `target` | `String?` | Web target; `null` inherits the app's fallback URL |
| `url` | `String` | The shareable URL |
| `appId` | `String?` | Owning app; `null` means the account's oldest app |
| `clickCount` | `int` | Lifetime clicks |
| `createdAt` | `DateTime` | |
| `updatedAt` | `DateTime?` | |
| `metadata` | `Map<String, dynamic>?` | Returned as `customParameters` on attributed installs |
| `ogTitle`, `ogDescription`, `ogImageUrl` | `String?` | Social preview overrides |
| `iosDeepLinkPath`, `androidDeepLinkPath` | `String?` | In-app route per platform |
| `redirectUrl` | `String?` | Mobile destination when the app is not installed |
| `fallbackUrl` | `String?` | Desktop destination |
| `label`, `campaign`, `adgroup`, `creative` | `String?` | Tracking defaults for every click |
| `referrerCustomerId` | `String?` | On a referral link, the customer it belongs to |
| `iosTapToStore`, `mobileInterstitial` | `bool?` | This link's iOS tap-to-store page and mobile interstitial; `null` follows the app's setting |
| `appendClickId` | `bool?` | Whether the link adds `adto_click` to its web destinations for `adto.js`; `null` is off |
| `routingRules` | `List<AdtoRoutingRule>?` | Geo and language routing, first match wins; `null` when the link has none |
| `templateId` | `String?` | The template whose defaults fill the fields the link leaves empty |
| `utmSource`, `utmMedium`, `utmCampaign`, `utmTerm`, `utmContent` | `String?` | Added to the link's web destinations, and to clicks whose URL has none |
| `externalId` | `String?` | Your own id for the link, unique in the account |
| `expiresAt`, `expiredUrl` | `DateTime?`, `String?` | When the link expires; past it taps go to `expiredUrl`, or get a 410 page |
| `disabledAt`, `disabledReason` | `DateTime?`, `String?` | Paused since (taps get a 410 page, nothing is recorded), and the owner's note |
| `archivedAt` | `DateTime?` | Filed away in the dashboard; the link keeps working |
| `deletedAt` | `DateTime?` | Deleted; its history stays |

Pausing, expiring and archiving are set from the dashboard, the REST API or the MCP server.

### AdtoRoutingRule

One routing rule of a link (`AdtoLink.routingRules`). A tap that meets the rule's conditions (one of `countries`, one of `languages`, between `startsAt` and `endsAt`, inside its `percent` share of visitors) takes the fields the rule sets instead of the link's; the first matching rule wins, and a tap that matches no rule is routed as usual. Set from the dashboard, the REST API or the MCP server. `AdtoRoutingRule.fromJson` parses the API shape.

| Field | Type | Meaning |
|---|---|---|
| `name` | `String?` | Recorded on each click the rule routes (else "rule N"), to compare variants |
| `countries` | `List<String>?` | ISO 3166 alpha-2 codes, upper case |
| `languages` | `List<String>?` | Primary language tags, lower case, e.g. `de` |
| `percent` | `int?` | An A/B share of visitors, 1 to 100; shares stack in rule order |
| `startsAt`, `endsAt` | `DateTime?` | Scheduled routing: the rule holds from `startsAt` until `endsAt` |
| `target`, `redirectUrl`, `fallbackUrl` | `String?` | The link's destinations this rule replaces |
| `iosDeepLinkPath`, `androidDeepLinkPath` | `String?` | The in-app routes this rule replaces |

### AdtoLinkPage

One page of `getLinks`, newest first. `AdtoLinkPage.fromJson` parses the API's `{"data": [...], "next_cursor": ...}` envelope.

| Field | Type | Meaning |
|---|---|---|
| `links` | `List<AdtoLink>` | The links on this page |
| `nextCursor` | `String?` | Pass to `getLinks(cursor:)` for the next page; `null` on the last one |
| `hasMore` | `bool get` | `nextCursor != null` |

### AdtoTempLink

| Field | Type | Meaning |
|---|---|---|
| `id`, `slug`, `url` | `String` | |
| `target` | `String?` | `null` inherits the app's fallback URL |
| `expiresAt`, `createdAt` | `DateTime` | |
| `ttlSeconds` | `int?` | |
| `ogTitle`, `ogDescription`, `ogImageUrl` | `String?` | |
| `expiredUrl`, `disabledAt`, `disabledReason`, `archivedAt`, `deletedAt` | `String?` / `DateTime?` | Lifecycle, as on `AdtoLink` |
| `isExpired` | `bool get` | `DateTime.now()` is after `expiresAt` |
| `timeUntilExpiration` | `Duration get` | Zero once expired |

`AdtoTempLink.fromJson` parses the API shape. Equality compares `id`, `slug`, `target` and `url`.

### AdtoLinkResolution

The public resolve result, for permanent and temporary links. Only a live link resolves: `resolveLink` throws `AdtoError` with code `link_paused` or `link_expired` (410) for a paused or expired one, and `not_found` for a deleted one.

| Field | Type | Meaning |
|---|---|---|
| `id`, `slug`, `url` | `String` | |
| `target` | `String?` | |
| `type` | `String` | `'permanent'` or `'temporary'` |
| `createdAt` | `DateTime` | |
| `clickCount` | `int?` | Permanent links only |
| `expiresAt` | `DateTime?` | Temporary links, and permanent links given an expiry |
| `ttlSeconds` | `int?` | Temporary links only |
| `metadata` | `Map<String, dynamic>?` | Permanent links only |
| `iosDeepLinkPath`, `androidDeepLinkPath` | `String?` | Permanent links only |
| `deepLinkPath` | `String? get` | The running platform's path: on iOS the iOS path, elsewhere the Android path, each falling back to the other |
| `isPermanent`, `isTemporary` | `bool get` | |
| `timeUntilExpiration` | `Duration? get` | `null` without `expiresAt` |
| `toAdtoLink` | `AdtoLink? toAdtoLink()` | `null` for temporary links |
| `toAdtoTempLink` | `AdtoTempLink? toAdtoTempLink()` | `null` for permanent links or without `expiresAt` |

### AdtoLinkClick

| Field | Type | Meaning |
|---|---|---|
| `originalUrl` | `String` | The URL that opened the app (`'unknown'` when the platform reported an error) |
| `slug`, `username` | `String` | Parsed from the URL; `'unknown'` when parsing failed |
| `receivedAt` | `DateTime` | |
| `error` | `AdtoError?` | Set for non-AdTo URLs, processing failures and calls before `initialize` |
| `linkResolution` | `AdtoLinkResolution?` | Set when the resolve call succeeded |
| `inApp` | `bool` | The link came through `handleUrl`, from the app's own UI |
| `isResolved` | `bool get` | `linkResolution != null && error == null` |
| `targetUrl` | `String? get` | `linkResolution?.target` |
| `linkType` | `String? get` | `linkResolution?.type` |
| `clickParams` | `AdtoClickParams? get` | The `adto_*` parameters of `originalUrl`, or `null` |

Extension `AdtoLinkClickX` on `AdtoLinkClick`: `Map<String, String>? get queryParameters`, `String? queryParameter(String key)`, `String? get path`, `String? get host`, `String? get scheme`, `String? get fragment`, all read from `originalUrl`.

### AdtoClickParams

The per-click `adto_*` overrides.

| Field | Type | Query parameter |
|---|---|---|
| `deepLink` | `String?` | `adto_deeplink` (the route without a scheme on verdicts; the raw value on opened URLs) |
| `label` | `String?` | `adto_label` |
| `campaign` | `String?` | `adto_campaign` |
| `adgroup` | `String?` | `adto_adgroup` |
| `creative` | `String?` | `adto_creative` |
| `tracker` | `String?` | `adto_tracker` |

`bool get isEmpty`, `AdtoClickParams.fromJson(Map<String, dynamic>)` (the server's `click_params` shape), `static AdtoClickParams? fromUri(Uri uri)` (`null` when the URL carries none), `Map<String, dynamic> toJson()`.

## Install models

### AdtoAppInstallResponse

The verdict on `onAppInstalled`, `currentAppInstall`, `getAttributionData()` and claim responses. `AdtoAppInstallResponse.fromJson` and `toJson` use the server's snake_case keys.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `matched` | `bool` | | Attribution credit, granted at `guaranteed` or `high` confidence |
| `type` | `String` | | `'organic'` or `'non-organic'` |
| `matchSource` | `String?` | | `'referrer'`, `'clipboard'`, `'fingerprint'` or `null` |
| `referrerSource` | `String?` | | `'google_play'`, `'huawei'`, `'samsung'`, `'xiaomi'`, `'vivo'`, `'meta'` or `null` |
| `matchConfidence` | `String?` | | `'guaranteed'`, `'high'`, `'medium'`, `'low'` or `null` |
| `routing` | `AdtoDeferredRoute?` | | Deferred-routing candidate at `medium` or better |
| `fraudFlags` | `List<String>` | `[]` | Fraud rules the install tripped |
| `username`, `slug` | `String?` | | Set when credited |
| `installId` | `String?` | | The server's install id |
| `clickedAt` | `DateTime?` | | The credited click's time |
| `link` | `AdtoAppInstallLink?` | | The credited permanent link |
| `customParameters` | `Map<String, dynamic>?` | | The credited link's metadata |
| `clickParams` | `AdtoClickParams?` | | The credited click's `adto_*` values |
| `deepLink` | `String?` | | `clickParams?.deepLink`, the route to open |
| `replayed` | `bool` | `false` | The server returned a stored verdict for a known attempt id |
| `isReinstall` | `bool` | `false` | Server or client reinstall detection |
| `installState` | `String?` | | `'install'`, `'reinstall'` or `'update'` |
| `claim` | `String?` | | `'upgraded'`, `'unchanged'` or `'rejected'` on claim responses |
| `claimReason` | `String?` | | `'click_reuse'`, `'click_not_found'`, `'no_signal'`, `'already_deterministic'` or `'stale_click'` |
| `appleSearchAds` | `AdtoAppleSearchAds?` | | `null` until a token was ever sent |
| `lastOpen` | `AdtoAppOpen?` | | Only on attribution re-pulls |

### AdtoDeferredRoute

| Field | Type |
|---|---|
| `username`, `slug` | `String?` |
| `deepLink` | `String?` |
| `clickParams` | `AdtoClickParams?` |
| `confidence` | `String?` (`'guaranteed'`, `'high'` or `'medium'`) |
| `clickedAt` | `DateTime?` |

### AdtoAppInstallLink

| Field | Type |
|---|---|
| `slug`, `url` | `String` |
| `target` | `String?` |
| `createdAt` | `DateTime` |
| `metadata` | `Map<String, dynamic>?` |
| `referrerCustomerId` | `String?`: the customer whose referral link brought the install, else null. Set by the server from the link, never from the tapped URL |

### AdtoAppOpen

| Field | Type |
|---|---|
| `username`, `slug` | `String` |
| `clickId` | `String?` |
| `openedAt` | `DateTime` |

### AdtoAppleSearchAds

| Field | Type | Meaning |
|---|---|---|
| `status` | `String` | `'pending'`, `'resolved'`, `'no_attribution'`, `'invalid'`, `'expired'` or `'failed'` |
| `attribution` | `bool?` | Apple's verdict once answered |
| `resolvedAt` | `DateTime?` | |
| `orgId`, `campaignId`, `adGroupId`, `keywordId`, `adId` | `int?` | Apple Ads ids |
| `conversionType` | `String?` | `'Download'`, `'Redownload'` or `'PreOrder'` |
| `claimType` | `String?` | `'Click'` or `'Impression'` |
| `clickDate`, `impressionDate` | `String?` | Apple's timestamps as sent |
| `countryOrRegion`, `supplyPlacement` | `String?` | |
| `isPending` | `bool get` | `status == 'pending'` |
| `isAttributed` | `bool get` | `attribution == true` |

### AdtoAppInstallRequest and AppInfo

`AdtoAppInstallRequest` is the wire model of the install registration (every field the SDK can send, all optional, `toJson` emits only non-null values). `AppInfo` carries the `package_info_plus` values the SDK reads (`appName`, `packageName`, `version`, `buildNumber`, `buildSignature`, `installerStore`, `installTime`, `updateTime`, with `installTimeMs` and `updateTimeMs` getters). Both are exported so the payload is inspectable, but the SDK builds them itself; you never construct them.

## Revenue types

Arguments of `trackConversion`, sent as their `wire` value.

| Enum | Values (wire) | Meaning |
|---|---|---|
| `AdtoStore` | `appStore` (`app_store`), `play` (`play`) | The store of the transaction. A transaction id is unique per store. |
| `AdtoPurchaseType` | `oneTime` (`one_time`), `subscription` (`subscription`) | What was bought |
| `AdtoTransactionType` | `purchase`, `refund`, `cancel` | A `refund` subtracts its `revenue` from net revenue; a `cancel` (auto-renew turned off) counts nothing |

## App settings

At `initialize` the SDK reads the app's settings from the server (`GET /api/v1/sdk-config`) and caches them for an hour: a launch with a fresh cache makes no request, a first launch waits at most 2.5 seconds (an answer that comes later is still cached for the next launch), a stale cache is refreshed in the background. An explicit `AdtoConfig` value always wins over the server's.

### AdtoSdkConfig

| Field | Type | Meaning |
|---|---|---|
| `appId` | `String` | The app the settings belong to |
| `fbAppId` | `String?` | The Facebook App ID for Meta's install referrer |
| `oemStoreReferrers` | `bool` | Read the OEM store referrers |
| `readClipboardOnInstall` | `bool?` | The pasteboard read; `null` is the platform default |
| `iosTapToStore` | `bool` | Whether the app uses iOS tap-to-store |
| `iosAppScheme`, `androidAppScheme` | `String?` | The custom schemes registered in the dashboard |
| `iosBundleId`, `androidPackage` | `String?` | The identifiers registered in the dashboard |
| `linkHosts` | `List<String>` | The hosts the account's links live on: the active custom domain first, then the default host |
| `username` | `String?` | The account the key belongs to; a link on a custom domain is its |
| `environment` | `AdtoEnvironment` | `test` when the key belongs to a test environment |
| `cacheSeconds` | `int` | How long the SDK keeps them |

### AdtoDiagnostics

| Field | Type | Meaning |
|---|---|---|
| `serverConfig` | `AdtoSdkConfig?` | The settings read, or `null` when the server could not be reached |
| `warnings` | `List<String>` | What does not match; empty when the setup agrees with the dashboard |
| `ok` | `bool get` | `warnings.isEmpty` |

## Errors

### AdtoError

`class AdtoError implements Exception`.

| Field | Type | Meaning |
|---|---|---|
| `message` | `String` | The server's `error.message` for API errors, else the SDK's description |
| `statusCode` | `int?` | HTTP status for API errors |
| `code` | `String?` | The server's `error.code` for API errors, such as `conflict`, `invalid_request`, `rate_limited` or `invalid_signature` ([Errors](https://docs.adto.app/api/overview/#errors)); null otherwise |
| `requestId` | `String?` | The server's `error.request_id`, else the `x-request-id` header; quote it when reporting a problem |
| `type` | `AdtoErrorType` | |
| `details` | `Map<String, dynamic>?` | Every field of the server's `error` object (for example `slug` on a 409); `retry_after_ms` is added when the response carried `Retry-After` |

Factories: `AdtoError.apiError({required String message, required int statusCode, Map<String, dynamic>? details, String? code, String? requestId})`, `AdtoError.fromResponse({required int statusCode, required String body, required String fallbackMessage, String? headerRequestId, Map<String, dynamic> extraDetails})` (parses the server's error envelope), `AdtoError.networkError(String message)`, `AdtoError.configError(String message)`, `AdtoError.linkError(String message)`. `toString()` renders `AdtoError: <message> (Status: <status>, <code>) [request <requestId>] Details: <details>`.

### AdtoErrorType

`api` (HTTP error from the server), `network` (connectivity or the 30-second timeout), `configuration` (not initialized, initialized twice, failed initialization), `linkResolution` (a URL that is not an AdTo link, or link processing failed), `unknown` (reserved).

## Widgets

### AdtoPasteButton

```dart
const AdtoPasteButton({
  Key? key,
  Size size = const Size(200, 44),
  AdtoPasteDisplayMode displayMode = AdtoPasteDisplayMode.iconAndLabel,
  AdtoPasteCornerStyle cornerStyle = AdtoPasteCornerStyle.capsule,
  Color? backgroundColor,
  Color? foregroundColor,
})
```

A `StatelessWidget` hosting Apple's `UIPasteControl` on iOS 16 and newer; it builds an empty `SizedBox` elsewhere. A tap reads the pasteboard without the system alert and, when it holds an AdTo link, sends a late claim (`paste_control`). Statics: `String viewType` (`'adto_paste_control'`), `bool get isSupported` (iOS 16 or newer, never on web), and `debugIsSupportedOverride` for tests.

`enum AdtoPasteDisplayMode { iconAndLabel, iconOnly, labelOnly }`

`enum AdtoPasteCornerStyle { capsule, dynamic, fixed, large, medium, small }`

### AdtoNavigatorObserver

```dart
AdtoNavigatorObserver({
  Set<String> captureParams = const {},
  String? Function(Route<dynamic> route)? nameOf,
  Duration debounce = const Duration(milliseconds: 350),
})
```

A `NavigatorObserver` for `MaterialApp(navigatorObservers: [...])` or `GoRouter(observers: [...])` that calls `trackScreenView` for each page route the navigator shows: on a push, a replace, and the route a pop reveals. Dialogs, sheets and other popup routes are not screens. The name is `nameOf(route)`, else `route.settings.name`; a route with neither is skipped. A screen is reported once it has been on top for `debounce`, so rapid transitions collapse into the one that settles, and the same screen twice in a row is reported once. Only the name is sent unless `captureParams` names route arguments (when `settings.arguments` is a map) to send with it, filtered like `trackScreenView`'s `params`. Reports before `initialize()` are dropped.

## Package version

`flutter_adto` sends `x-adto-sdk: flutter_adto/<version>` on every signed call, and also reports its version in the `User-Agent` header (`AdtoSDK/<version> (<platform>)`) and in the `flutter_plugin_version` metadata of clicks and installs. The version constants are internal (`lib/src/version.dart`) and match `pubspec.yaml`.
