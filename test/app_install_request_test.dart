import 'package:flutter_dectog/flutter_dectog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy fields serialize exactly as before (backcompat)', () {
    const request = DectogAppInstallRequest(
      appPlatform: 'flutter',
      appVersion: '1.0.0',
      appBuildNumber: '42',
      os: 'android',
      osVersion: 'Android 15',
      language: 'en_US',
      timezone: 'UTC',
      installReferrer: 'dtg_click=abc123',
    );
    final json = request.toJson();
    expect(
      json.keys,
      containsAll([
        'app_platform',
        'app_version',
        'app_build_number',
        'os',
        'os_version',
        'language',
        'timezone',
        'install_referrer',
      ]),
    );
    expect(
      json.keys.where(
        (k) =>
            k.startsWith(RegExp('device|ad_|cpu|screen|connectivity|carrier')),
      ),
      isEmpty,
    );
  });

  test('device-tier fields are emitted and omit-if-null', () {
    const withAll = DectogAppInstallRequest(
      os: 'android',
      deviceId: '8af8770a27cfd182',
      deviceModel: 'Pixel 9',
      deviceManufacturer: 'Google',
      deviceKind: 'phone',
      cpuType: 'arm64-v8a',
      osBuild: 'AP4A.250105.002',
      screenWidth: '1080',
      screenHeight: '2424',
      screenDensity: '2.625',
      connectivityType: 'wifi',
      carrierMcc: '310',
      carrierMnc: '260',
    );
    final json = withAll.toJson();
    expect(json['device_id'], '8af8770a27cfd182');
    expect(json['carrier_mcc'], '310');
    expect(json['screen_width'], '1080');

    const minimal = DectogAppInstallRequest(os: 'ios');
    final minimalJson = minimal.toJson();
    expect(minimalJson.containsKey('device_id'), isFalse);
    expect(minimalJson.containsKey('ad_id'), isFalse);
    expect(minimalJson.containsKey('screen_width'), isFalse);
  });

  test('fromJson roundtrips the device tier', () {
    const request = DectogAppInstallRequest(
      os: 'ios',
      deviceId: '7946DA4E-8429-423C-B405-B3FC77914E3E',
      deviceModel: 'iPhone 15 Pro Max',
      deviceManufacturer: 'Apple',
      deviceKind: 'phone',
      screenWidth: '1170',
      screenHeight: '2532',
      screenDensity: '3.000',
      connectivityType: 'cellular',
    );
    final roundtripped = DectogAppInstallRequest.fromJson(request.toJson());
    expect(roundtripped.deviceId, request.deviceId);
    expect(roundtripped.deviceModel, request.deviceModel);
    expect(roundtripped.screenWidth, '1170');
    expect(roundtripped.screenHeight, '2532');
    // Wire format: _screen() emits toStringAsFixed(3), so a 3x screen sends
    // '3.000', not '3'.
    expect(roundtripped.screenDensity, '3.000');
    expect(roundtripped.connectivityType, request.connectivityType);
  });

  test(
    'the UTC offset and the settings serialize, omit-if-null and round-trip',
    () {
      const withAll = DectogAppInstallRequest(
        os: 'ios',
        timezone: '3:00:00.000000',
        utcOffsetMin: 180,
        textSize: 19,
        darkMode: true,
        highContrast: false,
        reduceMotion: true,
      );
      final json = withAll.toJson();
      expect(json['utc_offset_min'], 180);
      expect(json['text_size'], 19);
      expect(json['dark_mode'], isTrue);
      expect(json['high_contrast'], isFalse);
      expect(json['reduce_motion'], isTrue);

      final minimal = const DectogAppInstallRequest(os: 'android').toJson();
      for (final key in [
        'utc_offset_min',
        'text_size',
        'dark_mode',
        'high_contrast',
        'reduce_motion',
      ]) {
        expect(minimal.containsKey(key), isFalse, reason: key);
      }

      final roundtripped = DectogAppInstallRequest.fromJson(json);
      expect(roundtripped.utcOffsetMin, 180);
      expect(roundtripped.textSize, 19);
      expect(roundtripped.darkMode, isTrue);
      expect(roundtripped.highContrast, isFalse);
      expect(roundtripped.reduceMotion, isTrue);

      // West of UTC is negative.
      expect(
        DectogAppInstallRequest.fromJson({'utc_offset_min': -420}).utcOffsetMin,
        -420,
      );
    },
  );

  test('withdrawn probe signals are absent from the wire format', () {
    const request = DectogAppInstallRequest(os: 'android');
    expect(request.toJson().keys.where((k) => k.startsWith('fp_')), isEmpty);
  });

  test('provenance tier serializes and roundtrips', () {
    const withAll = DectogAppInstallRequest(
      os: 'android',
      packageName: 'com.example.demoapp',
      isPhysicalDevice: true,
      installerPackage: 'com.android.vending',
      installTime: 1760000020000,
      updateTime: 1760005000000,
      referrerClickTs: 1760000000000,
      installBeginTs: 1760000020000,
      webUserAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 8)',
      metaReferrer: 'utm_source=facebook&dtg_click=abc',
      metaReferrerTs: 1759999999000,
      metaReferrerIsCt: true,
      clipboardUrl: 'https://demo.dectog.com/welcome?dtg_click=abc',
    );
    final json = withAll.toJson();
    expect(json['package_name'], 'com.example.demoapp');
    expect(json['is_physical_device'], isTrue);
    expect(json['installer_package'], 'com.android.vending');
    expect(json['install_time'], 1760000020000);
    expect(json['update_time'], 1760005000000);
    expect(json['referrer_click_ts'], 1760000000000);
    expect(json['install_begin_ts'], 1760000020000);
    expect(json['web_user_agent'], contains('Pixel 8'));
    expect(json['meta_referrer'], contains('dtg_click'));
    expect(json['meta_referrer_is_ct'], isTrue);
    expect(json['clipboard_url'], contains('dtg_click'));

    final minimal = DectogAppInstallRequest(os: 'ios');
    final minimalJson = minimal.toJson();
    for (final key in [
      'package_name',
      'is_physical_device',
      'installer_package',
      'install_time',
      'update_time',
      'referrer_click_ts',
      'install_begin_ts',
      'web_user_agent',
      'meta_referrer',
      'meta_referrer_ts',
      'meta_referrer_is_ct',
      'clipboard_url',
    ]) {
      expect(minimalJson.containsKey(key), isFalse, reason: key);
    }

    final roundtripped = DectogAppInstallRequest.fromJson(withAll.toJson());
    expect(roundtripped.packageName, withAll.packageName);
    expect(roundtripped.isPhysicalDevice, isTrue);
    expect(roundtripped.installTime, 1760000020000);
    expect(roundtripped.updateTime, 1760005000000);
    expect(roundtripped.referrerClickTs, 1760000000000);
    expect(roundtripped.clipboardUrl, withAll.clipboardUrl);
  });

  test('contract v2 fields serialize, omit-if-null and round-trip', () {
    const withAll = DectogAppInstallRequest(
      os: 'android',
      installReferrer: 'dtg_click=abc&dtg_l=demo/welcome',
      installAttemptId: '8b1e2b0a-7c1d-4f3e-9a2b-1c2d3e4f5a6b',
      attempt: 2,
      createdAtClient: '2026-10-12T09:00:00.000Z',
      sentAtClient: '2026-10-12T09:00:04.000Z',
      referrerStatus: 'ok',
      referrerAttempts: 3,
      referrerWaitMs: 4200,
      referrerClickServerTs: 1760000001000,
      installBeginServerTs: 1760000021000,
      installVersion: '1.2.3',
      googlePlayInstant: false,
      referrerStore: 'google_play',
      installState: 'install',
      firstInstallTs: 1760000020000,
      asaToken: 'AAAA==',
    );
    final json = withAll.toJson();
    expect(json['install_attempt_id'], '8b1e2b0a-7c1d-4f3e-9a2b-1c2d3e4f5a6b');
    expect(json['attempt'], 2);
    expect(json['created_at_client'], '2026-10-12T09:00:00.000Z');
    expect(json['sent_at_client'], '2026-10-12T09:00:04.000Z');
    expect(json['referrer_status'], 'ok');
    expect(json['referrer_attempts'], 3);
    expect(json['referrer_wait_ms'], 4200);
    expect(json['referrer_click_server_ts'], 1760000001000);
    expect(json['install_begin_server_ts'], 1760000021000);
    expect(json['install_version'], '1.2.3');
    expect(json['google_play_instant'], isFalse);
    expect(json['referrer_store'], 'google_play');
    expect(json['install_state'], 'install');
    expect(json['first_install_ts'], 1760000020000);
    expect(json['asa_token'], 'AAAA==');

    final minimal = const DectogAppInstallRequest(os: 'ios').toJson();
    for (final key in [
      'install_attempt_id',
      'attempt',
      'created_at_client',
      'sent_at_client',
      'referrer_status',
      'referrer_attempts',
      'referrer_wait_ms',
      'referrer_click_server_ts',
      'install_begin_server_ts',
      'install_version',
      'google_play_instant',
      'referrer_store',
      'install_state',
      'first_install_ts',
      'asa_token',
    ]) {
      expect(minimal.containsKey(key), isFalse, reason: key);
    }

    final roundtripped = DectogAppInstallRequest.fromJson(withAll.toJson());
    expect(roundtripped.installAttemptId, withAll.installAttemptId);
    expect(roundtripped.attempt, 2);
    expect(roundtripped.referrerClickServerTs, 1760000001000);
    expect(roundtripped.googlePlayInstant, isFalse);
    expect(roundtripped.referrerStore, 'google_play');
    expect(roundtripped.installState, 'install');
    expect(roundtripped.asaToken, 'AAAA==');
  });
}
