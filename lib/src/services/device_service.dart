import 'dart:io';

/// Service for collecting device information for app install tracking
class DeviceService {
  static final DeviceService _instance = DeviceService._internal();

  /// Singleton instance
  factory DeviceService() => _instance;

  DeviceService._internal();

  /// Get the current platform name
  String getPlatform() {
    if (Platform.isAndroid) {
      return 'android';
    } else if (Platform.isIOS) {
      return 'ios';
    } else if (Platform.isMacOS) {
      return 'macos';
    } else if (Platform.isWindows) {
      return 'windows';
    } else if (Platform.isLinux) {
      return 'linux';
    } else {
      return 'unknown';
    }
  }

  /// Get operating system name
  String getOperatingSystem() {
    return Platform.operatingSystem;
  }

  /// Get operating system version
  String getOperatingSystemVersion() {
    return Platform.operatingSystemVersion;
  }

  /// Get device language/locale
  String getLanguage() {
    try {
      return Platform.localeName;
    } catch (e) {
      return 'unknown';
    }
  }

  /// Get device timezone
  String getTimezone() {
    try {
      final now = DateTime.now();
      return now.timeZoneOffset.toString();
    } catch (e) {
      return 'unknown';
    }
  }

  /// The device's current offset from UTC in minutes, east positive
  /// (UTC+3 is 180); null when it cannot be read.
  int? getUtcOffsetMinutes() {
    try {
      return DateTime.now().timeZoneOffset.inMinutes;
    } catch (e) {
      return null;
    }
  }

  /// Get Dart version
  String getDartVersion() {
    try {
      return Platform.version.split(' ').first;
    } catch (e) {
      return 'unknown';
    }
  }

  /// Check if running on mobile platform
  bool isMobile() {
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Get app platform identifier for API
  String getAppPlatform() {
    return 'flutter';
  }

  /// Collect basic device information
  Map<String, dynamic> getDeviceInfo() {
    return {
      'platform': getPlatform(),
      'os': getOperatingSystem(),
      'os_version': getOperatingSystemVersion(),
      'language': getLanguage(),
      'timezone': getTimezone(),
      'utc_offset_min': getUtcOffsetMinutes(),
      'dart_version': getDartVersion(),
      'is_mobile': isMobile(),
    };
  }
}
