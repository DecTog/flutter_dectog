import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_dectog/flutter_dectog.dart';
import 'package:flutter_dectog/src/dectog_impl.dart';
import 'package:flutter_dectog/src/services/device_identity_service.dart';
import 'package:flutter_dectog/src/services/device_settings_service.dart';
import 'package:flutter_dectog/src/services/event_queue_service.dart';
import 'package:flutter_dectog/src/services/install_state_store.dart';
import 'package:flutter_dectog/src/services/sdk_config_store.dart';
import 'package:flutter_dectog/src/services/sdk_state_store.dart';
import 'package:flutter_dectog/src/services/sdk_storage.dart';
import 'package:flutter_dectog/src/version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The SDK driven end to end with its platform plugins faked and a
/// recording HTTP client, so behaviour that spans services can be tested:
/// what the SDK sends, and what it must not send.
class Harness {
  final requests = <http.Request>[];
  late Directory dir;
  String? initialLink;

  /// What the native getDeviceId answers (null: nothing).
  String? deviceId;

  /// Canned answers by path, ahead of the defaults.
  final responses = <String, String>{};

  /// Answers ahead of [responses], for a reply that waits or depends on the
  /// request (null: fall through).
  Future<http.Response?> Function(http.Request request)? answer;

  /// What the native pasteboardChangeCount answers (null: no counter). A
  /// clearPasteboard call is counted in [pasteboardClears] and moves it.
  int? pasteboardChangeCount;
  int pasteboardClears = 0;

  /// What the pasteboard holds for the first-launch read (null: no URL),
  /// and how often the SDK read it.
  String? pasteboardUrl;
  int pasteboardReads = 0;

  Iterable<String> get paths =>
      requests.map((r) => '${r.method} ${r.url.path}');

  /// The display and accessibility settings the SDK reads; set its test
  /// values (text scale, brightness, accessibility features) in a test.
  TestPlatformDispatcher get platformDispatcher =>
      TestWidgetsFlutterBinding.instance.platformDispatcher;

  Future<void> setUp() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    DeviceSettingsService().overrideForTest(platformDispatcher);
    dir = await Directory.systemTemp.createTemp('dectog_harness');
    Future<Directory> provider() async => dir;
    SdkStorage().overrideForTest(provider);
    await SdkStateStore().resetForTest(directoryProvider: provider);
    await InstallStateStore().resetForTest(directoryProvider: provider);
    await EventQueueService().resetForTest(directoryProvider: provider);
    SdkConfigStore().resetForTest(directoryProvider: provider);
    DeviceIdentityService().resetForTest();
    PackageInfo.setMockInitialValues(
      appName: 'Harness',
      packageName: 'app.dectog.harness',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // The SDK's own native channel: every read answers "nothing" but the
    // device id and the pasteboard's counter when a test sets them.
    messenger.setMockMethodCallHandler(_identifiers, (call) async {
      switch (call.method) {
        case 'getDeviceId':
          return deviceId;
        case 'pasteboardChangeCount':
          return pasteboardChangeCount;
        case 'pasteboardHasUrl':
          return pasteboardUrl != null;
        case 'readPasteboardUrl':
          pasteboardReads++;
          return pasteboardUrl;
        case 'clearPasteboard':
          pasteboardClears++;
          pasteboardChangeCount = (pasteboardChangeCount ?? 0) + 1;
          return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/messages'),
      (call) async => call.method == 'getInitialLink' ? initialLink : null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('com.llfbandit.app_links/events'),
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    final organic =
        File(
          'test/fixtures/wire/install-verdict-organic.json',
        ).readAsStringSync();
    FlutterDectogImpl.resetForTest(
      httpClient: MockClient((request) async {
        requests.add(request);
        final answered = await answer?.call(request);
        if (answered != null) return answered;
        final json = {'content-type': 'application/json'};
        final canned = responses[request.url.path];
        if (canned != null) return http.Response(canned, 200, headers: json);
        if (request.url.path == '/api/v1/app-installs') {
          return http.Response(organic, 200, headers: json);
        }
        if (request.url.path.startsWith('/api/v1/resolve/')) {
          return http.Response(
            File('test/fixtures/wire/resolution.json').readAsStringSync(),
            200,
            headers: json,
          );
        }
        return http.Response('{"ok":true}', 200, headers: json);
      }),
    );
  }

  Future<void> tearDown() async {
    SdkStorage().overrideForTest(null);
    platformDispatcher.clearAllTestValues();
    DeviceSettingsService().overrideForTest(null);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// Let fire-and-forget work (click logs, opens, pings) reach the client.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  /// Deliver [url] as the native paste control (UIPasteControl) does.
  Future<void> paste(String url) async {
    final done = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _identifiers.name,
          _identifiers.codec.encodeMethodCall(
            MethodCall('onPasteControlUrl', {'url': url}),
          ),
          done.complete,
        );
    await done.future;
  }
}

const _identifiers = MethodChannel('dectog_device_identifiers');

const config = DectogConfig(
  apiKey: 'dtg_0123456789abcdef0123456789abcdef',
  baseUrl: 'https://app.dectog.com',
  linkRootDomain: 'dectog.com',
);

/// The UTC day the SDK remembers a ping by.
String utcDay(DateTime at) => at.toUtc().toIso8601String().substring(0, 10);

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.setUp();
  });
  tearDown(() => h.tearDown());

