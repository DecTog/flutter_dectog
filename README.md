# Flutter DecTog

A Flutter package for creating and handling dynamic links using your own DecTog backend.

Full documentation: [docs.dectog.com](https://docs.dectog.com) (SDK guide at
[docs.dectog.com/sdk/installation/](https://docs.dectog.com/sdk/installation/)).

For AI coding agents, the package ships [`llms.txt`](llms.txt): every public
type and member, the link URLs the SDK recognizes and the init snippet, in one
file that is available offline in the pub cache. The API reference it is built
from is [`doc/api-reference.md`](doc/api-reference.md).

## Installation

```yaml
dependencies:
  flutter_dectog: ^1.0.0
```

Requirements: Flutter ≥ 3.29 (Dart ≥ 3.7), iOS 15+, Android 7 (API 24)+.
Dependency ranges are kept wide (`app_links` 6–7, `connectivity_plus` 6–7,
`crypto` 3.x, `device_info_plus` 11.2–13, `package_info_plus` 8.3–10,
`http` 1.x, `path_provider` 2.x, `rxdart` 0.27–0.28) so the package drops
into apps that already pin these. On iOS the plugin is a Swift package
(`ios/flutter_dectog`): hosts on Swift Package Manager (Flutter's default
since 3.44) need no extra steps, and hosts that disabled SwiftPM get the same
code through CocoaPods via the podspec.

## Quick Setup

### 1. Get Your API Key

Sign up at [app.dectog.com](https://app.dectog.com/login) and pick a username (your link subdomain). Dashboard → Settings shows your **SDK key** (`dtg_pub_…`): that is the key for the app. The account key (`dtg_…`) is for servers and scripts and never goes in an app.

### 2. Configure Deep Links

**Android** - Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="YOUR_SUBDOMAIN.dectog.com" />
</intent-filter>
```

**iOS** - Add Associated Domains to `ios/Runner/Runner.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>applinks:YOUR_SUBDOMAIN.dectog.com</string>
    </array>
</dict>
</plist>
```

If this file doesn't exist, create it. Also ensure your app is properly signed and the Associated Domains capability is enabled in your Apple Developer account.

### 3. Initialize

```dart
import 'package:flutter_dectog/flutter_dectog.dart';

final dectog = FlutterDectog();

await dectog.initialize(DectogConfig(
  apiKey: 'dtg_pub_your_sdk_key',
  enableDebugLogging: true,
));
```

That is all hosted DecTog needs: the SDK defaults to the API at
`https://app.dectog.com` (`DectogConfig.defaultBaseUrl`) and links on
`{username}.dectog.com`. Set `baseUrl` only when self-hosting, plus
`linkRootDomain` when your self-hosted links live on a different host than
the API:

```dart
await dectog.initialize(DectogConfig(
  apiKey: 'dtg_pub_your_sdk_key',
  baseUrl: 'https://api.example.com',
  linkRootDomain: 'example.com', // links at {username}.example.com
));
```

The example app reads `DECTOG_API_KEY`, `DECTOG_BASE_URL` and
`DECTOG_LINK_ROOT_DOMAIN` from its dart-define env file (see
`env/dev.json.example` and `env/prod.json.example`).

### 4. Handle Links

```dart
// Listen for incoming links
dectog.onLinkClick.listen((linkClick) {
  print('Link: ${linkClick.originalUrl}');
  print('Slug: ${linkClick.slug}');
  
});

// Handle app launch from link
final initialLink = await dectog.getInitialLink();
if (initialLink != null) {
  // Handle same as above
}
```

The SDK logs the in-app click and the app open even when resolving the link
fails. The link that launched the app is consumed **once per process**:
it is processed and emitted once however many times
`getInitialLink()` and `onLinkClick` deliver it, and an Android launch from
the recents screen (which replays the original intent) is ignored. OAuth /
social-login callback URLs (`fb<id>://…`, `com.googleusercontent.apps…`,
anything carrying `access_token` / `id_token`) are never logged or emitted.
Each in-app click is sent with `client_click_time` (when the link arrived)
and, on Android, the launching package (`launch_referrer`).

### 5. Track App Installs

The plugin automatically tracks app installs on first launch. Listen for install attribution events:

```dart
// Listen for app install events
dectog.onAppInstalled.listen((installEvent) {
  if (installEvent.matched) {
    // User installed app after clicking a DecTog link
    print('Install attributed to: ${installEvent.username}/${installEvent.slug}');
    print('Original click time: ${installEvent.clickedAt}');
    
    // Show personalized onboarding or deep link to specific content
    _handleAttributedInstall(installEvent);
  } else {
    // Organic install (no prior link click)
    print('Organic app install');
    _handleOrganicInstall();
  }
});

void _handleAttributedInstall(DectogAppInstallResponse install) {
  // Example: Navigate to the content they were trying to reach
  final route = install.deepLink;        // dec_deeplink on the clicked URL
  final target = install.link?.target;   // null = the app's fallback URL
  // Navigate to route / target or handle accordingly
}
```

**Routing vs credit.** `matched` is attribution *credit*, granted only
at `matchConfidence` `guaranteed` (install referrer, Meta, pasteboard) or
`high`. A probabilistic candidate the server is less sure about still comes
back as `routing` (`DectogDeferredRoute`: `slug`, `deepLink`, `clickParams`,
`confidence`) at `medium` confidence with `matched: false` — use it to route a
new user to the content they tapped (routing is cheap to get wrong, credit is
not; AppsFlyer separates the two the same way). A tie between candidates is
`low` and yields neither.

```dart
dectog.onAppInstalled.listen((install) {
  final route = install.routing?.deepLink ?? install.deepLink;
  if (route != null) _openRoute(route);          // medium or better
  if (install.matched) _creditInstall(install);  // high or guaranteed only
});
```

`onAppInstalled` can emit **more than once**: when a deterministic signal
arrives after the first registration (a Play referrer that was not ready in
time, a pasteboard link pasted via `DectogPasteButton`) the SDK sends a late
claim and re-emits the upgraded verdict (`claim == 'upgraded'`). An app that
reacts to the stream handles both naturally; `currentAppInstall` always holds
the latest verdict.

**What gets tracked:**

- First app launch only (subsequent launches are ignored). The registration
  carries a persisted `install_attempt_id`, so a retried launch can never
  register a second install, and `install_state` (`install` / `reinstall` /
  `update`) — an existing user who merely updated to an SDK build is never
  fingerprint-matched
- Device information (OS, version, timezone and UTC offset, language)
- App information (version, build number, package first-install / update
  times)
- Attribution matching with prior link clicks (if any)
- A device-data tier (on by default, configurable) —
  first-party device ID, hardware (model, manufacturer, CPU ABI, OS
  build), screen metrics, network/carrier, display and accessibility
  settings — see [Device data collection](#device-data-collection)

**Privacy notes:**

- **The device tier is on by default** (`DectogConfig.collect` null, or a
  set naming `DectogCollection.deviceTier`). Every install carries device
  id, hardware, network/carrier and display and accessibility settings
  fields; in-app clicks carry the device id and model. If your flow
  requires opt-in, start with `DectogConfig(enabled: false)` and call
  `setEnabled(true)` once the user consents, and
  declare the collection in your privacy
  policy and store privacy forms (GDPR purpose: analytics / install
  attribution; Play Data safety; App Store privacy labels)
- The device ID is the vendor-scoped identifier — `ANDROID_ID` on
  Android and the IDFV on iOS. By default the first IDFV is kept in the
  iOS Keychain (this-device-only, no iCloud sync), so the device ID
  survives uninstall/reinstall on both platforms and reinstalls are
  detected. Declare this persisted identifier in your App Store privacy
  answers. Set `DectogConfig(persistDeviceId: false)` to send the plain
  IDFV instead; on iOS a reinstall is then reported as a new install of a
  new device ID unless the referrer attributes it
- The core package never reads advertising identifiers (GAID/IDFA): no Play
  services dependency, no `AD_ID` permission, no AdSupport or ATT. The
  separate `flutter_dectog_adid` package reads them for apps that want them
  (see [Advertising ID](#advertising-id-optional)).
  `DectogCollection.appleSearchAdsToken` (off by default) reads Apple's AdServices
  attribution token, which carries no identifier and shows no prompt; the
  server exchanges it with Apple and the result arrives as
  `DectogAppInstallResponse.appleSearchAds` (campaign, ad group, keyword and
  ad ids — `pending` until Apple answers, so check `getAttributionData()` on
  a later launch)
- The SDK's state files live in a backup-excluded directory (Android
  `noBackupFilesDir`, iOS `NSURLIsExcludedFromBackupKey`), so a restored
  backup never suppresses or duplicates an install registration
- All data stays within your DecTog account

#### Device data collection

The install registration is enriched with these tiers, sent as optional
fields. **The tier is on by default**; leave `deviceTier` out of
`DectogConfig(collect: {…})` to turn it off (to wait for consent, use
`DectogConfig(enabled: false)` instead):

| Tier | Fields | Source | Server use |
|---|---|---|---|
| Device ID | `device_id` (Keychain-persisted IDFV / `ANDROID_ID`) | the SDK's own platform channel | install dedupe + reinstall detection |
| Hardware | `device_model`, `device_manufacturer`, `device_kind`, `cpu_type`, `os_build` | [`device_info_plus`](https://pub.dev/packages/device_info_plus) | device/hardware breakdowns |
| Screen | `screen_width`, `screen_height` (view physical px; can differ from the display by the navigation bar — harmless, see below), `screen_density` (pixel ratio) | Flutter view metrics via `PlatformDispatcher` — no WebView | install-match screen-profile demotion (see below) |
| Network | `connectivity_type`, `carrier_mcc`, `carrier_mnc` (Android only) | [`connectivity_plus`](https://pub.dev/packages/connectivity_plus) + a small platform channel | carrier/connectivity breakdowns |
| Settings | `text_size` (iOS only: the body text size in points for the text-size setting, 14–23, or 28–53 for the accessibility sizes; 17 is the default), `high_contrast` (iOS only: Increase Contrast), `dark_mode`, `reduce_motion` (iOS Reduce Motion, Android Remove animations) | Flutter's `PlatformDispatcher` — no plugin | compared with the same settings read by the link page, for calibration; worth no points yet |

After the retention window (default 400 days, `RETENTION_DAYS`, or an
account's shorter one) the backend deletes these rows once its daily counts
hold their day, and blanks these fields until then.

> **Screen profile (backend).** When a tap gets a link page instead of a
> plain redirect (the *mobile interstitial*, the iOS tap-to-store page, or
> the Facebook and Instagram page on Android), the page records
> the browser's logical pixels and `devicePixelRatio` on the click row. The
> install match compares the short side only (`MIN(w,h) × devicePixelRatio`
> against the SDK's `MIN(screen_width, screen_height)`, 3 % tolerance,
> orientation-invariant): agreement adds 15 points to the click's score, a
> contradiction takes 40 away. The short side is used
> because the SDK reports the *Flutter view* size, which on
> non-edge-to-edge Android stops above the navigation bar while the browser
> reports the full display. Without the device tier neither
> `device_model` nor the screen fields are sent.

#### Advertising ID (optional)

The core package does not read or send the Google Advertising ID or the
IDFA, and depends on no ad-identification library: attribution uses the
first-party device tier, the store referrers and the pasteboard. Apps that
want the advertising id add `flutter_dectog_adid`, which links AdSupport and
AppTrackingTransparency (iOS) and Play services ads-identifier with the
`AD_ID` permission (Android):

```dart
await DectogAdId.requestTracking(); // iOS: the ATT prompt, once
await dectog.initialize(const DectogConfig(
  apiKey: 'dtg_pub_your_sdk_key',
  advertisingIdProvider: DectogAdId.provider,
));
```

The id goes with the install only when the user allowed it (ATT authorized,
no Android opt-out); otherwise the install carries `ad_tracking_limited:
true` and no id. The server stores it apart from the device tier. iOS needs
`NSUserTrackingUsageDescription` in Info.plist; declare "Device ID, used for
tracking" (App Store) and "Advertising ID" (Play Data safety).

#### Deterministic Android attribution (install referrers)

Matching installs to prior link clicks with only a server side fingerprint
(IP address and IP derived geo data) breaks when the device's IP changes
between the link click and the first app launch, for example when switching
from WiFi to cellular.

The SDK makes Android attribution deterministic automatically.
When DecTog redirects a user to a store, it embeds the click identifier in
the store's install referrer (`referrer=dtg_click=<id>&dtg_l=<user>/<slug>`);
on the first launch the SDK reads it back and the backend matches the exact
click, regardless of IP changes — and, since the referrer also names the
link, even when the click row itself never landed. No setup is required.

The reader is the plugin's own native code, modelled on the Adjust and
Branch SDKs:

- **Retries.** Transient Play errors (`SERVICE_UNAVAILABLE`,
  `SERVICE_DISCONNECTED`, `DEVELOPER_ERROR`) get up to three attempts, 3 s
  apart, instead of giving up on the first one. `FEATURE_NOT_SUPPORTED`,
  no Play Store and Play's own organic marker are definitive answers.
- **Bounded wait, late claim.** The first-launch registration waits at most
  `installReferrerTimeout` (default 5 s) for the referrer, then ships. If
  the referrer arrives later — in the same process or on a later launch —
  the SDK sends it as a late claim (`POST /api/v1/app-installs/:id/claim`),
  the backend upgrades the stored verdict, and `onAppInstalled` emits the
  upgraded verdict. A non-definitive read is re-asked on up to five later
  launches; the "delivered" flag is written only after the server
  acknowledged it.
- **Every store.** With `DectogCollection.oemReferrers` (on by default) the Huawei
  AppGallery and Vivo referrers are read too (no extra library), and the
  Samsung Galaxy Store / Xiaomi GetApps readers activate when the host app
  adds `store.galaxy.samsung.installreferrer:samsung_galaxystore_install_referrer:4.0.0`
  / `com.miui.referrer:homereferrer:1.0.0.7` to its Gradle dependencies.
  The store whose install began last wins (Branch's rule); the verdict's
  `referrerSource` names it (`google_play`, `huawei`, `samsung`, `xiaomi`,
  `vivo`, `meta`).
- **Both clocks.** Google's server-side click / install-begin timestamps are
  sent alongside the device-clock ones; the backend's fraud timing trusts
  only the server pair.
- Organic installs carry no DecTog referrer and are reported as organic.
- If you need a custom referrer source, the optional
  `installReferrerProvider` callback in `DectogConfig` overrides the
  built-in read (string only, Google Play, no OEM stores):

```dart
await dectog.initialize(DectogConfig(
  apiKey: 'dtg_pub_your_sdk_key',
  installReferrerProvider: () async => myCustomReferrerSource(),
));
```

#### Deterministic iOS attribution (pasteboard)

iOS has no install referrer. The SDK does what Branch's
NativeLink and Adjust's LinkMe do: on the first launch it checks the system
pasteboard **silently** (`UIPasteboard.hasURLs`, no prompt) and, only when
it holds a URL, reads it. A URL that parses as a DecTog link for this
deployment and names a click (`dtg_click`, as the tap-to-store page copies
it) is sent with the install (`matchSource: 'clipboard'`,
`matchConfidence: 'guaranteed'`); anything else, a plain share link
included, is left alone and never sent. The pasteboard is cleared only after
the server credited the link and only if nothing was copied since. The DecTog interstitial's
tap-to-store button (dashboard: *iOS tap-to-store*) is the web side that
copies the link before opening the App Store.

- The read defaults to **on for iOS, off for Android** (`collect` null, and
  the dashboard setting); a `collect` set without
  `DectogCollection.pasteboard` opts out on iOS, one with it forces the read
  on Android (where the Play referrer already is deterministic and Android
  12+ shows a paste toast).
- On iOS 16+ the read shows Apple's "Allow paste from …?" alert — only when
  a URL is actually in the pasteboard. `await FlutterDectog()
  .willShowPasteboardPrompt()` (callable before `initialize()`) tells you
  whether it will, so an onboarding screen can explain it first.
- `DectogPasteButton` renders Apple's `UIPasteControl` (iOS 16+; nothing
  elsewhere): tapping it reads the pasteboard **without** the alert, and a
  DecTog link is sent as a late claim. Put it on your onboarding / "I have
  an invite link" screen as the recovery path for users who declined the
  alert or apps that opted out of the automatic read:

```dart
if (DectogPasteButton.isSupported)
  const DectogPasteButton(size: Size(220, 44)),
```

Reinstalls on iOS are classified client-side from the executable, Library
and Documents dates plus a Keychain-held first-install date (Branch's
model); no new identifier is involved.

### 6. Track Post-Install Events (leads, revenue)

Events queue durably on disk and batch to the server, which
stamps each with the install's matched link — the dashboard then shows
leads and revenue per link.

```dart
// Bind your own user identity to this device's install attribution.
await dectog.identify(
  customerId: user.id,
  name: user.name,
  email: user.email,
  phone: user.phone,
);

// The first identify of a new user on a fresh install is their signup lead.
// Repeat calls with unchanged fields are skipped, so calling it on every
// launch is safe; only signup/login and profile changes send an event.
await dectog.trackConversion(
  revenue: 9.99,
  currency: 'USD',
  productId: 'pro-monthly',
  transactionId: purchase.transactionId, // counted once, even if reported again
  store: DectogStore.appStore,
);
// Renewals: originalTransactionId; refunds: transactionType: DectogTransactionType.refund.
await dectog.trackEvent('level_up', data: {'level': 3});
// Screens, for the dashboard's "Screens after open" (outside event totals):
await dectog.trackScreenView('product', params: {'id': 42});
// or once for every page route: MaterialApp(navigatorObservers: [DectogNavigatorObserver()])

await dectog.flush();   // force-send (otherwise 20 events / 30 s)
await dectog.logout();  // flush + forget the customer id
await dectog.setEnabled(false); // stop all collection (persisted; true resumes)
// Consent first: initialize with DectogConfig(enabled: false); nothing is sent
// until the user agrees, then held events and the launch link's report go out:
await dectog.setEnabled(true);
final verdict = await dectog.getAttributionData(); // cached install verdict
```

`getAttributionData()` returns the install verdict — `matched`, `type`,
`matchSource` (`'referrer'` / `'clipboard'` deterministic / `'fingerprint'`
probabilistic / null organic), `matchConfidence`, `routing`, `clickedAt`,
the matched link and its `customParameters` — using the first-launch cache,
re-pulled from the server when the app restarted (by device id, or by
install id without the device tier). An organic install
comes back as a verdict with `matched: false`; `null` means the server knows
no install for this device at all. Declare the event tier in your store
privacy forms (the SDK ships an iOS privacy manifest declaring it).

### 7. Create Links


```dart
// Create a permanent link (only slug is required; a null target inherits
// the app's fallback URL)
final link = await dectog.createLink(
  slug: 'my-link',
  target: 'https://example.com',
  iosDeepLinkPath: 'products/42',
  androidDeepLinkPath: 'products/42',
  ogTitle: 'Product 42',
  campaign: 'spring',
);
print('Created: ${link.url}');

// Update: null keeps the stored value, '' clears it
await dectog.updateLink('my-link', campaign: 'summer', ogTitle: '');

// Create a temporary link (expires in 1 hour; TTL clamped to 60 s – 30 days)
final tempLink = await dectog.createTempLink(
  target: 'https://example.com',
  ttlSeconds: 3600,
);
await dectog.updateTempLink(tempLink.slug, ogTitle: 'Limited offer');
print('Temp link: ${tempLink.url}');
```

`createLink` also accepts `metadata`, `appId`, `redirectUrl`, `fallbackUrl`,
`ogDescription`, `ogImageUrl`, `label`, `adgroup` and `creative`
(`updateLink` takes the same fields except `slug`/`appId`).
`deleteLink` / `deleteTempLink` stop the link and hide it but keep its clicks
and the installs, events and app opens attributed to it, so it can be
restored; `permanently: true` also deletes that history, which cannot be
undone.

## Complete Attribution Flow

Here's how to implement a complete attribution flow:

```dart
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final dectog = FlutterDectog();
  
  @override
  void initState() {
    super.initState();
    _initializeDectog();
  }
  
  Future<void> _initializeDectog() async {
    await dectog.initialize(DectogConfig(
      apiKey: 'your-api-key',
      enableDebugLogging: true,
    ));
    
    // Handle ongoing link clicks
    dectog.onLinkClick.listen(_handleLinkClick);
    
    // Handle app install attribution
    dectog.onAppInstalled.listen(_handleAppInstall);
    
    // Handle initial link if app was opened via link
    final initialLink = await dectog.getInitialLink();
    if (initialLink != null) {
      _handleLinkClick(initialLink);
    }
  }
  
  void _handleLinkClick(DectogLinkClick linkClick) {
    print('Link clicked: ${linkClick.slug}');
    
    if (linkClick.linkResolution != null) {
      // Navigate based on link target
      _navigateToTarget(linkClick.linkResolution!.target);
    }
  }
  
  void _handleAppInstall(DectogAppInstallResponse install) {
    if (install.matched) {
      // Show attributed install welcome
      _showAttributedWelcome(install);
    } else {
      // Show standard onboarding
      _showStandardOnboarding();
    }
  }
  
  void _showAttributedWelcome(DectogAppInstallResponse install) {
    // Example: Show personalized welcome message
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Welcome!'),
        content: Text('Thanks for installing from our ${install.slug} link!'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Navigate to the content they were originally trying to reach
              _navigateToTarget(install.deepLink ?? install.link?.target);
            },
            child: Text('Get Started'),
          ),
        ],
      ),
    );
  }
  
  void _navigateToTarget(String? target) {
    // Handle navigation based on your app's routing
    print('Navigating to: $target');
  }
}
```

## Android build notes

The plugin's `android/build.gradle` works with every current toolchain:
on AGP 9 / Flutter 3.47+ it compiles under Built-in Kotlin, on AGP 8 it
uses the Kotlin Gradle plugin, applying it itself only when neither the
host nor Flutter's tooling already did. Nothing to configure. The bundled
example app pins `android.builtInKotlin=false` in its `gradle.properties`
because two of its third-party dependencies (`device_info_plus`,
`package_info_plus`) still apply KGP and Flutter's migrator re-adds the pin
while they do; that pin affects only the example app.

## Error Handling

```dart
try {
  final link = await dectog.createLink(slug: 'test', target: 'https://example.com');
} on DectogError catch (e) {
  print('Error: ${e.message}');
}
```

## API Reference

### Configuration

```dart
DectogConfig({
  required String apiKey,     // An SDK key (dtg_pub_…)
  String? baseUrl,           // Self-hosted backend, default https://app.dectog.com
  String? linkRootDomain,    // Self-hosted link root ({username}.<root>); default
  // dectog.com when baseUrl is unset, else the baseUrl host
  bool enableDebugLogging,   // Optional: debug mode
  InstallReferrerProvider? installReferrerProvider,
  // Optional override for the built-in install-referrer read (see
  // section 5); omit it to use the native reader automatically
  Duration installReferrerTimeout, // Optional, default 5 s: how long the
  // first-launch registration waits for the referrer (a later one is
  // sent as a late claim)
  Set<DectogCollection>? collect, // Optional, default null: the device
  // tier on, the pasteboard (iOS) and OEM store referrers as the dashboard
  // sets them, no Apple Search Ads token. A set is exact: deviceTier,
  // pasteboard, oemReferrers, appleSearchAdsToken, adId
  AdvertisingIdProvider? advertisingIdProvider, // Optional: DectogAdId.provider
  // from flutter_dectog_adid
  String? fbAppId,          // Optional: enables the Meta on-device install
  // referrer on Android as an extra deterministic signal
  bool persistDeviceId,     // Optional, default true: keep the first iOS IDFV
  // in the Keychain so the device id survives reinstall
  bool enabled,             // Optional, default true: false waits for consent
  // (no request until setEnabled(true); events held on the device)
  DectogEnvironment? environment, // Optional: the key's expected environment;
  // diagnostics() warns about a test key in a live build and the reverse
})
```

#### Pasteboard helpers

- `Future<bool> willShowPasteboardPrompt({Set<DectogCollection>? collect})` —
  whether this launch's pasteboard read will show the iOS 16+ system alert
  (callable before `initialize()`).
- `DectogPasteButton({Size size, DectogPasteDisplayMode displayMode,
  DectogPasteCornerStyle cornerStyle, Color? backgroundColor, Color?
  foregroundColor})` + `DectogPasteButton.isSupported` — the native
  `UIPasteControl` (iOS 16+).

#### Signing, opens and fraud signals

- Every authenticated SDK call is HMAC-signed (`x-dectog-timestamp` +
  `x-dectog-signature`) — the backend rejects unsigned requests.
- DecTog links that open the already-installed app are reported
  (`POST /api/v1/app-opens`), powering per-link **Opens** analytics and
  `lastOpen` on `getAttributionData()`.
- The install response carries `fraudFlags` (e.g. `'emulator'`,
  `'impossible_speed'`) and `referrerSource`; a per-app **strict fraud
  mode** on the dashboard makes flagged installs count organic.

### Models

```dart
// Permanent link
DectogLink({
  String id, slug, url,
  String? target,                // null = inherits the app's fallback URL
  String? appId,
  int clickCount,
  DateTime createdAt,
  DateTime? updatedAt,
  Map<String, dynamic>? metadata,
  String? ogTitle, ogDescription, ogImageUrl,
  String? iosDeepLinkPath, androidDeepLinkPath,
  String? redirectUrl, fallbackUrl,
  String? label, campaign, adgroup, creative,
})

// Temporary link
DectogTempLink({
  String id, slug, url,
  String? target,
  int? ttlSeconds,
  DateTime expiresAt, createdAt,
  String? ogTitle, ogDescription, ogImageUrl,
})

// resolveLink() result / DectogLinkClick.linkResolution
DectogLinkResolution({
  String id, slug, url, type,    // type: 'permanent' | 'temporary'
  String? target,
  String? iosDeepLinkPath, androidDeepLinkPath,
  ...
})  // .deepLinkPath: this platform's path, else the other platform's

// Link click event
DectogLinkClick({
  String originalUrl, slug, username,
  DateTime receivedAt,
  DectogError? error,
  DectogLinkResolution? linkResolution,
})  // .targetUrl (String?), .clickParams → the opened URL's dec_* values

// App install attribution — emitted on the first launch, and again when a
// late deterministic signal upgrades the verdict (claim == 'upgraded')
DectogAppInstallResponse({
  bool matched,                  // Attribution CREDIT (guaranteed/high confidence)
  String type,                   // 'organic' | 'non-organic'
  String? matchSource,           // 'referrer' | 'clipboard' | 'fingerprint' | null
  String? referrerSource,        // 'google_play' | 'huawei' | 'samsung' | 'xiaomi' | 'vivo' | 'meta'
  String? matchConfidence,       // 'guaranteed' | 'high' | 'medium' | 'low' | null
  DectogDeferredRoute? routing,  // deferred-routing candidate at >= medium
  String? username, slug,        // Attribution details (if matched)
  String? installId,             // Server install id (stable handle for the verdict)
  DateTime? clickedAt,           // attributed click time (also on first launch)
  DectogAppInstallLink? link, // {slug, target, url, created_at, metadata}
  Map<String, dynamic>? customParameters,
  DectogClickParams? clickParams, // dec_* params on the clicked URL
  String? deepLink,               // dec_deeplink route, e.g. 'voucher?code=X'
  List<String> fraudFlags,
  bool replayed,                  // the server already had this install_attempt_id
  bool isReinstall,
  String? installState,           // 'install' | 'reinstall' | 'update'
  String? claim, claimReason,     // late-claim outcome ('upgraded' | 'unchanged' | 'rejected')
  DectogAppOpen? lastOpen,        // latest link that re-opened the installed app
                                  // (attribution re-pulls only)
  DectogAppleSearchAds? appleSearchAds, // null until a token was sent, then the
                                  // status of the exchange with Apple
})

// Deferred-routing candidate
DectogDeferredRoute({
  String? username, slug, deepLink, confidence,
  DectogClickParams? clickParams,
  DateTime? clickedAt,
})

// Apple Search Ads attribution, resolved server-side from the AdServices
// token (DectogCollection.appleSearchAdsToken)
DectogAppleSearchAds({
  String status,                 // 'pending' | 'resolved' | 'no_attribution' |
                                 // 'invalid' | 'expired' | 'failed'
  bool? attribution,             // Apple's verdict once answered
  DateTime? resolvedAt,
  int? orgId, campaignId, adGroupId, keywordId, adId,
  String? conversionType,        // 'Download' | 'Redownload' | 'PreOrder'
  String? claimType,             // 'Click' | 'Impression'
  String? clickDate, impressionDate, countryOrRegion, supplyPlacement,
})  // .isPending, .isAttributed

// A link that re-opened the already-installed app
DectogAppOpen({
  String username, slug,
  String? clickId,
  DateTime openedAt,
})

// Per-click link overrides — ?dec_label=…&dec_campaign=…&dec_deeplink=…
DectogClickParams({
  String? deepLink, label, campaign, adgroup, creative, tracker,
})
```

### Streams

```dart
// Listen for link clicks (app running or launch)
Stream<DectogLinkClick> dectog.onLinkClick

// Listen for app install events (first launch, plus late-claim upgrades)
Stream<DectogAppInstallResponse> dectog.onAppInstalled
```

## Testing Install Attribution

Keep test traffic out of your live numbers with a test environment
(dashboard Settings → Test environment): a second account,
`t-<username>`, with the same apps. Put its SDK key in debug builds and
add `t-<username>.dectog.com` to their associated domains:

```dart
await dectog.initialize(DectogConfig(
  apiKey: kReleaseMode ? liveSdkKey : testSdkKey,
  environment: kReleaseMode ? DectogEnvironment.live : DectogEnvironment.test,
));
```

During development, you can test install attribution by:

1. **Delete and reinstall your app** to simulate first install
2. **Clear app data** on Android or **delete from device** on iOS  
3. **Click a DecTog link** → install app → open app
4. The `onAppInstalled` event should fire with `matched: true`

The plugin prevents duplicate install logging with a persisted
`install_attempt_id` (the server replays the stored verdict for a retried
registration) and a sentinel in a backup-excluded directory, validated
against the package's first-install time. On Android, `adb shell pm
clear <package>` resets it; on iOS delete the app.

## Example

See the [example app](./example) for a complete implementation.

## Support

- 🐛 Issues: [GitHub Issues](https://github.com/DecTog/flutter_dectog/issues)
- 📚 Docs: [docs.dectog.com/](https://docs.dectog.com/)

## License

MIT License - see [LICENSE](LICENSE) file.
