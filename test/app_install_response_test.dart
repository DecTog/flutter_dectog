import 'package:flutter_dectog/flutter_dectog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'parses the verdict fields (referrer_source, fraud_flags, last_open)',
    () {
      final response = DectogAppInstallResponse.fromJson({
        'matched': true,
        'type': 'non-organic',
        'match_source': 'referrer',
        'referrer_source': 'google_play',
        'fraud_flags': ['emulator'],
        'username': 'demo',
        'slug': 'welcome',
        'install_id': 'inst-1',
        'clicked_at': '2026-10-11T10:00:00Z',
        'last_open': {
          'username': 'demo',
          'slug': 'welcome',
          'click_id': 'abc123',
          'opened_at': '2026-10-11T12:30:00Z',
        },
      });
      expect(response.matchSource, 'referrer');
      expect(response.referrerSource, 'google_play');
      expect(response.fraudFlags, ['emulator']);
      expect(response.lastOpen?.slug, 'welcome');
      expect(response.lastOpen?.clickId, 'abc123');
      expect(
        response.lastOpen?.openedAt,
        DateTime.parse('2026-10-11T12:30:00Z'),
      );
      expect(response.installId, 'inst-1');
    },
  );

  test('older payloads parse with empty fraud flags and no last_open', () {
    final response = DectogAppInstallResponse.fromJson({
      'matched': false,
      'type': 'organic',
      'fraud_flags': [],
      'install_id': 'inst-2',
    });
    expect(response.fraudFlags, isEmpty);
    expect(response.lastOpen, isNull);
    expect(response.referrerSource, isNull);
    expect(response.matchConfidence, isNull);
    expect(response.routing, isNull);
    expect(response.replayed, isFalse);
    expect(response.isReinstall, isFalse);
  });

  test('clipboard match verdicts carry match_source clipboard', () {
    final response = DectogAppInstallResponse.fromJson({
      'matched': true,
      'type': 'non-organic',
      'match_source': 'clipboard',
      'fraud_flags': [],
    });
    expect(response.matchSource, 'clipboard');
    expect(response.fraudFlags, isEmpty);
  });

  test(
    'confidence, routing-only candidate, replay and install state round-trip',
    () {
      final json = {
        'matched': false,
        'type': 'organic',
        'match_confidence': 'medium',
        'routing': {
          'username': 'demo',
          'slug': 'promo',
          'deep_link': 'voucher?code=X',
          'click_params': {
            'deep_link': 'voucher?code=X',
            'label': 'l1',
            'campaign': null,
            'adgroup': null,
            'creative': null,
            'tracker': null,
          },
          'confidence': 'medium',
          'clicked_at': '2026-10-12T09:00:00Z',
        },
        'replayed': true,
        'is_reinstall': true,
        'install_state': 'reinstall',
        'install_id': 'inst-3',
      };
      final r = DectogAppInstallResponse.fromJson(json);
      expect(
        r.matched,
        isFalse,
        reason: 'medium confidence routes but never credits',
      );
      expect(r.matchConfidence, 'medium');
      expect(r.routing?.slug, 'promo');
      expect(r.routing?.deepLink, 'voucher?code=X');
      expect(r.routing?.clickParams?.label, 'l1');
      expect(r.routing?.confidence, 'medium');
      expect(r.routing?.clickedAt, DateTime.parse('2026-10-12T09:00:00Z'));
      expect(r.replayed, isTrue);
      expect(r.isReinstall, isTrue);
      expect(r.installState, 'reinstall');

      final again = DectogAppInstallResponse.fromJson(r.toJson());
      expect(again.routing?.deepLink, 'voucher?code=X');
      expect(again.routing?.clickParams?.label, 'l1');
      expect(again.matchConfidence, 'medium');
      expect(again.replayed, isTrue);
      expect(again.installState, 'reinstall');
      expect(r.toString(), contains('routing'));
    },
  );

  test('claim responses carry claim / claim_reason', () {
    final r = DectogAppInstallResponse.fromJson({
      'matched': true,
      'type': 'non-organic',
      'match_confidence': 'guaranteed',
      'claim': 'upgraded',
      'install_id': 'i',
    });
    expect(r.claim, 'upgraded');
    expect(r.claimReason, isNull);
    final rejected = DectogAppInstallResponse.fromJson({
      'matched': false,
      'type': 'organic',
      'claim': 'rejected',
      'claim_reason': 'click_reuse',
    });
    expect(rejected.claimReason, 'click_reuse');
    expect(rejected.toJson()['claim_reason'], 'click_reuse');
  });

  test('a verdict without type derives it from matched', () {
    expect(
      DectogAppInstallResponse.fromJson({'matched': true}).type,
      'non-organic',
    );
    expect(
      DectogAppInstallResponse.fromJson({'matched': false}).type,
      'organic',
    );
  });
}
