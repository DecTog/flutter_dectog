import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'install response parses click_params and deep_link, and round-trips',
    () {
      final response = AdtoAppInstallResponse.fromJson({
        'matched': true,
        'type': 'non-organic',
        'slug': 'promo',
        'deep_link': 'voucher?code=ABC',
        'click_params': {
          'deep_link': 'voucher?code=ABC',
          'label': '2323',
          'campaign': 'refer_a_friend',
          'adgroup': null,
          'creative': null,
          'tracker': null,
        },
      });
      expect(response.deepLink, 'voucher?code=ABC');
      expect(response.clickParams?.label, '2323');
      expect(response.clickParams?.campaign, 'refer_a_friend');
      expect(response.clickParams?.adgroup, isNull);

      final again = AdtoAppInstallResponse.fromJson(response.toJson());
      expect(again.deepLink, 'voucher?code=ABC');
      expect(again.clickParams?.label, '2323');
    },
  );

  test('older payloads have no click params', () {
    final response = AdtoAppInstallResponse.fromJson({
      'matched': false,
      'type': 'organic',
    });
    expect(response.clickParams, isNull);
    expect(response.deepLink, isNull);
  });

  test('fromUri reads only dec_* keys; none means null', () {
    final params = AdtoClickParams.fromUri(
      Uri.parse(
        'https://demo.adto.app/promo?dec_label=2323&dec_deeplink=myapp%3A%2F%2Fvoucher&label=x&adj_campaign=y&dec_tracker=t1',
      ),
    );
    expect(params?.label, '2323');
    expect(params?.deepLink, 'myapp://voucher');
    expect(params?.tracker, 't1');
    expect(params?.campaign, isNull);
    expect(
      AdtoClickParams.fromUri(
        Uri.parse('https://demo.adto.app/promo?utm_source=x'),
      ),
      isNull,
    );
  });

  test('AdtoLinkClick exposes the opened URL click params', () {
    final click = AdtoLinkClick(
      originalUrl: 'https://demo.adto.app/promo?dec_campaign=spring',
      slug: 'promo',
      username: 'demo',
      receivedAt: DateTime(2026, 10, 11),
    );
    expect(click.clickParams?.campaign, 'spring');
  });
}
