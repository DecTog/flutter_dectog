/// The flutter_dectog package version.
///
/// Must match `version:` in pubspec.yaml. test/version_test.dart fails the
/// build when the two drift, so update both together when releasing.
const String packageVersion = '1.0.0';

/// `<name>/<version>` sent as `x-dectog-sdk` on every signed API call.
const String sdkIdentity = 'flutter_dectog/$packageVersion';