  test(
    'enabled (default): the first launch registers the install, signed and identified',
    () async {
      await FlutterDectog().initialize(config);
      await h.settle();
      final installs = h.requests.where(
        (r) => r.url.path == '/api/v1/app-installs',
      );
      expect(installs, hasLength(1));
      final r = installs.single;
      expect(r.headers['x-dectog-sdk'], 'flutter_dectog/$packageVersion');
      expect(r.headers['x-dectog-signature'], startsWith('v1='));
      expect(FlutterDectog().currentAppInstall?.matched, isFalse);
    },
  );

  test('a tapped link is logged as a click and an app open', () async {
    h.initialLink = 'https://demo.dectog.com/spring';
    await FlutterDectog().initialize(config);
    await h.settle();
    expect(h.paths, contains('POST /api/v1/clicks'));
    expect(h.paths, contains('POST /api/v1/app-opens'));
  });

  test(
    'the click report carries the dec_* and utm_* values, never the rest of the URL',
    () async {
      h.initialLink =
          'https://demo.dectog.com/spring?dec_campaign=chat&utm_source=mail&email=ana%40example.com#top';
      await FlutterDectog().initialize(config);
      await h.settle();
      final click = h.requests.singleWhere(
        (r) => r.url.path == '/api/v1/clicks',
      );
      final body = jsonDecode(click.body) as Map<String, dynamic>;
      expect(body['link_params'], {'dec_campaign': 'chat'});
      expect(body['utm_source'], 'mail');
      expect(click.body, isNot(contains('email')));
      expect(click.body, isNot(contains('example.com')));
      expect(click.body, isNot(contains('original_url')));
    },
  );

  test(
    'a link on the custom domain is the account\'s, named by the server settings',
    () async {
      h.responses['/api/v1/sdk-config'] =
          File('test/fixtures/wire/sdk-config.json').readAsStringSync();
      h.initialLink = 'https://go.acme.app/spring';
      await FlutterDectog().initialize(
        const DectogConfig(
          apiKey: 'dtg_0123456789abcdef0123456789abcdef',
          baseUrl: 'https://app.dectog.com',
          linkRootDomain: 'dectog.com',
          linkDomains: ['go.acme.app'],
        ),
      );
      await h.settle();
      expect(h.paths, contains('POST /api/v1/clicks'));
      expect(h.paths, contains('POST /api/v1/app-opens'));
      expect(h.paths, contains('GET /api/v1/resolve/acme/spring'));
    },
  );

  test(
    'before the server names the account, a custom-domain link still counts',
    () async {
      // No sdk-config answer: the account stays unknown.
      h.initialLink = 'https://go.acme.app/spring';
      await FlutterDectog().initialize(
        const DectogConfig(
          apiKey: 'dtg_0123456789abcdef0123456789abcdef',
          baseUrl: 'https://app.dectog.com',
          linkRootDomain: 'dectog.com',
          linkDomains: ['go.acme.app'],
        ),
      );
      await h.settle();
      expect(h.paths, contains('POST /api/v1/clicks'));
      expect(h.paths, contains('POST /api/v1/app-opens'));
      expect(h.paths.where((p) => p.contains('/resolve/')), isEmpty);
    },
  );

