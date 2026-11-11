import 'adto_environment.dart';

/// The app's SDK settings as the server holds them
/// (`GET /api/v1/sdk-config`). The SDK reads them at start-up, caches them
/// for [cacheSeconds], and lets an explicit `AdtoConfig` value win.
class AdtoSdkConfig {
  const AdtoSdkConfig({
    required this.appId,
    this.fbAppId,
    this.oemStoreReferrers = true,
    this.readClipboardOnInstall,
    this.iosTapToStore = false,
    this.iosAppScheme,
    this.androidAppScheme,
    this.iosBundleId,
    this.androidPackage,
    this.linkHosts = const [],
    this.username,
    this.environment = AdtoEnvironment.live,
    this.cacheSeconds = 3600,
  });

  final String appId;

  /// The Facebook App ID for Meta's on-device install referrer (Android).
  final String? fbAppId;

  /// Whether to read the Huawei, Samsung, Xiaomi and vivo store referrers.
  final bool oemStoreReferrers;

  /// The first-launch pasteboard read; null leaves it to the platform
  /// default (iOS on, Android off).
  final bool? readClipboardOnInstall;
  final bool iosTapToStore;
  final String? iosAppScheme;
  final String? androidAppScheme;
  final String? iosBundleId;
  final String? androidPackage;

  /// The hosts this account's links live on: the active custom domain
  /// first, then the default host.
  final List<String> linkHosts;

  /// The account the key belongs to, so a link on a custom domain
  /// maps to it without a round trip.
  final String? username;

  /// The environment of the key's account.
  final AdtoEnvironment environment;
  final int cacheSeconds;

  factory AdtoSdkConfig.fromJson(Map<String, dynamic> json) => AdtoSdkConfig(
    appId: json['app_id'] as String? ?? '',
    fbAppId: json['fb_app_id'] as String?,
    oemStoreReferrers: json['oem_store_referrers'] as bool? ?? true,
    readClipboardOnInstall: json['read_clipboard_on_install'] as bool?,
    iosTapToStore: json['ios_tap_to_store'] as bool? ?? false,
    iosAppScheme: json['ios_app_scheme'] as String?,
    androidAppScheme: json['android_app_scheme'] as String?,
    iosBundleId: json['ios_bundle_id'] as String?,
    androidPackage: json['android_package'] as String?,
    linkHosts:
        (json['link_hosts'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
    username: json['username'] as String?,
    environment:
        json['environment'] == 'test'
            ? AdtoEnvironment.test
            : AdtoEnvironment.live,
    cacheSeconds: (json['cache_seconds'] as num?)?.toInt() ?? 3600,
  );

  Map<String, dynamic> toJson() => {
    'app_id': appId,
    'fb_app_id': fbAppId,
    'oem_store_referrers': oemStoreReferrers,
    'read_clipboard_on_install': readClipboardOnInstall,
    'ios_tap_to_store': iosTapToStore,
    'ios_app_scheme': iosAppScheme,
    'android_app_scheme': androidAppScheme,
    'ios_bundle_id': iosBundleId,
    'android_package': androidPackage,
    'link_hosts': linkHosts,
    'username': username,
    'environment': environment.name,
    'cache_seconds': cacheSeconds,
  };
}

/// What `FlutterAdto.diagnostics()` found. [warnings] is empty when
/// the app's own setup matches the dashboard's record of it.
class AdtoDiagnostics {
  const AdtoDiagnostics({this.serverConfig, this.warnings = const []});

  /// The settings the server holds for this app (null when unreachable).
  final AdtoSdkConfig? serverConfig;

  /// Human-readable problems, e.g. a URL scheme missing from Info.plist or a
  /// link host Android has not verified.
  final List<String> warnings;

  bool get ok => warnings.isEmpty;

  @override
  String toString() =>
      ok ? 'AdtoDiagnostics(ok)' : 'AdtoDiagnostics(${warnings.join('; ')})';
}
