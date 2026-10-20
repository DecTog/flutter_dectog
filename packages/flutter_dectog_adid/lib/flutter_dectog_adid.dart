/// The advertising identifier for flutter_dectog: the IDFA on iOS
/// once App Tracking Transparency allows it, the GAID on Android.
///
/// ```dart
/// await DectogAdId.requestTracking(); // iOS: shows the ATT prompt once
/// await FlutterDectog().initialize(const DectogConfig(
///   apiKey: 'dtg_pub_…',
///   advertisingIdProvider: DectogAdId.provider,
/// ));
/// ```
library;

import 'package:flutter/services.dart';
import 'package:flutter_dectog/flutter_dectog.dart';

/// The App Tracking Transparency status (iOS). Android has no prompt and
/// answers [notSupported].
enum DectogTrackingStatus {
  notDetermined,
  restricted,
  denied,
  authorized,
  notSupported,
}

/// Reads the advertising identifier for `DectogConfig.advertisingIdProvider`.
abstract final class DectogAdId {
  static const MethodChannel _channel = MethodChannel('dectog_adid');

  static const String _zeros = '00000000-0000-0000-0000-000000000000';

  /// The provider to pass as `DectogConfig.advertisingIdProvider`. It only
  /// reads; it never shows the ATT prompt (call [requestTracking] before
  /// `initialize()` for that). An id the user limited (ATT not authorized,
  /// Android opt-out, the all-zero id) comes back as `limited` with no id;
  /// null when the platform has no reader (no Play services, a desktop).
  static Future<DectogAdvertisingId?> provider() async {
    final Map<dynamic, dynamic>? raw;
    try {
      raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getAdvertisingId',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
    if (raw == null) return null;
    final id = (raw['id'] as String?)?.trim();
    final limited =
        raw['limited'] == true || id == null || id.isEmpty || id == _zeros;
    return limited
        ? const DectogAdvertisingId(limited: true)
        : DectogAdvertisingId(id: id);
  }

  /// The current ATT status, without prompting.
  static Future<DectogTrackingStatus> trackingStatus() =>
      _status('trackingStatus');

  /// Shows the iOS ATT prompt when the status is still `notDetermined`, and
  /// answers the status. The app must be active (iOS answers
  /// `notDetermined` without a prompt otherwise) and its Info.plist must
  /// carry `NSUserTrackingUsageDescription`.
  static Future<DectogTrackingStatus> requestTracking() =>
      _status('requestTracking');

  static Future<DectogTrackingStatus> _status(String method) async {
    try {
      final name = await _channel.invokeMethod<String>(method);
      return DectogTrackingStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => DectogTrackingStatus.notSupported,
      );
    } on MissingPluginException {
      return DectogTrackingStatus.notSupported;
    } on PlatformException {
      return DectogTrackingStatus.notSupported;
    }
  }
}
