import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('links without a target parse, with the full field set', () {
    final link = AdtoLink.fromJson({
      'id': 'l1',
      'slug': 'spring',
      'target': null,
      'url': 'https://acme.adto.app/spring',
      'click_count': 3,
      'created_at': '2026-10-12T10:00:00Z',
      'updated_at': null,
      'ios_deep_link_path': 'feed',
      'campaign': 'spring_sale',
      'og_title': 'Spring',
    });
    expect(link.target, isNull);
    expect(link.id, 'l1');
    expect(link.iosDeepLinkPath, 'feed');
    expect(link.campaign, 'spring_sale');
    expect(link.ogTitle, 'Spring');

    final temp = AdtoTempLink.fromJson({
      'id': 't1',
      'slug': 't_abc',
      'target': null,
      'url': 'https://acme.adto.app/t_abc',
      'expires_at': '2026-10-12T11:00:00Z',
      'created_at': '2026-10-12T10:00:00Z',
      'ttl_seconds': 3600,
    });
    expect(temp.target, isNull);
    expect(temp.ttlSeconds, 3600);
  });

  test('a paused, expiring, archived link parses its lifecycle', () {
    final link = AdtoLink.fromJson({
      'id': 'l2',
      'slug': 'sale',
      'target': null,
      'url': 'https://acme.adto.app/sale',
      'click_count': 0,
      'created_at': '2026-10-12T10:00:00Z',
      'expires_at': '2026-12-31T23:59:00.000Z',
      'expired_url': 'https://example.com/over',
      'disabled_at': '2026-10-13T10:00:00.000Z',
      'disabled_reason': 'sale over',
      'archived_at': '2026-10-13T11:00:00.000Z',
      'deleted_at': null,
    });
    expect(link.expiresAt, DateTime.utc(2026, 12, 31, 23, 59));
    expect(link.expiredUrl, 'https://example.com/over');
    expect(link.disabledAt, isNotNull);
    expect(link.disabledReason, 'sale over');
    expect(link.archivedAt, isNotNull);
    expect(link.deletedAt, isNull);
  });

  test('a link parses its routing rules', () {
    final link = AdtoLink.fromJson({
      'id': 'l3',
      'slug': 'sale',
      'target': null,
      'url': 'https://acme.adto.app/sale',
      'click_count': 0,
      'created_at': '2026-10-12T10:00:00Z',
      'routing_rules': [
        {
          'countries': ['DE', 'AT'],
          'fallback_url': 'https://example.de/sale',
          'android_deep_link_path': 'de/sale',
        },
        {
          'languages': ['fr'],
          'redirect_url': 'https://example.fr/m',
        },
      ],
    });
    expect(link.routingRules, hasLength(2));
    expect(link.routingRules![0].countries, ['DE', 'AT']);
    expect(link.routingRules![0].androidDeepLinkPath, 'de/sale');
    expect(link.routingRules![1].languages, ['fr']);
    expect(link.routingRules![1].redirectUrl, 'https://example.fr/m');
  });

  test('resolution parses a null target and exposes the deep-link paths', () {
    final r = AdtoLinkResolution.fromJson({
      'id': 'l1',
      'slug': 'open',
      'target': null,
      'url': 'https://acme.adto.app/open',
      'type': 'permanent',
      'created_at': '2026-10-12T10:00:00Z',
      'click_count': 1,
      'ios_deep_link_path': 'feed',
      'android_deep_link_path': 'products/1',
    });
    expect(r.target, isNull);
    expect(r.iosDeepLinkPath, 'feed');
    // Tests run on the host, which takes the Android path.
    expect(r.deepLinkPath, 'products/1');
    expect(r.toAdtoLink()?.androidDeepLinkPath, 'products/1');
  });

  test('deepLinkPath falls back to the iOS path off iOS', () {
    final r = AdtoLinkResolution.fromJson({
      'id': 'l1',
      'slug': 'open',
      'target': null,
      'url': 'https://acme.adto.app/open',
      'type': 'permanent',
      'created_at': '2026-10-12T10:00:00Z',
      'ios_deep_link_path': 'feed',
    });
    expect(r.deepLinkPath, 'feed');
  });

  test('config defaults to hosted AdTo', () {
    const hosted = AdtoConfig(apiKey: 'adto_test');
    expect(hosted.effectiveBaseUrl, 'https://api.adto.app');
    expect(hosted.effectiveLinkRootDomain, 'adto.app');

    const selfHosted = AdtoConfig(
      apiKey: 'adto_test',
      baseUrl: 'https://links.example.com/',
    );
    expect(selfHosted.effectiveBaseUrl, 'https://links.example.com');
    expect(
      selfHosted.effectiveLinkRootDomain,
      isNull,
    ); // falls back to the API host

    const split = AdtoConfig(
      apiKey: 'adto_test',
      baseUrl: 'https://app.example.com',
      linkRootDomain: 'example.com.',
    );
    expect(split.effectiveLinkRootDomain, 'example.com');
  });
}