  test(
    'handleUrl routes an in-app link once, as an open and not a click',
    () async {
      await FlutterDectog().initialize(config);
      await h.settle();
      final emitted = <DectogLinkClick>[];
      final sub = FlutterDectog().onLinkClick.listen(emitted.add);
      final click = await FlutterDectog().handleUrl(
        'https://demo.dectog.com/spring?utm_source=chat',
      );
      final again = await FlutterDectog().handleUrl(
        'https://demo.dectog.com/spring?utm_source=chat',
      );
      await h.settle();
      await sub.cancel();
      expect(click?.slug, 'spring');
      expect(click?.inApp, isTrue);
      expect(again?.slug, 'spring');
      expect(emitted, hasLength(1));
      expect(h.paths, contains('POST /api/v1/app-opens'));
      expect(h.paths, isNot(contains('POST /api/v1/clicks')));

      // Not a DecTog link, or a sign-in callback: the app opens it itself.
      expect(
        await FlutterDectog().handleUrl('https://example.com/article'),
        isNull,
      );
      expect(await FlutterDectog().handleUrl('not a url'), isNull);
    },
  );

  test(
    'setEnabled(false) persisted: no request at all, then enabling registers the install',
    () async {
      // A previous launch turned collection off.
      await SdkStateStore().setEnabled(false);
      h.initialLink = 'https://demo.dectog.com/spring';

      await FlutterDectog().initialize(config);
      await FlutterDectog().trackEvent('opened_cart');
      await FlutterDectog().identify(customerId: 'cust-1', email: 'a@b.c');
      await h.settle();

      expect(h.paths, isEmpty, reason: 'collection off: no request');
      expect(await FlutterDectog().isEnabled(), isFalse);

      await FlutterDectog().setEnabled(true);
      await h.settle();
      expect(h.paths, contains('POST /api/v1/app-installs'));
      expect(await FlutterDectog().isEnabled(), isTrue);
    },
  );

  group('consent mode', () {
    const waiting = DectogConfig(
      apiKey: 'dtg_0123456789abcdef0123456789abcdef',
      baseUrl: 'https://app.dectog.com',
      linkRootDomain: 'dectog.com',
      enabled: false,
    );

    test(
      'enabled: false sends nothing: launch link, events, identify, attribution pull, in-app link',
      () async {
        h.initialLink = 'https://demo.dectog.com/spring?dec_screen=sale';
        final emitted = <DectogLinkClick>[];
        final sub = FlutterDectog().onLinkClick.listen(emitted.add);
        await FlutterDectog().initialize(waiting);
        await FlutterDectog().trackEvent('opened_cart');
        await FlutterDectog().identify(customerId: 'cust-1');
        expect(await FlutterDectog().getAttributionData(), isNull);
        final inApp = await FlutterDectog().handleUrl(
          'https://demo.dectog.com/summer',
        );
        await FlutterDectog().flush();
        await h.settle();
        await sub.cancel();

        expect(h.paths, isEmpty);
        expect(await FlutterDectog().isEnabled(), isFalse);
        // The app still routes: the links arrive as parsed, without the server's details.
        expect(emitted.map((c) => c.slug), contains('spring'));
        expect(
          emitted.firstWhere((c) => c.slug == 'spring').linkResolution,
          isNull,
        );
        expect(inApp?.slug, 'summer');
        expect(EventQueueService().pendingCount, greaterThanOrEqualTo(2));
      },
    );

    test(
      'consent given: the install registers, the held events go, the launch link is reported',
      () async {
        h.initialLink = 'https://demo.dectog.com/spring';
        await FlutterDectog().initialize(waiting);
        await FlutterDectog().trackEvent('opened_cart');
        await h.settle();
        expect(h.paths, isEmpty);

        await FlutterDectog().setEnabled(true);
        await h.settle();
        expect(h.paths, contains('POST /api/v1/app-installs'));
        expect(h.paths, contains('POST /api/v1/clicks'));
        expect(h.paths, contains('POST /api/v1/app-opens'));
        final events = h.requests.where((r) => r.url.path == '/api/v1/events');
        expect(events, isNotEmpty);
        final names = [
          for (final r in events)
            for (final e in (jsonDecode(r.body)['events'] as List))
              (e as Map)['event_name'],
        ];
        expect(names, contains('opened_cart'));
        final click = h.requests.firstWhere(
          (r) => r.url.path == '/api/v1/clicks',
        );
        expect(jsonDecode(click.body)['slug'], 'spring');
      },
    );

    test(
      'a revoke drops the held link report; held events stay for the next consent',
      () async {
        h.initialLink = 'https://demo.dectog.com/spring';
        await FlutterDectog().initialize(waiting);
        await FlutterDectog().trackEvent('before_revoke');
        await FlutterDectog().setEnabled(false);
        await FlutterDectog().setEnabled(true);
        await h.settle();
        expect(h.paths, isNot(contains('POST /api/v1/clicks')));
        expect(h.paths, isNot(contains('POST /api/v1/app-opens')));
        expect(h.paths, contains('POST /api/v1/events'));
      },
    );

    test('the stored choice wins over the config on later launches', () async {
      await SdkStateStore().setEnabled(true);
      await FlutterDectog().initialize(waiting);
      await h.settle();
      expect(await FlutterDectog().isEnabled(), isTrue);
      expect(h.paths, contains('POST /api/v1/app-installs'));
    });
  });

