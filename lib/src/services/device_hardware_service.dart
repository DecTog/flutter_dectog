import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:device_info_plus/device_info_plus.dart';

/// Normalized device hardware fingerprint, collected on both mobile
/// platforms via device_info_plus (mirrors the Adjust `device_name` /
/// `cpu_type` / `os_build` tier).
///
/// Screen metrics come from PlatformDispatcher (no WebView needed).
class DeviceHardwareInfo {
  /// Physical pixels, e.g. "1080" x "2424".
  final String? screenWidth;
  final String? screenHeight;

  /// Device pixel ratio, e.g. "2.625".
  final String? screenDensity;

  /// Build.MODEL on Android (e.g. "Pixel 9"); marketing name on iOS
  /// (e.g. "iPhone 17e"), falling back to utsname.machine (e.g.
  /// "iPhone18,5") when device_info_plus doesn't know the identifier yet.
  /// Null on desktop.
  final String? deviceModel;

  /// Build.MANUFACTURER on Android; "Apple" on iOS.
  final String? deviceManufacturer;

  /// 'phone' | 'tablet' | null.
  final String? deviceKind;

  /// Primary ABI (e.g. "arm64-v8a"); "arm64" on iOS.
  final String? cpuType;

  /// Build.ID on Android (e.g. "AP4A.250105.002"); no iOS equivalent.
  final String? osBuild;

  /// Precise OS version: Android `version.release` (e.g. "15"),
  /// iOS `systemVersion` (e.g. "17.5.1") — more reliable than the coarse
  /// dart:io `Platform.operatingSystemVersion`.
  final String? osVersion;

  /// device_info_plus `isPhysicalDevice`; null when unknown (desktop).
  /// Drives the worker's emulator fraud rule.
  final bool? isPhysicalDevice;

  const DeviceHardwareInfo({
    this.screenWidth,
    this.screenHeight,
    this.screenDensity,
    this.deviceModel,
    this.deviceManufacturer,
    this.deviceKind,
    this.cpuType,
    this.osBuild,
    this.osVersion,
    this.isPhysicalDevice,
  });
}

class DeviceHardwareService {
  DeviceHardwareService._internal();
  static final DeviceHardwareService _instance =
      DeviceHardwareService._internal();
  factory DeviceHardwareService() => _instance;

  final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  /// Screen metrics from the first platform view — available without any
  /// WebView; null when no view exists yet (tests, headless embeds).
  static ({String? width, String? height, String? density}) _screen() {
    try {
      final view = PlatformDispatcher.instance.views.first;
      final size = view.physicalSize;
      if (size.isEmpty) return (width: null, height: null, density: null);
      return (
        width: size.width.round().toString(),
        height: size.height.round().toString(),
        density: view.devicePixelRatio.toStringAsFixed(3),
      );
    } catch (_) {
      return (width: null, height: null, density: null);
    }
  }

  Future<DeviceHardwareInfo> collect() async {
    final screen = _screen();
    try {
      if (Platform.isAndroid) {
        final a = await _plugin.androidInfo;
        return DeviceHardwareInfo(
          deviceModel: _clean(a.model),
          deviceManufacturer: _clean(a.manufacturer),
          // Shortest side in dp (physical px / devicePixelRatio) at 600+ is
          // the standard Android tablet heuristic.
          deviceKind:
              _androidTablet(screen.width, screen.height, screen.density)
                  ? 'tablet'
                  : 'phone',
          cpuType:
              a.supportedAbis.isEmpty ? null : _clean(a.supportedAbis.first),
          osBuild: _clean(a.id),
          osVersion: _clean(a.version.release),
          isPhysicalDevice: a.isPhysicalDevice,
          screenWidth: screen.width,
          screenHeight: screen.height,
          screenDensity: screen.density,
        );
      }
      if (Platform.isIOS) {
        final i = await _plugin.iosInfo;
        final machine = _clean(i.utsname.machine);
        // modelName is "Unknown device" for identifiers newer than the
        // resolved device_info_plus release.
        final modelName = _clean(i.modelName);
        return DeviceHardwareInfo(
          deviceModel:
              (modelName == null || modelName == 'Unknown device')
                  ? machine
                  : modelName,
          deviceManufacturer: 'Apple',
          // UIDevice.model is "iPhone" / "iPad" regardless of generation.
          deviceKind:
              i.model.toLowerCase().contains('ipad') ? 'tablet' : 'phone',
          cpuType: 'arm64',
          osVersion: _clean(i.systemVersion),
          isPhysicalDevice: i.isPhysicalDevice,
          screenWidth: screen.width,
          screenHeight: screen.height,
          screenDensity: screen.density,
        );
      }
    } catch (_) {
      // Attribution enrichment must never break install tracking.
    }
    return DeviceHardwareInfo(
      screenWidth: screen.width,
      screenHeight: screen.height,
      screenDensity: screen.density,
    );
  }

  static bool _androidTablet(String? w, String? h, String? dpr) {
    final width = double.tryParse(w ?? '');
    final height = double.tryParse(h ?? '');
    final density = double.tryParse(dpr ?? '');
    if (width == null || height == null || density == null || density <= 0) {
      return false;
    }
    final shortestDp = (width < height ? width : height) / density;
    return shortestDp >= 600;
  }

  static String? _clean(String? value) {
    final v = value?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}
