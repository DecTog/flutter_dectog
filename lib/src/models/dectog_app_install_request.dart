/// App install request model for DecTog
class DectogAppInstallRequest {
  /// App platform
  final String? appPlatform;

  /// App version
  final String? appVersion;

  /// App build number
  final String? appBuildNumber;

  /// Operating system
  final String? os;

  /// Operating system version
  final String? osVersion;

  /// Device language
  final String? language;

  /// Device timezone
  final String? timezone;

  /// The device's current offset from UTC in minutes, east positive
  /// (UTC+3 is 180). Sent with [timezone], outside the device tier.
  final int? utcOffsetMin;

  /// Raw install referrer string of the winning store (Android only; see
  /// [referrerStore]).
  final String? installReferrer;

  /// Additional metadata
  final Map<String, dynamic>? metadata;

  // ---- Device data tier, all optional / omit-if-null ----

  /// First-party device identifier: plain IDFV on iOS (no Keychain
  /// persistence) or `ANDROID_ID` on Android — sent only when the host app
  /// collects `DectogCollection.deviceTier`.
  final String? deviceId;

  /// Hardware fingerprint tier (device_info_plus).
  final String? deviceModel;
  final String? deviceManufacturer;
  final String? deviceKind;
  final String? cpuType;
  final String? osBuild;
  final String? screenWidth;
  final String? screenHeight;
  final String? screenDensity;

  /// Network / carrier tier.
  final String? connectivityType;
  final String? carrierMcc;
  final String? carrierMnc;

  /// Display and accessibility settings tier (PlatformDispatcher), each
  /// null when the platform does not report it.
  ///
  /// [textSize] is the body text size in points for the user's text-size
  /// setting: 14, 15, 16, 17 (the default), 19, 21, 23, then 28 to 53 for
  /// the accessibility sizes. iOS only.
  final int? textSize;

  /// The system appearance is dark.
  final bool? darkMode;

  /// Increase Contrast (iOS only).
  final bool? highContrast;

  /// iOS Reduce Motion; Android Remove animations.
  final bool? reduceMotion;

  // ---- provenance + anti-fraud / deterministic-signal tier ----

  /// Android package name / iOS bundle id of the host app.
  final String? packageName;

  /// device_info_plus isPhysicalDevice; null on old SDKs / desktop.
  final bool? isPhysicalDevice;

  /// Which store delivered the app (package_info_plus `installerStore`,
  /// e.g. `com.android.vending` for Play). sourced from
  /// package_info_plus instead of a hand-rolled channel read.
  final String? installerPackage;

  /// package_info_plus `installTime` (Android PackageManager.firstInstallTime;
  /// iOS = the app documents directory's creation date), epoch ms.
  /// Provenance/fraud-review timestamps — not a match input.
  final int? installTime;

  /// package_info_plus `updateTime` (lastUpdateTime / bundle mtime), epoch ms.
  final int? updateTime;

  /// Install-referrer timestamps as the DEVICE clock reports them, epoch
  /// ms (`getReferrerClickTimestampSeconds` / `getInstallBeginTimestampSeconds`).
  /// The server-side pair below is what
  /// fraud timing trusts.
  final int? referrerClickTs;
  final int? installBeginTs;

  /// The device's WebView User-Agent (Android WebSettings.getDefaultUserAgent;
  /// iOS does not expose one synchronously). Branch-parity fingerprint input.
  final String? webUserAgent;

  /// Meta's on-device install referrer for [DectogConfig.fbAppId], when the
  /// Facebook/Instagram app recorded a click for this app (Android only).
  final String? metaReferrer;
  final int? metaReferrerTs;

  /// Meta's `is_ct` for [metaReferrer]: true for a click-through, false
  /// for a view-through.
  final bool? metaReferrerIsCt;

  /// A DecTog link URL recovered from the pasteboard at first launch
  /// (LinkMe/NativeLink-style; only ever sent when it parses as a DecTog link).
  final String? clipboardUrl;

  // ---- attribution reliability (contract v2) ----

  /// Client idempotency key, persisted before the first POST: a retried
  /// registration returns the stored verdict instead of a second row.
  final String? installAttemptId;