  test(
    'a refund rides as a conversion with its transaction, top level',
    () async {
      await FlutterDectog().initialize(config);
      await FlutterDectog().trackConversion(
        revenue: 4.99,
        currency: 'EUR',
        productId: 'pro_monthly',
        transactionId: '2000000123',
        originalTransactionId: '2000000100',
        store: DectogStore.appStore,
        purchaseType: DectogPurchaseType.subscription,
        transactionType: DectogTransactionType.refund,
      );
      await FlutterDectog().flush();
      await h.settle();
      final batch = h.requests.lastWhere((r) => r.url.path == '/api/v1/events');
      final event =
          ((jsonDecode(batch.body) as Map)['events'] as List).single as Map;
      expect(event, {
        'type': 'conversion',
        'event_name': 'refund',
        'revenue': 4.99,
        'currency': 'EUR',
        'product_id': 'pro_monthly',
        'transaction_id': '2000000123',
        'original_transaction_id': '2000000100',
        'store': 'app_store',
        'purchase_type': 'subscription',
        'transaction_type': 'refund',
        'client_timestamp': isA<String>(),
        'client_event_id': isA<String>(),
        'session_id': isA<String>(),
      });
    },
  );

  test('screen views ride the event queue with the previous screen', () async {
    await FlutterDectog().initialize(config);
    await FlutterDectog().trackScreenView('home');
    await FlutterDectog().trackScreenView('  ');
    await FlutterDectog().trackScreenView(
      'product',
      params: {
        'id': 42,
        'promo': true,
        'label': 'x' * 300,
        'nested': {'a': 1},
        'missing': null,
        'ratio': double.nan,
      },
    );
    await FlutterDectog().flush();
    await h.settle();
    final events = [
      for (final r in h.requests.where((r) => r.url.path == '/api/v1/events'))
        ...((jsonDecode(r.body) as Map)['events'] as List).cast<Map>(),
    ];
    expect(events, hasLength(2));
    expect(events[0]['type'], 'screen_view');
    expect(events[0]['event_name'], 'home');
    expect(events[0].containsKey('metadata'), isFalse);
    expect(events[1]['event_name'], 'product');
    expect(events[1]['metadata'], {
      'previous_screen': 'home',
      'params': {'id': 42, 'promo': true, 'label': 'x' * 256},
    });
  });

  test('a StoreKit 2 transaction rides as app_store_jws', () async {
    await FlutterDectog().initialize(config);
    await FlutterDectog().trackConversion(
      revenue: 9.99,
      store: DectogStore.appStore,
      appStoreJws: 'header.payload.signature',
    );
    await FlutterDectog().flush();
    await h.settle();
    final batch = h.requests.lastWhere((r) => r.url.path == '/api/v1/events');
    final event =
        ((jsonDecode(batch.body) as Map)['events'] as List).single as Map;
    expect(event['app_store_jws'], 'header.payload.signature');
    expect(event['store'], 'app_store');
  });

