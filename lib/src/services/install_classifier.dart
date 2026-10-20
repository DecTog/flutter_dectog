/// Client-side install classification: `install` | `reinstall` |
/// `update`, sent as `install_state` on the install registration.
///
/// Why it matters: an existing user who merely UPDATES to the first build
/// that ships this SDK produces a first-launch install call. Without this
/// label the backend would fingerprint-match that "install" against the
/// orphan click pool — at 6M users that is millions of wrong credits. Branch
/// classifies the same way (STATE_FRESH_INSTALL / STATE_UPDATE with a 24 h
/// buffer, plus the keychain first-install date on iOS) and the backend
/// never fingerprint-matches an `update`.
///
/// Pure function; every timestamp is epoch milliseconds, null = unknown.
library;

/// 24 h — Branch's buffer: an update landing within a day of the first
/// install is still the install (store-side re-signing, same-day hotfix).
const Duration installUpdateBuffer = Duration(hours: 24);

String? classifyInstallState({
  required bool isAndroid,
  int? firstInstallTs,
  int? lastUpdateTs,
  int? keychainFirstInstallTs,
  int? documentsCtimeTs,
  int? executableCtimeTs,
  int? libraryCtimeTs,
}) {
  final buffer = installUpdateBuffer.inMilliseconds;
  if (isAndroid) {
    // PackageManager: firstInstallTime == lastUpdateTime on a fresh
    // install; a later lastUpdateTime means the package was updated since.
    // Android cannot tell a reinstall client-side (the server does, by
    // device id).
    if (firstInstallTs == null || lastUpdateTs == null) return null;
    return lastUpdateTs - firstInstallTs > buffer ? 'update' : 'install';
  }
  // iOS (Branch's install-date logic): a keychain first-install date that
  // predates this container by more than the buffer means the app was here
  // before — a reinstall. Otherwise a binary (executable ctime) newer than
  // the container (Library ctime) by more than the buffer is an update of an
  // existing install; else a fresh install.
  if (keychainFirstInstallTs != null && documentsCtimeTs != null) {
    if (documentsCtimeTs - keychainFirstInstallTs > buffer) return 'reinstall';
  }
  if (executableCtimeTs != null && libraryCtimeTs != null) {
    return executableCtimeTs - libraryCtimeTs > buffer ? 'update' : 'install';
  }
  if (documentsCtimeTs != null || libraryCtimeTs != null) return 'install';
  return null;
}