  /// The install id this registration replaces (the server had lost it).
  final String? recoveredFrom;

  /// Cross-launch attempt number of this POST (1 = first launch).
  final int? attempt;

  /// Device-clock ISO times: when the install flow first started / when
  /// this POST left (Adjust `created_at` vs `sent_at`).
  final String? createdAtClient;
  final String? sentAtClient;

  /// Referrer read outcome (`ok`, `organic`, `feature_not_supported`,
  /// `service_unavailable`, `timeout`, …) and its telemetry.
  final String? referrerStatus;
  final int? referrerAttempts;
  final int? referrerWaitMs;

  /// Play Install Referrer SERVER-side timestamps (epoch ms).
  final int? referrerClickServerTs;
  final int? installBeginServerTs;

  /// Play `installVersion` / `googlePlayInstantParam`.
  final String? installVersion;
  final bool? googlePlayInstant;

  /// Which store produced [installReferrer]: `google_play` | `huawei` |
  /// `samsung` | `xiaomi` | `vivo`.
  final String? referrerStore;

  /// Client classification: `install` | `reinstall` | `update` (an
  /// existing user updating to an SDK build — never fingerprint-matched).
  final String? installState;

  /// Android `firstInstallTime` / iOS keychain first-install date, epoch ms.
  final int? firstInstallTs;

  /// Apple Search Ads attribution token (AdServices), when enabled.
  final String? asaToken;

  /// The advertising id (IDFA / GAID) from
  /// `DectogConfig.advertisingIdProvider`; stored apart from the device tier.
  final String? adId;

  /// The user limited ad tracking (then [adId] is null).
  final bool? adTrackingLimited;

  const DectogAppInstallRequest({
    this.appPlatform,
    this.appVersion,
    this.appBuildNumber,
    this.os,
    this.osVersion,
    this.language,
    this.timezone,
    this.utcOffsetMin,
    this.installReferrer,
    this.metadata,
    this.deviceId,
    this.deviceModel,
    this.deviceManufacturer,
    this.deviceKind,
    this.cpuType,
    this.osBuild,
    this.screenWidth,
    this.screenHeight,
    this.screenDensity,
    this.connectivityType,
    this.carrierMcc,
    this.carrierMnc,
    this.textSize,
    this.darkMode,
    this.highContrast,
    this.reduceMotion,
    this.packageName,
    this.isPhysicalDevice,
    this.installerPackage,
    this.installTime,
    this.updateTime,
    this.referrerClickTs,
    this.installBeginTs,
    this.webUserAgent,
    this.metaReferrer,
    this.metaReferrerTs,
    this.metaReferrerIsCt,
    this.clipboardUrl,
    this.installAttemptId,
    this.recoveredFrom,
    this.attempt,
    this.createdAtClient,
    this.sentAtClient,
    this.referrerStatus,
    this.referrerAttempts,
    this.referrerWaitMs,
    this.referrerClickServerTs,
    this.installBeginServerTs,
    this.installVersion,
    this.googlePlayInstant,
    this.referrerStore,
    this.installState,
    this.firstInstallTs,
    this.asaToken,
    this.adId,
    this.adTrackingLimited,
  });

  /// Convert to JSON for API request
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (appPlatform != null) json['app_platform'] = appPlatform;
    if (appVersion != null) json['app_version'] = appVersion;
    if (appBuildNumber != null) json['app_build_number'] = appBuildNumber;
    if (os != null) json['os'] = os;
    if (osVersion != null) json['os_version'] = osVersion;
    if (language != null) json['language'] = language;
    if (timezone != null) json['timezone'] = timezone;
    if (utcOffsetMin != null) json['utc_offset_min'] = utcOffsetMin;
    if (installReferrer != null) json['install_referrer'] = installReferrer;
    if (metadata != null) json['metadata'] = metadata;

