import 'dart:ui' show Brightness, PlatformDispatcher;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// The user's display and accessibility settings, as the device tier sends
/// them. Each field is null when the platform does not report it.
class DeviceSettings {
  /// Body text size in points for the text-size setting (iOS only):
  /// 14, 15, 16, 17 (the default), 19, 21, 23, then 28, 33, 40, 47, 53 for
  /// the accessibility sizes.
  final int? textSize;

  /// The system appearance is dark.
  final bool? darkMode;

  /// Increase Contrast (iOS only).
  final bool? highContrast;

  /// iOS Reduce Motion; Android Remove animations.
  final bool? reduceMotion;

  const DeviceSettings({
    this.textSize,
    this.darkMode,
    this.highContrast,
    this.reduceMotion,
  });
}

/// Reads [DeviceSettings] from dart:ui, with no plugin and no channel call.
///
/// iOS delivers these settings after the first view appears, a moment after
/// `main()` starts, so the install flow reads them last, once its other
/// reads have resolved.
class DeviceSettingsService {
  DeviceSettingsService._internal();
  static final DeviceSettingsService _instance =
      DeviceSettingsService._internal();
  factory DeviceSettingsService() => _instance;

  PlatformDispatcher? _override;

  /// Tests: read from [dispatcher] (a `TestPlatformDispatcher`) instead of
  /// the app's; null restores `PlatformDispatcher.instance`.
  @visibleForTesting
  void overrideForTest(PlatformDispatcher? dispatcher) =>
      _override = dispatcher;

  /// The current settings. [isIOS] gates the text size and the contrast.
  /// The Flutter iOS engine reports the content-size category as body
  /// points / 17, so the scale times 17 is the body size; Android's font
  /// scale has no such mapping. On Android the engine's contrast flag
  /// follows the Android 14 contrast level and is always false before
  /// Android 14, so it would say nothing. Each read that fails is null;
  /// this never throws.
  DeviceSettings read({required bool isIOS}) {
    final dispatcher = _override ?? PlatformDispatcher.instance;
    return DeviceSettings(
      textSize:
          isIOS ? _read(() => (dispatcher.textScaleFactor * 17).round()) : null,
      darkMode: _read(() => dispatcher.platformBrightness == Brightness.dark),
      highContrast:
          isIOS
              ? _read(() => dispatcher.accessibilityFeatures.highContrast)
              : null,
      reduceMotion: _read(() {
        final features = dispatcher.accessibilityFeatures;
        return features.reduceMotion || features.disableAnimations;
      }),
    );
  }

  static T? _read<T>(T Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }
}
