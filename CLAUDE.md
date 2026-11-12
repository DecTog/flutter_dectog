# Working on flutter_adto

The Flutter SDK for AdTo: Dart in `lib/`, a Kotlin plugin in `android/`, a
Swift plugin in `ios/`, an example app in `example/`. The server and its wire
contract are in `ad-to/adto` (`docs/API_CONTRACT.md`).

## Commands

```bash
dart format --output=none --set-exit-if-changed lib test tool example/lib
flutter analyze
flutter test
flutter pub publish --dry-run
(cd packages/flutter_adto_adid && flutter test) && tool/publish_adid.sh --dry-run
cd example && flutter build apk --debug && flutter build ios --simulator --debug
(cd example/android && ./gradlew :flutter_adto:testDebugUnitTest)   # Kotlin tests
swift test --package-path ios/native_tests                             # Swift tests
tool/device_restart_test.sh   # with an emulator or device attached
```

`flutter test` mocks the platform channel; the example builds are what compile
the Kotlin and Swift.

## Rules

- flutter_adto is the SDK of AdTo, a new service; it shares no names or
  device data with flutter_dectog (the DecTog service's SDK, maintained on
  the `flutter_dectog-1.x` branch). Once published, the public API follows
  semantic versioning; a removed, renamed or retyped member needs a major
  version. Never publish to pub.dev without being asked.
- The on-device names (the `adto` folder, `.adto_*.json`, the Keychain
  service `app.adto.sdk`) and the wire names (`x-adto-*`, `AdtoSDK/`,
  `adto_*` keys and parameters, `adto://`) never change once released:
  `test/on_device_names_test.dart` pins the device ones.
- The wire format follows the server's `docs/API_CONTRACT.md`; change both
  together. Errors arrive as `{"error": {"code", "message", "request_id"}}` and
  surface as `AdtoError.code` / `requestId`.
- Everything the SDK collects respects `setEnabled(false)` and
  `AdtoConfig.collect` (`AdtoCollection`), and is declared in
  `ios/flutter_adto/Sources/flutter_adto/PrivacyInfo.xcprivacy` and the
  disclosure table in `doc/api-reference.md`. The advertising id lives only
  in `packages/flutter_adto_adid`; the core links no ad framework.
- The native reads live in framework-free files shared as source with the
  React Native SDK (`ad-to/react-native-adto`, whose `tool/sync_shared.sh
  --check` compares them byte for byte): `android/src/main/kotlin/app/adto/core/`
  and, in `ios/flutter_adto/Sources/flutter_adto/`, `AdtoDevice.swift`,
  `AdtoKeychain.swift`, `AdtoInstallDates.swift` and
  `AdtoPasteTargetView.swift`. Keep Flutter out of them, change them here
  first, then sync. The plugin classes only map the channel onto them.
- Custom-scheme links are recognised by their `adto_l=<username>/<slug>` tag,
  never by the URL's shape (only `adto://` is accepted untagged).
- Version bumps touch `pubspec.yaml`, `lib/src/version.dart`, the podspec and
  `CHANGELOG.md` together (`RELEASING.md`).
- `test/fixtures/wire/` mirrors the server's golden responses (`tool/sync_wire_fixtures.sh`);
  `test/fixtures/url-cases.json` is the shared URL table; `test/public_api_test.dart` pins the
  public surface; `test/sdk_harness_test.dart` is the end-to-end harness.
- `doc/api-reference.md` is the API reference (the docs site syncs it). A public API change
  updates it, then `dart run tool/gen_llms.dart` regenerates `llms.txt`; `test/llms_test.dart`
  fails until both are done.
- A defect fix starts with a failing test.
- Comments, doc comments and test names say what and why in words: no plan item
  ids (`P2.12`), decision or review ids.