    if (deviceId != null) json['device_id'] = deviceId;
    if (deviceModel != null) json['device_model'] = deviceModel;
    if (deviceManufacturer != null)
      json['device_manufacturer'] = deviceManufacturer;
    if (deviceKind != null) json['device_kind'] = deviceKind;
    if (cpuType != null) json['cpu_type'] = cpuType;
    if (osBuild != null) json['os_build'] = osBuild;
    if (screenWidth != null) json['screen_width'] = screenWidth;
    if (screenHeight != null) json['screen_height'] = screenHeight;
    if (screenDensity != null) json['screen_density'] = screenDensity;
    if (connectivityType != null) json['connectivity_type'] = connectivityType;
    if (carrierMcc != null) json['carrier_mcc'] = carrierMcc;
    if (carrierMnc != null) json['carrier_mnc'] = carrierMnc;
    if (textSize != null) json['text_size'] = textSize;
    if (darkMode != null) json['dark_mode'] = darkMode;
    if (highContrast != null) json['high_contrast'] = highContrast;
    if (reduceMotion != null) json['reduce_motion'] = reduceMotion;

    if (packageName != null) json['package_name'] = packageName;
    if (isPhysicalDevice != null) json['is_physical_device'] = isPhysicalDevice;
    if (installerPackage != null) json['installer_package'] = installerPackage;
    if (installTime != null) json['install_time'] = installTime;
    if (updateTime != null) json['update_time'] = updateTime;
    if (referrerClickTs != null) json['referrer_click_ts'] = referrerClickTs;
    if (installBeginTs != null) json['install_begin_ts'] = installBeginTs;
    if (webUserAgent != null) json['web_user_agent'] = webUserAgent;
    if (metaReferrer != null) json['meta_referrer'] = metaReferrer;
    if (metaReferrerTs != null) json['meta_referrer_ts'] = metaReferrerTs;
    if (metaReferrerIsCt != null)
      json['meta_referrer_is_ct'] = metaReferrerIsCt;
    if (clipboardUrl != null) json['clipboard_url'] = clipboardUrl;

    if (installAttemptId != null) json['install_attempt_id'] = installAttemptId;
    if (recoveredFrom != null) json['recovered_from'] = recoveredFrom;
    if (attempt != null) json['attempt'] = attempt;
    if (createdAtClient != null) json['created_at_client'] = createdAtClient;
    if (sentAtClient != null) json['sent_at_client'] = sentAtClient;
    if (referrerStatus != null) json['referrer_status'] = referrerStatus;
    if (referrerAttempts != null) json['referrer_attempts'] = referrerAttempts;
    if (referrerWaitMs != null) json['referrer_wait_ms'] = referrerWaitMs;
    if (referrerClickServerTs != null)
      json['referrer_click_server_ts'] = referrerClickServerTs;
    if (installBeginServerTs != null)
      json['install_begin_server_ts'] = installBeginServerTs;
    if (installVersion != null) json['install_version'] = installVersion;
    if (googlePlayInstant != null)
      json['google_play_instant'] = googlePlayInstant;
    if (referrerStore != null) json['referrer_store'] = referrerStore;
    if (installState != null) json['install_state'] = installState;
    if (firstInstallTs != null) json['first_install_ts'] = firstInstallTs;
    if (asaToken != null) json['asa_token'] = asaToken;
    if (adId != null) json['ad_id'] = adId;
    if (adTrackingLimited != null) {
      json['ad_tracking_limited'] = adTrackingLimited;
    }

