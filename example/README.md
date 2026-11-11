# Trails, the flutter_adto example

A small app built the way a real one would use AdTo: a friend shares a trail, you tap the link,
install the app, and land on that trail after signing up; your friend's invite is credited on the
server; you go Pro, and the purchase is credited to the link that brought you. Every screen is
reported, so the dashboard shows where people went after a link opened the app.

| Flow | What the app calls |
|---|---|
| A shared trail opens the installed app on it | `onLinkClick`, `clickParams.deepLink` (`dec_deeplink=trails/2`) |
| A new install lands on the shared trail after signing up | `onAppInstalled`, `deepLink` / `routing.deepLink` |
| Sign up (a random id, no name or email) | `identify(customerId:)`; on an install credited to a referral link the server records the referral |
| Invite friends | `createReferralLink(customerId:)` |
| Share a trail | the referral link with `dec_deeplink=trails/<id>` per share |
| Go Pro (a demo purchase) | `trackConversion(...)` with a transaction id, store and plan |
| Every screen | `AdtoNavigatorObserver(captureParams: {'trail_id'})` |
| Paste an invite link on iOS 16+ without the paste alert | `AdtoPasteButton` |
| Debug: setup, attribution, consent | `diagnostics()`, `getAttributionData()`, `setEnabled` |

No event carries personal data: the user is a random id, events name trails by id.

`site/index.html` is the app's web page: two store buttons that are one AdTo link, so a tap from
a phone goes to the right store (or opens the app), and a tap inside Instagram's or Facebook's
browser gets AdTo's way out to the store. Serve it from anywhere, after replacing the link.

## Run it

1. In the dashboard, register the app on the Apps page (bundle ID `app.adto.example` and your team
   ID, package `app.adto.example` and your signing fingerprint), and create a link bound to it,
   for example `get-trails` with the deep-link path `trails/1`.
2. Create an SDK key (Settings → SDK keys) and the env file:

   ```bash
   cp env/dev.json.example env/dev.json     # a test-environment SDK key
   cp env/prod.json.example env/prod.json   # a live SDK key
   ```

   | Key | Meaning |
   |---|---|
   | `ADTO_API_KEY` | The SDK key (`dtg_pub_…`), never the account key. |
   | `ADTO_BASE_URL` | The API: `https://app.adto.app`. |
   | `ADTO_LINK_ROOT_DOMAIN` | Where links live: `adto.app`. |

3. Universal Links and App Links need your link host in the app. Replace `{username}` in
   `android/app/src/main/AndroidManifest.xml` and `YOUR_SUBDOMAIN` in
   `ios/Runner/Runner.entitlements` with your username. The `dectog://` scheme filters already in
   the project work without it.
4. Run:

   ```bash
   flutter run --dart-define-from-file=env/dev.json    # or env/prod.json
   ```

Without a key the app opens on its welcome screen and says how to configure it.

## Try each flow

- **Warm open:** with the app installed, open `https://<you>.adto.app/get-trails?dec_deeplink=trails/3`
  from Notes or Messages (not by pasting into Safari): Trails opens on Old Mill Path once signed in.
- **Deferred deep link:** uninstall, tap the same link (it goes to the store), install from your
  build, launch: after Sign up you land on the trail. The Debug screen shows how the install was
  matched (`referrer` on Android is deterministic).
- **Referral:** sign up, open Invite friends, send the link to a second device, install and sign up
  there: the dashboard's Overview shows the referral, and a `referral.converted` webhook fires.
- **Screens after open:** after a few opens, the links page's Screens after open panel lists where
  people went.

## Tests

```bash
flutter test     # the welcome screen without a key, and the route parser
```
