import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_adto/src/services/identifier_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('adto_device_identifiers');

  void mockMetaReferrer(Object? reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getMetaReferrer');
          expect(call.arguments, {'fbAppId': '123'});
          return reply;
        });
  }

  void mock(Map<String, Object? Function(MethodCall call)> handlers) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final h = handlers[call.method];
          if (h == null) throw MissingPluginException(call.method);
          return h(call);
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getMetaReferrer parses referrer, ts and isCt', () async {
    mockMetaReferrer({
      'referrer': 'utm_source=fb',
      'ts': 1759999999000,
      'isCt': false,
    });
    final r = await IdentifierChannel().getMetaReferrer(' 123 ');
    expect(r?.referrer, 'utm_source=fb');
    expect(r?.ts, 1759999999000);
    expect(r?.isCt, isFalse);
  });

  test('getMetaReferrer leaves optional fields null when absent', () async {
    mockMetaReferrer({'referrer': 'utm_source=fb'});
    final r = await IdentifierChannel().getMetaReferrer('123');
    expect(r?.ts, isNull);
    expect(r?.isCt, isNull);
  });

  test(
    'every contract-v2 method degrades to null/false when the native side lacks it',
    () async {
      // No mock handler at all → MissingPluginException on every call.
      final c = IdentifierChannel();
      expect(
        await c.getInstallReferrers(
          timeoutMs: 100,
          stores: const ['google_play'],
        ),
        isNull,
      );
      expect(await c.getNoBackupDirectory(), isNull);
      expect(await c.getPackageInstallInfo(), isNull);
      expect(await c.getLaunchInfo(), isNull);
      expect(await c.getInstallDates(), isNull);
      expect(await c.excludeFromBackup('/x'), isFalse);
      expect(await c.getAttributionToken(), isNull);
      expect(await c.pasteboardHasUrl(), isFalse);
      expect(await c.readPasteboardUrl(), isNull);
      expect(await c.clearPasteboard(), isFalse);
    },
  );

  test('PlatformException degrades the same way', () async {
    mock({'getLaunchInfo': (_) => throw PlatformException(code: 'boom')});
    expect(await IdentifierChannel().getLaunchInfo(), isNull);
  });

  test(
    'provenance, launch info, install dates and pasteboard parse per contract',
    () async {
      mock({
        'getNoBackupDirectory': (_) => '/data/user/0/app/no_backup',
        'getPackageInstallInfo':
            (_) => {
              'firstInstallTime': 1760000000000,
              'lastUpdateTime': 1760000500000,
              'versionCode': 42,
              'installer': 'com.android.vending',
            },
        'getLaunchInfo':
            (_) => {
              'fromHistory': true,
              'hasIntentData': true,
              'referrer': 'android-app://com.whatsapp',
            },
        'getInstallDates':
            (_) => {
              'executableCtime': 1,
              'libraryCtime': 2,
              'documentsCtime': 3,
              'keychainFirstInstall': 4,
            },
        'excludeFromBackup': (call) {
          expect(call.arguments, {'path': '/tmp/adto'});
          return true;
        },
        'getAttributionToken': (_) => 'token==',
        'pasteboardHasUrl': (_) => true,
        'readPasteboardUrl': (_) => ' https://demo.adto.app/x?dtg_click=1 ',
        'clearPasteboard': (_) => true,
      });
      final c = IdentifierChannel();
      expect(await c.getNoBackupDirectory(), '/data/user/0/app/no_backup');
      final pkg = await c.getPackageInstallInfo();
      expect(pkg?.firstInstallTime, 1760000000000);
      expect(pkg?.lastUpdateTime, 1760000500000);
      expect(pkg?.versionCode, 42);
      expect(pkg?.installer, 'com.android.vending');
      final launch = await c.getLaunchInfo();
      expect(launch?.fromHistory, isTrue);
      expect(launch?.referrer, 'android-app://com.whatsapp');
      final dates = await c.getInstallDates();
      expect(dates?.executableCtime, 1);
      expect(dates?.keychainFirstInstall, 4);
      expect(dates?.keychainLatestInstall, isNull);
      expect(await c.excludeFromBackup('/tmp/adto'), isTrue);
      expect(await c.getAttributionToken(), 'token==');
      expect(await c.pasteboardHasUrl(), isTrue);
      expect(
        await c.readPasteboardUrl(),
        'https://demo.adto.app/x?dtg_click=1',
      );
      expect(await c.clearPasteboard(), isTrue);
    },
  );

  test(
    'getInstallReferrers parses every store entry and tolerates extra keys',
    () async {
      mock({
        'getInstallReferrers': (call) {
          expect(call.arguments, {
            'timeoutMs': 5000,
            'stores': ['google_play', 'huawei'],
          });
          return {
            'google_play': {
              'status': 'service_unavailable',
              'attempts': 3,
              'waitMs': 9000,
              'error': 'disconnected',
            },
            'huawei': {
              'status': 'ok',
              'referrer': 'dtg_click=h',
              'clickTs': 10,
              'installBeginTs': 20,
              'attempts': 1,
              'waitMs': 40,
              'trackId': 't',
            },
          };
        },
      });
      final all = await IdentifierChannel().getInstallReferrers(
        timeoutMs: 5000,
        stores: const ['google_play', 'huawei'],
      );
      expect(all!.keys, containsAll(['google_play', 'huawei']));
      expect(all['google_play']!.status, 'service_unavailable');
      expect(all['google_play']!.attempts, 3);
      expect(all['google_play']!.error, 'disconnected');
      expect(all['huawei']!.referrer, 'dtg_click=h');
      expect(all['huawei']!.installBeginTs, 20);
      expect(all['huawei']!.hasReferrer, isTrue);
    },
  );

  test(
    'onPasteControlUrl delivers URLs the native side pushes on the channel',
    () async {
      final c = IdentifierChannel();
      final received = <String>[];
      final sub = c.onPasteControlUrl.listen(received.add);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Future<void> push(Object? args) async {
        final completer = Completer<ByteData?>();
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall('onPasteControlUrl', args)),
          completer.complete,
        );
        await completer.future;
      }

      await push({'url': 'https://demo.adto.app/invite?dtg_click=p1'});
      await push({'url': '   '}); // blank: ignored
      await push(
        'https://demo.adto.app/invite?dtg_click=p2',
      ); // bare string also accepted
      await Future<void>.delayed(Duration.zero);
      expect(received, [
        'https://demo.adto.app/invite?dtg_click=p1',
        'https://demo.adto.app/invite?dtg_click=p2',
      ]);
      await sub.cancel();
    },
  );
}