  test(
    'an install the server lost is registered again with recovered_from',
    () async {
      await FlutterDectog().initialize(config);
      await h.settle();
      final first = h.requests.firstWhere(
        (r) => r.url.path == '/api/v1/app-installs',
      );
      final lostId = FlutterDectog().currentAppInstall!.installId;

      h.responses['/api/v1/events'] = jsonEncode({
        'accepted': 1,
        'duplicates': 0,
        'rejected': [],
        'code': 'install_not_found',
        'action': 'reregister',
      });
      await FlutterDectog().trackEvent('after_restore');
      await FlutterDectog().flush();
      await h.settle();

      final installs =
          h.requests
              .where((r) => r.url.path == '/api/v1/app-installs')
              .toList();
      expect(installs, hasLength(2));
      final again = jsonDecode(installs.last.body) as Map;
      expect(again['recovered_from'], lostId);
      expect(again['install_state'], 'reinstall');
      expect(
        again['install_attempt_id'],
        isNot((jsonDecode(first.body) as Map)['install_attempt_id']),
      );
    },
  );

  test(
    'a recovery registration never reads the pasteboard; the first launch does',
    () async {
      FlutterDectogImpl.debugIsIOS = true;
      addTearDown(() => FlutterDectogImpl.debugIsIOS = null);
      h.pasteboardUrl = 'https://demo.dectog.com/spring?dtg_click=abcdefgh1234';
      await FlutterDectog().initialize(config);
      await h.settle();
      expect(h.pasteboardReads, 1);
      final first = h.requests.firstWhere(
        (r) => r.url.path == '/api/v1/app-installs',
      );
      expect((jsonDecode(first.body) as Map)['clipboard_url'], h.pasteboardUrl);

      h.responses['/api/v1/events'] = jsonEncode({
        'accepted': 1,
        'duplicates': 0,
        'rejected': [],
        'code': 'install_not_found',
        'action': 'reregister',
      });
      await FlutterDectog().trackEvent('after_restore');
      await FlutterDectog().flush();
      await h.settle();
      final installs =
          h.requests
              .where((r) => r.url.path == '/api/v1/app-installs')
              .toList();
      expect(installs, hasLength(2));
      final again = jsonDecode(installs.last.body) as Map;
      expect(again['recovered_from'], isNotNull);
      expect(again.containsKey('clipboard_url'), isFalse);
      expect(h.pasteboardReads, 1);
    },
  );

  test(
    'events after a link opened the app name that link and the session',
    () async {
      h.initialLink = 'https://demo.dectog.com/spring';
      await FlutterDectog().initialize(config);
      await h.settle();
      await FlutterDectog().trackEvent('cart_viewed');
      await FlutterDectog().trackEvent('checkout');
      await FlutterDectog().flush();
      await h.settle();
      final events =
          (jsonDecode(
                    h.requests
                        .lastWhere((r) => r.url.path == '/api/v1/events')
                        .body,
                  )
                  as Map)['events']
              as List;
      expect(events, hasLength(2));
      for (final e in events.cast<Map>()) {
        expect(e['open_slug'], 'spring');
        expect(DateTime.parse(e['open_at'] as String).isUtc, isTrue);
      }
      expect(events[0]['session_id'], events[1]['session_id']);
      expect(await SdkStateStore().lastOpen?.slug, 'spring');
    },
  );

  test(
    'a link with a malformed dtg_click opens the app without it, and later events still go',
    () async {
      h.initialLink = 'https://demo.dectog.com/spring?dtg_click=bad';
      await FlutterDectog().initialize(config);
      await h.settle();
      await FlutterDectog().trackEvent('checkout');
      await FlutterDectog().flush();
      await h.settle();
      final open = h.requests.lastWhere(
        (r) => r.url.path == '/api/v1/app-opens',
      );
      expect((jsonDecode(open.body) as Map).containsKey('click_id'), isFalse);
      final events =
          (jsonDecode(
                    h.requests
                        .lastWhere((r) => r.url.path == '/api/v1/events')
                        .body,
                  )
                  as Map)['events']
              as List;
      expect(events.single['open_slug'], 'spring');
      expect((events.single as Map).containsKey('open_click_id'), isFalse);
      expect(SdkStateStore().lastOpen?.clickId, isNull);
      // A state file written before this check drops the bad id when read.
      expect(
        LastOpen.fromJson({
          'slug': 'spring',
          'click_id': 'bad',
          'opened_at': '2026-10-16T10:00:00.000Z',
        })?.clickId,
        isNull,
      );
    },
  );