    return json;
  }

  /// Create from JSON
  factory DectogAppInstallRequest.fromJson(Map<String, dynamic> json) {
    return DectogAppInstallRequest(
      appPlatform: json['app_platform'] as String?,
      appVersion: json['app_version'] as String?,
      appBuildNumber: json['app_build_number'] as String?,
      os: json['os'] as String?,
      osVersion: json['os_version'] as String?,
      language: json['language'] as String?,
      timezone: json['timezone'] as String?,
      utcOffsetMin: (json['utc_offset_min'] as num?)?.toInt(),
      installReferrer: json['install_referrer'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      deviceId: json['device_id'] as String?,
      deviceModel: json['device_model'] as String?,
      deviceManufacturer: json['device_manufacturer'] as String?,
      deviceKind: json['device_kind'] as String?,
      cpuType: json['cpu_type'] as String?,
      osBuild: json['os_build'] as String?,
      screenWidth: json['screen_width'] as String?,
      screenHeight: json['screen_height'] as String?,
      screenDensity: json['screen_density'] as String?,
      connectivityType: json['connectivity_type'] as String?,
      carrierMcc: json['carrier_mcc'] as String?,
      carrierMnc: json['carrier_mnc'] as String?,
      textSize: (json['text_size'] as num?)?.toInt(),
      darkMode: json['dark_mode'] as bool?,
      highContrast: json['high_contrast'] as bool?,
      reduceMotion: json['reduce_motion'] as bool?,
      packageName: json['package_name'] as String?,
      isPhysicalDevice: json['is_physical_device'] as bool?,
      installerPackage: json['installer_package'] as String?,
      installTime: (json['install_time'] as num?)?.toInt(),
      updateTime: (json['update_time'] as num?)?.toInt(),
      referrerClickTs: (json['referrer_click_ts'] as num?)?.toInt(),
      installBeginTs: (json['install_begin_ts'] as num?)?.toInt(),
      webUserAgent: json['web_user_agent'] as String?,
      metaReferrer: json['meta_referrer'] as String?,
      metaReferrerTs: (json['meta_referrer_ts'] as num?)?.toInt(),
      metaReferrerIsCt: json['meta_referrer_is_ct'] as bool?,
      clipboardUrl: json['clipboard_url'] as String?,
      installAttemptId: json['install_attempt_id'] as String?,
      recoveredFrom: json['recovered_from'] as String?,
      attempt: (json['attempt'] as num?)?.toInt(),
      createdAtClient: json['created_at_client'] as String?,
      sentAtClient: json['sent_at_client'] as String?,
      referrerStatus: json['referrer_status'] as String?,
      referrerAttempts: (json['referrer_attempts'] as num?)?.toInt(),
      referrerWaitMs: (json['referrer_wait_ms'] as num?)?.toInt(),
      referrerClickServerTs:
          (json['referrer_click_server_ts'] as num?)?.toInt(),
      installBeginServerTs: (json['install_begin_server_ts'] as num?)?.toInt(),
      installVersion: json['install_version'] as String?,
      googlePlayInstant: json['google_play_instant'] as bool?,
      referrerStore: json['referrer_store'] as String?,
      installState: json['install_state'] as String?,
      firstInstallTs: (json['first_install_ts'] as num?)?.toInt(),
      asaToken: json['asa_token'] as String?,
      adId: json['ad_id'] as String?,
      adTrackingLimited: json['ad_tracking_limited'] as bool?,
    );
  }

  @override
  String toString() {
    return 'DectogAppInstallRequest{appPlatform: $appPlatform, appVersion: $appVersion, '
        'appBuildNumber: $appBuildNumber, os: $os, osVersion: $osVersion, language: $language, '
        'timezone: $timezone, utcOffsetMin: $utcOffsetMin, '
        'installReferrer: $installReferrer, referrerStore: $referrerStore, '
        'referrerStatus: $referrerStatus, installState: $installState, attempt: $attempt, '
        'installAttemptId: $installAttemptId, deviceId: $deviceId, '
        'deviceModel: $deviceModel, deviceKind: $deviceKind, '
        'screenWidth: $screenWidth, screenHeight: $screenHeight, '
        'screenDensity: $screenDensity, '
        'connectivityType: $connectivityType, carrierMcc: $carrierMcc, '
        'textSize: $textSize, darkMode: $darkMode, highContrast: $highContrast, '
        'reduceMotion: $reduceMotion, metadata: $metadata}';
  }
}

class AppInfo {
  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;

  /// package_info_plus extras: signing-key hex on Android (''
  /// elsewhere), the delivering store, and package-manager install/update
  /// timestamps (null where the platform has no equivalent).
  final String buildSignature;
  final String? installerStore;
  final DateTime? installTime;
  final DateTime? updateTime;

  AppInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
    this.buildSignature = '',
    this.installerStore,
    this.installTime,
    this.updateTime,
  });

  int? get installTimeMs =>
      installTime == null ? null : installTime!.millisecondsSinceEpoch;
  int? get updateTimeMs =>
      updateTime == null ? null : updateTime!.millisecondsSinceEpoch;
}
