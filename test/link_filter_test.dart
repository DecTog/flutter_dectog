import 'package:flutter_dectog/src/services/link_deduper.dart';
import 'package:flutter_dectog/src/services/link_filter.dart';
import 'package:flutter_dectog/src/services/platform_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSensitiveUrl', () {
    test('social-login callback schemes are sensitive', () {
      for (final u in [
        'fb123456://authorize/?code=abc',
        'li12345://callback',
        'pdk99://pinterest',
        'twitterkit-abc://authorize',
        'com.googleusercontent.apps.123-xyz:/oauth2redirect?code=4/abc',
        'myoauthscheme://done',
        'custom://x?access_token=AAA',
        'https://demo.dectog.com/promo?id_token=eyJ',
        'https://demo.dectog.com/promo#access_token=AAA&state=1',
      ]) {
        expect(isSensitiveUrl(Uri.parse(u)), isTrue, reason: u);
      }
    });

    test('DecTog links and ordinary deep links are not', () {
      for (final u in [
        'https://demo.dectog.com/welcome?dtg_click=abc&dec_deeplink=voucher%3Fcode%3DX',
        'istoria://demo/welcome/products/42?color=black',
        'http://localhost:8787/r/demo/e2e',
        'https://demo.dectog.com/promo?token_hint=1', // not an exact token key
      ]) {
        expect(isSensitiveUrl(Uri.parse(u)), isFalse, reason: u);
      }
    });
  });

  group('LinkDeduper', () {
    test(
      'the cold-start URL is processed once per process, echoes inside the window fold',
      () {
        final d = LinkDeduper(window: const Duration(seconds: 10));
        final t0 = DateTime(2026, 10, 12, 12);
        const url = 'https://demo.dectog.com/welcome';
        expect(d.shouldProcess(url, initial: true, now: t0), isTrue);
        // uriLinkStream delivers the same link right after getInitialLink
        expect(
          d.shouldProcess(
            url,
            initial: false,
            now: t0.add(const Duration(seconds: 1)),
          ),
          isFalse,
        );
        // the host app calls getInitialLink() minutes later: still consumed
        expect(
          d.shouldProcess(
            url,
            initial: true,
            now: t0.add(const Duration(minutes: 30)),
          ),
          isFalse,
        );
        expect(d.wasConsumedInitial(url), isTrue);
        // a genuinely new tap on the same link an hour later is a new open
        expect(
          d.shouldProcess(
            url,
            initial: false,
            now: t0.add(const Duration(hours: 1)),
          ),
          isTrue,
        );
      },
    );

    test(
      'identical stream deliveries within the window are one open; after it, two',
      () {
        final d = LinkDeduper(window: const Duration(seconds: 10));
        final t0 = DateTime(2026, 10, 12, 12);
        const url = 'istoria://demo/promo?dtg_click=1';
        expect(d.shouldProcess(url, initial: false, now: t0), isTrue);
        expect(
          d.shouldProcess(
            url,
            initial: false,
            now: t0.add(const Duration(seconds: 2)),
          ),
          isFalse,
        );
        expect(
          d.shouldProcess(
            url,
            initial: false,
            now: t0.add(const Duration(seconds: 11)),
          ),
          isTrue,
        );
      },
    );

    test('different URLs never collide', () {
      final d = LinkDeduper();
      expect(d.shouldProcess('a://u/s', initial: true), isTrue);
      expect(d.shouldProcess('a://u/t', initial: true), isTrue);
    });
  });

  group('iosMajorVersion', () {
    test('parses Platform.operatingSystemVersion shapes', () {
      expect(iosMajorVersion('Version 17.5 (Build 21F79)'), 17);
      expect(iosMajorVersion('Version 16.0.3 (Build 20A392)'), 16);
      expect(iosMajorVersion('15.7'), 15);
      expect(iosMajorVersion(''), 0);
      expect(iosMajorVersion('unknown'), 0);
    });
  });
}
