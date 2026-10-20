# flutter_dectog_adid

The advertising identifier for [flutter_dectog](../../README.md): the IDFA on
iOS once App Tracking Transparency allows it, the GAID on Android.

flutter_dectog itself never reads an advertising identifier and links no ad
framework. This package is the only one that links AdSupport and
AppTrackingTransparency (iOS) and Play services ads-identifier with the
`AD_ID` permission (Android). An app that does not depend on it ships none of
them.

## Use

```dart
import 'package:flutter_dectog/flutter_dectog.dart';
import 'package:flutter_dectog_adid/flutter_dectog_adid.dart';

// iOS: the ATT prompt, once. Ask before initialize() so the install
// registration can carry the IDFA; the app must be active.
await DectogAdId.requestTracking();

await FlutterDectog().initialize(const DectogConfig(
  apiKey: 'dtg_pub_your_sdk_key',
  advertisingIdProvider: DectogAdId.provider,
));
```

`DectogAdId.provider` only reads; it never prompts. When the user did not
allow tracking (ATT not authorized, an Android opt-out, the all-zero id) the
install carries `ad_tracking_limited: true` and no id. A `DectogConfig.collect`
set without `DectogCollection.adId` turns the read off even with a provider.

## Platform setup

- **iOS:** add `NSUserTrackingUsageDescription` to `Info.plist`; without it
  `requestTracking()` does not prompt (iOS would terminate the app). The
  bundled privacy manifest declares the IDFA as a Device ID used for
  tracking.
- **Android:** the `AD_ID` permission merges into your manifest. Declare
  "Advertising ID" in the Play Console (Policy → App content → Advertising
  ID) and in Data safety.

## Store disclosures

| Store | What to declare |
|---|---|
| App Store (App Privacy) | Device ID, used for tracking (third-party advertising or developer advertising, as you use it) |
| Google Play (Data safety) | Device or other IDs: Advertising ID; collected, for advertising or marketing and analytics |

The full table for every `DectogCollection` value is on
[docs.dectog.com/sdk/device-data-and-privacy](https://docs.dectog.com/sdk/device-data-and-privacy/).
