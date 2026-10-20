import 'package:flutter/foundation.dart';

import 'identifier_channel.dart';

/// First-party device identifier behind the `DectogCollection.deviceTier` consent
/// gate: `Settings.Secure.ANDROID_ID` on Android and the IDFV on iOS. The
/// IDFV is kept in the Keychain so it survives uninstall/reinstall unless
/// the host sets `DectogConfig.persistDeviceId: false`; see README privacy
/// notes. Cached per process; a
/// failed read returns null and the install is simply sent WITHOUT a
/// device_id (a random per-process fallback would register phantom devices
/// server-side).
class DeviceIdentityService {
  DeviceIdentityService._internal();
  static final DeviceIdentityService _instance =
      DeviceIdentityService._internal();
  factory DeviceIdentityService() => _instance;

  final IdentifierChannel _channel = IdentifierChannel();
  String? _cachedDeviceId;

  /// Stable device identifier for this install, or null when the platform
  /// read fails (the field is then omitted entirely). [persist] is the
  /// iOS Keychain switch (DectogConfig.persistDeviceId).
  Future<String?> getDeviceId({bool persist = false}) async {
    if (_cachedDeviceId != null) return _cachedDeviceId;
    final native = await _channel.getDeviceId(persist: persist);
    if (native != null && native.trim().isNotEmpty) {
      _cachedDeviceId = native;
      return native;
    }
    return null;
  }

  bool get hasStableId => _cachedDeviceId != null;

  /// Drop the cached identifier (tests only — the cache exists per process).
  @visibleForTesting
  void resetForTest() => _cachedDeviceId = null;
}
