# Changelog

All notable changes to flutter_adto are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - Unreleased

flutter_adto is flutter_dectog 1.0.x under AdTo's name: the same behaviour, wire and on-device
data, with the package, the types and the default hosts renamed. See "Moving from
flutter_dectog" in the README.

- **Package:** `flutter_adto` (`package:flutter_adto/flutter_adto.dart`), and
  `flutter_adto_adid` for the advertising identifier. The iOS Swift package and pod, the Android
  plugin (`app.adto.flutter_adto`) and the method channels are renamed too, so the old and the
  new plugin never clash in one app.
- **Types:** every `Dectog` prefix becomes `Adto`: `FlutterAdto`, `AdtoConfig`, `AdtoLink`,
  `AdtoLinkClick`, `AdtoError`, `AdtoPasteButton`, `AdtoNavigatorObserver` and the rest. There
  are no aliases for the old names.
- **Default hosts:** `AdtoConfig.defaultBaseUrl` is `https://app.adto.app` and
  `defaultLinkRootDomain` is `adto.app`. An account on the old DecTog service sets
  `baseUrl: 'https://app.dectog.com'` and `linkRootDomain: 'dectog.com'`.
- **SDK header:** calls send `x-dectog-sdk: flutter_adto/<version>`.
- **Unchanged:** the request headers (`x-dectog-*`), the `DectogSDK/` user-agent token, the
  `dtg_*` parameters, the `dectog://` development links, the files the SDK keeps on the device
  (`.dectog_*.json` in its `dectog` folder) and the iOS Keychain items (service
  `app.dectog.sdk`), so an app that moves from flutter_dectog keeps its install state.

## flutter_dectog history

flutter_adto continues flutter_dectog, whose releases follow.

### flutter_dectog [1.0.0] - 2026-10-12

First public release. flutter_dectog is the Flutter SDK for DecTog, a
self-hosted deep-link and install-attribution backend (Cloudflare Worker +
D1): short links that open the installed app or route through the stores,
deferred deep linking for new installs, post-install events, and the
attribution mechanics of the Adjust, Branch and AppsFlyer SDKs on your own
infrastructure.

- **Links** — create, update, delete and resolve permanent and temporary
  links with per-platform deep-link paths, redirect / fallback overrides,
  social previews and tracking fields; `dec_*` per-click overrides
  (`DectogClickParams`). `getLinks({limit, cursor})` returns one page, a
  `DectogLinkPage` (`links`, `nextCursor`, `hasMore`). Links carry their
  lifecycle (`expiresAt`, `expiredUrl`, `disabledAt`, `disabledReason`,
  `archivedAt`, `deletedAt`); `deleteLink` / `deleteTempLink` keep the
  link's history unless `permanently: true`, and `resolveLink` throws
  `link_paused` / `link_expired` for a link that is not live.
- **Opens** — `onLinkClick` / `getInitialLink()` for universal links, App
  Links, custom schemes and the Android intent bounce. The cold-start link
  is consumed once per process, launches from the recents screen are
  ignored, OAuth / social-login callback URLs are never logged or emitted,
  and every open is reported for per-link analytics with the URL's `dec_*`
  and `utm_*` values only; the rest of the URL stays on the device.
- **Deferred install attribution** — one idempotent install registration
  per install: a persisted attempt id, bounded retries with jittered backoff
  and `Retry-After`, state kept in a backup-excluded directory and validated
  against the package first-install time. Deterministic signals come first:
  the Google Play Install Referrer and the Huawei AppGallery, Galaxy Store,
  Xiaomi GetApps and vivo store referrers (native readers with Adjust-style
  retries; a referrer the store delivers after the first launch is sent as
  a late claim), Meta's on-device referrer (`fbAppId`), and the pasteboard
  on iOS (on by default on iOS 15+, domain-validated, cleared after use,
  `willShowPasteboardPrompt()`, `DectogPasteButton` for the iOS 16+
  `UIPasteControl`). The probabilistic fallback is scored server-side:
  `matchConfidence` (`guaranteed` / `high` / `medium` / `low`) separates
  attribution credit (`matched`) from the deferred route (`routing`), and
  `installState` keeps app updates out of matching.
- **Verdict** — `onAppInstalled` (emitted again when a late signal upgrades
  it), `currentAppInstall`, `getAttributionData()` (organic verdicts
  included), fraud flags, `clickParams` / `deepLink` to route to, and
  `appleSearchAds` once the server has resolved the AdServices token
  (`DectogCollection.appleSearchAdsToken`).
- **Environments** — `DectogEnvironment` and `DectogConfig(environment:)`:
  a test environment's key in debug builds keeps their installs, events
  and links out of the live numbers; `diagnostics()` warns about a key from
  the other environment, and about a test key in a release build.
- **Events** — `identify`, `trackConversion`, `trackEvent`, `trackScreenView`
  and `DectogNavigatorObserver` (screen views, name only unless route
  arguments are allowed, kept out of event totals), a durable
  on-disk queue, `flush`, `logout`, `setEnabled` / `isEnabled` (persisted
  collection consent) and `DectogConfig(enabled: false)` to wait for it:
  no request of the SDK's own until `setEnabled(true)`, events held on the
  device, the launch link's click and open reported on consent. Every event carries a `client_event_id`, so a resent
  batch is stored once; undelivered events expire after 7 days.
  `trackConversion` carries the store transaction (`transactionId`,
  `originalTransactionId`, `store`, `purchaseType`, `quantity`,
  `transactionType`), so purchases count once, renewals keep their link and
  refunds subtract; on iOS, `appStoreJws` (a StoreKit 2 `jwsRepresentation`)
  makes the purchase store-verified.
- **Privacy** — `DectogConfig.collect` names what a build collects
  (`DectogCollection`: the device tier, the pasteboard, the OEM referrers,
  the Apple Search Ads token, the advertising id), each with its App Store
  and Play disclosures documented. With the device tier on, the device ping
  that feeds the retention read-out goes once per device per UTC day. The
  core package reads no advertising
  identifier; the separate `flutter_dectog_adid` package reads the IDFA
  after ATT and the GAID (`advertisingIdProvider`). The iOS privacy manifest
  is bundled, and every authenticated call is HMAC-signed.
- **Packaging** — iOS through Swift Package Manager (CocoaPods still
  supported via the podspec), Android with the Play Install Referrer
  library. Flutter ≥ 3.29, Dart ≥ 3.7.
- **Documentation** — full reference at [docs.dectog.com](https://docs.dectog.com).
  The package ships `llms.txt` for AI coding agents and the API reference in
  `doc/api-reference.md`.
