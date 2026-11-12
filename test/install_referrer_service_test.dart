import 'package:flutter/services.dart';
import 'package:flutter_adto/src/services/identifier_channel.dart';
import 'package:flutter_adto/src/services/install_referrer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('adto_device_identifiers');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  StoreReferrer sr(
    String store, {
    String status = 'ok',
    String? referrer,
    int? installBegin,
    int attempts = 1,
    int waitMs = 100,
  }) => StoreReferrer(
    store: store,
    status: status,
    referrer: referrer,
    installBeginTs: installBegin,
    attempts: attempts,
    waitMs: waitMs,
  );

  group('pickWinner', () {
    test(
      'the store whose install began last wins; telemetry is aggregated',
      () {
        final r = InstallReferrerService.pickWinner({
          'google_play': sr(
            'google_play',
            referrer: 'adto_click=a',
            installBegin: 1000,
            attempts: 2,
            waitMs: 3000,
          ),
          'huawei': sr(
            'huawei',
            referrer: 'adto_click=b',
            installBegin: 2000,
            attempts: 1,
            waitMs: 500,
          ),
        });
        expect(r.status, ReferrerStatus.ok);
        expect(r.store, 'huawei');
        expect(r.referrer, 'adto_click=b');
        expect(r.attempts, 3);
        expect(r.waitMs, 3000);
        expect(r.hasReferrer, isTrue);
        expect(r.isDefinitive, isTrue);
      },
    );

    test('google_play wins ties and unknown timestamps', () {
      final r = InstallReferrerService.pickWinner({
        'samsung': sr('samsung', referrer: 'adto_click=s'),
        'google_play': sr('google_play', referrer: 'adto_click=g'),
      });
      expect(r.store, 'google_play');
    });

    test("Play's organic marker is organic, not a referrer", () {
      final r = InstallReferrerService.pickWinner({
        'google_play': sr(
          'google_play',
          referrer: ReferrerResult.organicPlayReferrer,
        ),
      });
      expect(r.status, ReferrerStatus.organic);
      expect(r.hasReferrer, isFalse);
      expect(r.isDefinitive, isTrue);
    });

    test(
      'an empty ok read is organic; a transient failure stays non-definitive',
      () {
        expect(
          InstallReferrerService.pickWinner({
            'google_play': sr('google_play', referrer: ''),
          }).status,
          ReferrerStatus.organic,
        );
        final unavailable = InstallReferrerService.pickWinner({
          'google_play': sr(
            'google_play',
            status: ReferrerStatus.serviceUnavailable,
            attempts: 3,
          ),
        });
        expect(unavailable.status, ReferrerStatus.serviceUnavailable);
        expect(unavailable.isDefinitive, isFalse);
        expect(unavailable.attempts, 3);
      },
    );

    test(
      "feature_not_supported is definitive; an OEM referrer still wins over Play's failure",
      () {
        expect(
          ReferrerStatus.isDefinitive(ReferrerStatus.featureNotSupported),
          isTrue,
        );
        expect(
          ReferrerStatus.isDefinitive(ReferrerStatus.notAvailable),
          isTrue,
        );
        expect(ReferrerStatus.isDefinitive(ReferrerStatus.timeout), isFalse);
        final r = InstallReferrerService.pickWinner({
          'google_play': sr('google_play', status: ReferrerStatus.notAvailable),
          'vivo': sr(
            'vivo',
            referrer: 'adto_click=v&adto_l=u/s',
            installBegin: 5,
          ),
        });
        expect(r.store, 'vivo');
        expect(r.status, ReferrerStatus.ok);
      },
    );

    test('nothing attempted is not_available', () {
      expect(
        InstallReferrerService.pickWinner({}).status,
        ReferrerStatus.notAvailable,
      );
    });
  });

  group('read', () {
    test(
      'non-Android platforms report not_android without touching the channel',
      () async {
        var called = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              called = true;
              return null;
            });
        final read = await InstallReferrerService().read(
          timeout: const Duration(seconds: 1),
          oemStores: true,
          isAndroid: false,
        );
        expect(read.result.status, ReferrerStatus.notAndroid);
        expect(called, isFalse);
      },
    );

    test('parses the native map, passing timeout and the store list', () async {
      Object? args;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getInstallReferrers');
            args = call.arguments;
            return {
              'google_play': {
                'status': 'ok',
                'referrer': 'adto_click=abc&adto_l=demo/welcome',
                'clickTs': 1760000000000,
                'installBeginTs': 1760000020000,
                'clickServerTs': 1760000001000,
                'installBeginServerTs': 1760000021000,
                'installVersion': '1.2.3',
                'instant': false,
                'attempts': 2,
                'waitMs': 3200,
              },
              'huawei': {
                'status': 'not_available',
                'attempts': 1,
                'waitMs': 10,
                'adsReferrer': 'x',
                'trackId': 'y',
              },
            };
          });
      final read = await InstallReferrerService().read(
        timeout: const Duration(seconds: 2),
        oemStores: true,
        isAndroid: true,
      );
      expect(args, {
        'timeoutMs': 2000,
        'stores': InstallReferrerService.allStores,
      });
      final r = read.result;
      expect(r.store, 'google_play');
      expect(r.referrer, 'adto_click=abc&adto_l=demo/welcome');
      expect(r.clickServerTs, 1760000001000);
      expect(r.installBeginServerTs, 1760000021000);
      expect(r.installVersion, '1.2.3');
      expect(r.instant, isFalse);
      expect(r.attempts, 3);
      expect(read.late, isNull);
    });

    test('only Play is asked when OEM stores are off', () async {
      Object? args;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            args = call.arguments;
            return {
              'google_play': {'status': 'organic', 'attempts': 1, 'waitMs': 50},
            };
          });
      final read = await InstallReferrerService().read(
        timeout: const Duration(seconds: 1),
        oemStores: false,
        isAndroid: true,
      );
      expect((args as Map)['stores'], ['google_play']);
      expect(read.result.status, ReferrerStatus.organic);
    });

    test('a missing native method degrades to not_available', () async {
      final read = await InstallReferrerService().read(
        timeout: const Duration(seconds: 1),
        oemStores: true,
        isAndroid: true,
      );
      expect(read.result.status, ReferrerStatus.notAvailable);
      expect(read.result.isDefinitive, isTrue);
    });

    test(
      'a slow native read times out but keeps the late future alive',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              await Future<void>.delayed(const Duration(milliseconds: 1200));
              return {
                'google_play': {
                  'status': 'ok',
                  'referrer': 'adto_click=late',
                  'attempts': 3,
                  'waitMs': 9000,
                },
              };
            });
        final read = await InstallReferrerService().read(
          timeout: const Duration(milliseconds: 100),
          oemStores: false,
          isAndroid: true,
        );
        expect(read.result.status, ReferrerStatus.timeout);
        expect(read.result.isDefinitive, isFalse);
        expect(read.late, isNotNull);
        final late = await read.late!;
        expect(late.referrer, 'adto_click=late');
        expect(late.status, ReferrerStatus.ok);
      },
    );

    test('a custom provider yields ok / organic / timeout', () async {
      final ok = await InstallReferrerService().read(
        timeout: const Duration(seconds: 1),
        oemStores: true,
        isAndroid: true,
        provider: () async => 'adto_click=p',
      );
      expect(ok.result.status, ReferrerStatus.ok);
      expect(ok.result.store, 'google_play');
      final organic = await InstallReferrerService().read(
        timeout: const Duration(seconds: 1),
        oemStores: true,
        isAndroid: true,
        provider: () async => null,
      );
      expect(organic.result.status, ReferrerStatus.organic);
      final slow = await InstallReferrerService().read(
        timeout: const Duration(milliseconds: 50),
        oemStores: true,
        isAndroid: true,
        provider: () => Future.delayed(const Duration(seconds: 1), () => 'x'),
      );
      expect(slow.result.status, ReferrerStatus.timeout);
    });
  });
}