  test(
    'an open the server refused leaves the earlier open on later events',
    () async {
      h.initialLink = 'https://demo.dectog.com/spring';
      h.answer = (r) async {
        if (r.url.path != '/api/v1/app-opens') return null;
        if ((jsonDecode(r.body) as Map)['slug'] != 'paused') return null;
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'link_paused',
              'message': 'This link is paused',
              'request_id': 'req-f2',
            },
          }),
          410,
          headers: {'content-type': 'application/json'},
        );
      };
      await FlutterDectog().initialize(config);
      await h.settle();
      await FlutterDectog().handleUrl('https://demo.dectog.com/paused');
      await h.settle();
      expect(SdkStateStore().lastOpen?.slug, 'spring');
      await FlutterDectog().trackEvent('checkout');
      await FlutterDectog().flush();
      await h.settle();
      final events =
          (jsonDecode(
                    h.requests
                        .lastWhere((r) => r.url.path == '/api/v1/events')
                        .body,
                  )
                  as Map)['events']
              as List;
      expect(events.single['open_slug'], 'spring');
    },
  );

  test('createReferralLink accepts the existing link (200)', () async {
    h.responses['/api/v1/referral-links'] =
        File('test/fixtures/wire/link.json').readAsStringSync();
    await FlutterDectog().initialize(config);
    final link = await FlutterDectog().createReferralLink(customerId: 'alice');
    final sent = h.requests.lastWhere(
      (r) => r.url.path == '/api/v1/referral-links',
    );
    expect(jsonDecode(sent.body), {'customer_id': 'alice'});
    expect(link.slug, isNotEmpty);
  });

  test(
    'the first launch reads the app settings before registering; later launches use the cache',
    () async {
      h.responses['/api/v1/sdk-config'] =
          File('test/fixtures/wire/sdk-config.json').readAsStringSync();
      await FlutterDectog().initialize(config);
      await h.settle();
      final paths = h.paths.toList();
      final cfg = paths.indexOf('GET /api/v1/sdk-config');
      expect(cfg, greaterThanOrEqualTo(0));
      expect(cfg, lessThan(paths.indexOf('POST /api/v1/app-installs')));
      expect(
        h.requests[cfg].url.queryParameters['package'],
        'app.dectog.harness',
      );
      expect(SdkConfigStore().config?.fbAppId, '1234567890');

      final report = await FlutterDectog().diagnostics();
      expect(report.serverConfig?.linkHosts, [
        'go.acme.app',
        'acme.dectog.com',
      ]);
      expect(report.serverConfig?.username, 'acme');
      expect(
        report.ok,
        isTrue,
        reason: 'the test host is neither iOS nor Android',
      );
    },
  );

  test(
    'a slow first-launch settings read does not hold start-up; its answer is still cached',
    () async {
      final gate = Completer<void>();
      final fixture =
          File('test/fixtures/wire/sdk-config.json').readAsStringSync();
      h.answer = (r) async {
        if (r.url.path != '/api/v1/sdk-config') return null;
        await gate.future;
        return http.Response(
          fixture,
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      final started = DateTime.now();
      await FlutterDectog().initialize(config);
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 5)),
      );
      expect(SdkConfigStore().config, isNull);

      gate.complete();
      await h.settle();
      expect(SdkConfigStore().config?.fbAppId, '1234567890');
      expect(
        h.paths.where((p) => p == 'GET /api/v1/sdk-config').length,
        1,
        reason: 'one request: the late answer is kept, not fetched again',
      );
    },
  );

  test(
    'the first launch waits for a settings answer as slow as a cold connection',
    () async {
      final fixture =
          File('test/fixtures/wire/sdk-config.json').readAsStringSync();
      h.answer = (r) async {
        if (r.url.path != '/api/v1/sdk-config') return null;
        // One request on a cold connection measured about 2 s.
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response(
          fixture,
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      await FlutterDectog().initialize(config);
      expect(
        SdkConfigStore().config?.fbAppId,
        '1234567890',
        reason: 'the install registration ran with the settings',
      );
    },
  );

  test(
    'diagnostics warns when the key belongs to the other environment',
    () async {
      h.responses['/api/v1/sdk-config'] =
          File('test/fixtures/wire/sdk-config.json').readAsStringSync();
      await FlutterDectog().initialize(
        const DectogConfig(
          apiKey: 'dtg_0123456789abcdef0123456789abcdef',
          baseUrl: 'https://app.dectog.com',
          linkRootDomain: 'dectog.com',
          environment: DectogEnvironment.test,
        ),
      );
      final report = await FlutterDectog().diagnostics();
      expect(report.serverConfig?.environment, DectogEnvironment.live);
      expect(
        report.warnings,
        contains(
          'This build expects a test key, but its key belongs to the live environment (acme).',
        ),
      );
    },
  );

  Map<String, dynamic> installBody() =>
      jsonDecode(
            h.requests
                .singleWhere((r) => r.url.path == '/api/v1/app-installs')
                .body,
          )
          as Map<String, dynamic>;

  test('the advertising id from the provider goes on the install', () async {
    await FlutterDectog().initialize(
      DectogConfig(
        apiKey: config.apiKey,
        baseUrl: config.baseUrl,
        linkRootDomain: config.linkRootDomain,
        advertisingIdProvider:
            () async => const DectogAdvertisingId(id: 'IDFA-1'),
      ),
    );
    await h.settle();
    final body = installBody();
    expect(body['ad_id'], 'IDFA-1');
    expect(body['ad_tracking_limited'], isFalse);
  });

  test('a limited id sends the flag and no id', () async {
    await FlutterDectog().initialize(
      DectogConfig(
        apiKey: config.apiKey,
        baseUrl: config.baseUrl,
        linkRootDomain: config.linkRootDomain,
        advertisingIdProvider:
            () async => const DectogAdvertisingId(id: 'IDFA-1', limited: true),
      ),
    );
    await h.settle();
    final body = installBody();
    expect(body.containsKey('ad_id'), isFalse);
    expect(body['ad_tracking_limited'], isTrue);
  });

  test(
    'an empty collect set reads no ad id and sends no device ping',
    () async {
      h.deviceId = 'device-1';
      var asked = 0;
      await FlutterDectog().initialize(
        DectogConfig(
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
          linkRootDomain: config.linkRootDomain,
          collect: const {},
          advertisingIdProvider: () async {
            asked++;
            return const DectogAdvertisingId(id: 'IDFA-1');
          },
        ),
      );
      await h.settle();
      expect(asked, 0);
      final body = installBody();
      expect(body.containsKey('ad_id'), isFalse);
      expect(body.containsKey('device_id'), isFalse);
      expect(h.paths, isNot(contains('POST /api/v1/device-ping')));
    },
  );

  test('the defaults send the device tier and ping', () async {
    h.deviceId = 'device-1';
    await FlutterDectog().initialize(config);
    await h.settle();
    expect(installBody()['device_id'], 'device-1');
    expect(h.paths, contains('POST /api/v1/device-ping'));
    expect(SdkStateStore().pingDay, utcDay(DateTime.now()));
  });

  test('a device already pinged today is not pinged again', () async {
    h.deviceId = 'device-1';
    await SdkStateStore().setPingDay(utcDay(DateTime.now()));
    await FlutterDectog().initialize(config);
    await h.settle();
    expect(h.paths, isNot(contains('POST /api/v1/device-ping')));
  });

  test('a new day pings again', () async {
    h.deviceId = 'device-1';
    await SdkStateStore().setPingDay(
      utcDay(DateTime.now().subtract(const Duration(days: 1))),
    );
    await FlutterDectog().initialize(config);
    await h.settle();
    expect(h.paths, contains('POST /api/v1/device-ping'));
    expect(SdkStateStore().pingDay, utcDay(DateTime.now()));
  });

  group('display and accessibility settings', () {
    setUp(() {
      h.platformDispatcher
        ..textScaleFactorTestValue = 19 / 17
        ..platformBrightnessTestValue = Brightness.dark
        ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
          highContrast: true,
          disableAnimations: true,
        );
    });

    test('the device tier sends them with the UTC offset', () async {
      FlutterDectogImpl.debugIsIOS = true;
      addTearDown(() => FlutterDectogImpl.debugIsIOS = null);
      await FlutterDectog().initialize(config);
      await h.settle();
      final body = installBody();
      expect(body['text_size'], 19);
      expect(body['dark_mode'], isTrue);
      expect(body['high_contrast'], isTrue);
      expect(body['reduce_motion'], isTrue);
      expect(body['utc_offset_min'], DateTime.now().timeZoneOffset.inMinutes);
    });

    test(
      'without the device tier none are sent, but the UTC offset is',
      () async {
        FlutterDectogImpl.debugIsIOS = true;
        addTearDown(() => FlutterDectogImpl.debugIsIOS = null);
        await FlutterDectog().initialize(
          DectogConfig(
            apiKey: config.apiKey,
            baseUrl: config.baseUrl,
            linkRootDomain: config.linkRootDomain,
            collect: const {},
          ),
        );
        await h.settle();
        final body = installBody();
        for (final key in [
          'text_size',
          'dark_mode',
          'high_contrast',
          'reduce_motion',
        ]) {
          expect(body.containsKey(key), isFalse, reason: key);
        }
        expect(body['utc_offset_min'], isA<int>());
        expect(body['timezone'], isNotNull);
      },
    );

    test('the text size and high contrast are sent on iOS only', () async {
      FlutterDectogImpl.debugIsIOS = false;
      addTearDown(() => FlutterDectogImpl.debugIsIOS = null);
      await FlutterDectog().initialize(config);
      await h.settle();
      final body = installBody();
      expect(body.containsKey('text_size'), isFalse);
      expect(body.containsKey('high_contrast'), isFalse);
      expect(body['dark_mode'], isTrue);
      expect(body['reduce_motion'], isTrue);
    });
  });

  group('each pasteboard read keeps its own mark', () {
    const link = 'https://demo.dectog.com/invite?dtg_click=c1';
    final matched =
        jsonDecode(
              File(
                'test/fixtures/wire/install-verdict-matched.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    http.Response verdict(String claim) => http.Response(
      jsonEncode({...matched, 'claim': claim}),
      200,
      headers: {'content-type': 'application/json'},
    );
    Future<void> wait(int ms) =>
        Future<void>.delayed(Duration(milliseconds: ms));

    setUp(() => h.pasteboardChangeCount = 7);
    tearDown(() => FlutterDectog().dispose());

    test('a credited paste-control link is cleared', () async {
      h.answer =
          (r) async =>
              r.url.path.endsWith('/claim') ? verdict('upgraded') : null;
      await FlutterDectog().initialize(config);
      await h.settle();
      await h.paste(link);
      await h.settle();
      expect(h.pasteboardClears, 1);
    });

    test(
      'a second read answered first, not credited, leaves the first its clear',
      () async {
        var claims = 0;
        h.answer = (r) async {
          if (!r.url.path.endsWith('/claim')) return null;
          if (++claims == 1) {
            await wait(200);
            return verdict('upgraded');
          }
          return verdict('unchanged');
        };
        await FlutterDectog().initialize(config);
        await h.settle();
        await h.paste(link);
        await wait(20);
        await h.paste(link); // a second tap on the same link
        await wait(600);
        expect(claims, 2);
        expect(h.pasteboardClears, 1);
      },
    );

    test(
      'a link copied after a read is not cleared by that read\'s credit',
      () async {
        h.answer = (r) async {
          if (!r.url.path.endsWith('/claim')) return null;
          final first = (jsonDecode(r.body) as Map)['clipboard_url'] == link;
          await wait(first ? 100 : 300);
          return verdict(first ? 'upgraded' : 'rejected');
        };
        await FlutterDectog().initialize(config);
        await h.settle();
        await h.paste(link); // read at 7
        await wait(20);
        h.pasteboardChangeCount = 8; // the user copies another link
        await h.paste('https://demo.dectog.com/other?dtg_click=c2');
        await wait(600);
        expect(h.pasteboardClears, 0);
      },
    );
  });
}
