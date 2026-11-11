# Contributing to flutter_dectog

Thank you for helping. This repository is the Flutter SDK for DecTog: a Dart
package with a Kotlin plugin (`android/`) and a Swift plugin (`ios/`). The
server is [DecTog/dectog](https://github.com/DecTog/dectog); the docs site is
[DecTog/docs](https://github.com/DecTog/docs).

flutter_dectog is on pub.dev and in apps in production, so the public API
follows semantic versioning: a removed, renamed or retyped member is a breaking
change and needs a major version. `test/public_api_test.dart` fails on any
change to the surface.

## Before you start

- **Bugs:** open an issue with the Flutter version, the platform and OS
  version, the SDK log with `enableDebugLogging: true`, and the `requestId` of
  any `DectogError` you got.
- **Features:** open an issue before a large change.
- **Security issues:** never in public; see [SECURITY.md](SECURITY.md).

## Checks

CI runs these on every push and pull request; run them before you open one.

```bash
dart format --output=none --set-exit-if-changed lib test tool example/lib
flutter analyze
flutter test
flutter pub publish --dry-run
cd example && flutter build apk --debug && flutter build ios --simulator --debug
(cd example/android && ./gradlew :flutter_dectog:testDebugUnitTest)   # Kotlin, JUnit + Robolectric
swift test --package-path ios/native_tests                             # Swift, XCTest on macOS
```

The two example builds compile the plugin's Kotlin and Swift; `flutter test`
alone does not, because it mocks the platform channel. The native reads sit in
framework-free files (`android/src/main/kotlin/app/dectog/core/`, and
`DectogDevice.swift`, `DectogKeychain.swift`, `DectogInstallDates.swift` and
`DectogPasteTargetView.swift` on iOS) that the React Native SDK copies byte for
byte; keep Flutter imports out of them. The native tests cover
the referrer reader and orchestrator (`android/src/test`) and the install dates
(`ios/native_tests`, which compiles the production Swift files through
symlinks).

With an Android emulator or device attached, `tool/device_restart_test.sh`
checks that the install registration survives a process kill and retries with
the same `install_attempt_id`. CI runs it only on demand (the "Device tests"
workflow).

## Rules

- **The wire contract lives in the server repo.** Request and response shapes
  follow `docs/API_CONTRACT.md` there; a change on one side ships with the
  change on the other. `test/fixtures/wire/` is a copy of the server's golden
  responses: refresh it with `tool/sync_wire_fixtures.sh` (server checked out
  next to this repo) and keep `test/wire_contract_test.dart` parsing every file.
- **Shared cases.** `test/fixtures/url-cases.json` is the link-URL table every
  SDK port must pass; add a case there, not inline.
- **End-to-end behaviour.** `test/sdk_harness_test.dart` drives the real SDK with
  faked plugins and a recording HTTP client; use it for anything that spans
  services (what is sent, and what must not be).
- **Versions move together.** `pubspec.yaml`, `lib/src/version.dart`,
  `ios/flutter_dectog.podspec` and the newest `CHANGELOG.md` entry carry the
  same version; `test/version_test.dart` fails otherwise. See
  [RELEASING.md](RELEASING.md).
- **Collection is consent-gated.** Anything new the SDK sends must respect
  `setEnabled(false)` and `collectDeviceData`, and must be listed in the
  privacy manifest and the docs site's device-data page.
- **Never block the host app.** Native reads run with timeouts and fail soft;
  no SDK call may throw into app code except the documented `DectogError`s.
- **Tests first for defects.** A bug fix starts with a test that fails without it.
- **No tracking ids in code.** Comments, doc comments and test names say what and
  why in words, without plan item ids (`P2.12`), decision or review ids: dartdoc
  and editor hovers show them to people who cannot look them up.

## Pull requests

- One topic per pull request, with a description of what changed and why.
- Commit messages follow the existing history: `fix:`, `feat:`, `docs:`,
  `ci:`, `chore:`, `style:`, `test:`, then a summary in the imperative.
- CI must be green.

## License

The SDK is licensed under the [MIT License](LICENSE). Your contribution is
licensed under the same terms, as GitHub's terms of service provide for
contributions to a licensed repository.
