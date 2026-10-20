import 'dart:convert';
import 'dart:io';

import 'package:flutter_dectog/flutter_dectog.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server's golden wire fixtures (copied by tool/sync_wire_fixtures.sh
/// from DecTog/dectog apps/worker/test/fixtures/wire, where every live v1
/// response is held to their shape). Each must parse into the model the SDK
/// uses for it, with no field lost.
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/wire/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  const parsed = {
    'install-verdict-matched',
    'install-verdict-organic',
    'attribution',
    'link',
    'link-page',
    'temp-link',
    'resolution',
    'error',
    'sdk-config',
  };

  test('every server fixture is parsed by a test below', () {
    final files =
        Directory('test/fixtures/wire')
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
            .toSet();
    expect(files, parsed, reason: 'a new fixture needs a parse test here');
  });

  test('a matched install verdict', () {
    final r = DectogAppInstallResponse.fromJson(
      fixture('install-verdict-matched'),
    );
    expect(r.matched, isTrue);
    expect(r.type, 'non-organic');
    expect(r.matchSource, 'referrer');
    expect(r.referrerSource, 'google_play');
    expect(r.matchConfidence, 'guaranteed');
    expect(r.username, 'acme');
    expect(r.slug, 'promo');
    expect(r.installId, isNotEmpty);
    expect(r.clickedAt, isNotNull);
    expect(r.link?.slug, 'promo');
    expect(r.routing?.slug, 'promo');
    expect(r.routing?.confidence, 'guaranteed');
    expect(r.isReinstall, isFalse);
  });

  test('an organic install verdict', () {
    final r = DectogAppInstallResponse.fromJson(
      fixture('install-verdict-organic'),
    );
    expect(r.matched, isFalse);
    expect(r.type, 'organic');
    expect(r.matchSource, isNull);
    expect(r.routing, isNull);
    expect(r.slug, isNull);
    expect(r.installId, isNotEmpty);
  });

  test('the attribution pull carries last_open', () {
    final json = fixture('attribution');
    expect(json.containsKey('last_open'), isTrue);
    final r = DectogAppInstallResponse.fromJson(json);
    expect(r.matched, isTrue);
    expect(r.lastOpen, isNull);
  });

  test('a permanent link', () {
    final l = DectogLink.fromJson(fixture('link'));
    expect(l.slug, 'spring');
    expect(l.target, 'https://example.com/s');
    expect(l.campaign, 'c1');
    expect(l.metadata?['screen'], 'sale');
    expect(l.url, startsWith('https://acme.'));
    // A live link; following the app's pages.
    expect(l.iosTapToStore, isNull);
    expect(l.mobileInterstitial, isNull);
    expect(l.appendClickId, isNull);
    expect(l.routingRules, isNull);
    expect(l.templateId, isNull);
    expect(l.utmSource, isNull);
    expect(l.externalId, isNull);
    expect(l.expiresAt, isNull);
    expect(l.disabledAt, isNull);
    expect(l.deletedAt, isNull);
  });

  test('a page of links', () {
    final p = DectogLinkPage.fromJson(fixture('link-page'));
    expect(p.links.single.slug, 'spring');
    expect(p.nextCursor, isNotEmpty);
    expect(p.hasMore, isTrue);
  });

  test('a temporary link', () {
    final t = DectogTempLink.fromJson(fixture('temp-link'));
    expect(t.slug, startsWith('t_'));
    expect(t.ttlSeconds, 600);
    expect(t.expiredUrl, isNull);
    expect(t.deletedAt, isNull);
  });

  test('a public resolution', () {
    final r = DectogLinkResolution.fromJson(fixture('resolution'));
    expect(r.slug, 'spring');
    expect(r.type, 'permanent');
    expect(r.expiresAt, isNull);
  });

  test('the error envelope', () {
    final e = DectogError.fromResponse(
      statusCode: 404,
      body: jsonEncode(fixture('error')),
      fallbackMessage: 'Request failed (HTTP 404)',
    );
    expect(e.code, 'not_found');
    expect(e.message, 'Link not found');
    expect(e.requestId, isNotEmpty);
  });

  test('the app settings', () {
    final c = DectogSdkConfig.fromJson(fixture('sdk-config'));
    final json = fixture('sdk-config')..remove(r'$source');
    expect(c.toJson(), json, reason: 'no field lost');
  });
}
