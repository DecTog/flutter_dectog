import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('apple_search_ads parses the resolved record and round-trips', () {
    final r = AdtoAppInstallResponse.fromJson({
      'matched': false,
      'type': 'organic',
      'install_id': 'i1',
      'apple_search_ads': {
        'status': 'resolved',
        'attribution': true,
        'resolved_at': '2026-10-12T10:00:00.000Z',
        'org_id': 40669820,
        'campaign_id': 542370539,
        'ad_group_id': 542317095,
        'keyword_id': 87675432,
        'ad_id': 542317136,
        'conversion_type': 'Download',
        'claim_type': 'Click',
        'click_date': '2026-10-08T17:17Z',
        'impression_date': null,
        'country_or_region': 'US',
        'supply_placement': 'APPSTORE_SEARCH_RESULTS',
      },
    });
    final asa = r.appleSearchAds!;
    expect(asa.status, 'resolved');
    expect(asa.isAttributed, isTrue);
    expect(asa.isPending, isFalse);
    expect(asa.campaignId, 542370539);
    expect(asa.keywordId, 87675432);
    expect(asa.claimType, 'Click');
    expect(asa.clickDate, '2026-10-08T17:17Z');
    expect(asa.impressionDate, isNull);
    expect(asa.resolvedAt, DateTime.parse('2026-10-12T10:00:00.000Z'));

    final again = AdtoAppInstallResponse.fromJson(r.toJson());
    expect(again.appleSearchAds?.campaignId, 542370539);
    expect(again.appleSearchAds?.supplyPlacement, 'APPSTORE_SEARCH_RESULTS');
    expect(
      r.matched,
      isFalse,
      reason: 'Apple Search Ads never changes AdTo link attribution',
    );
  });

  test('a pending exchange and a missing token both parse', () {
    final pending = AdtoAppInstallResponse.fromJson({
      'matched': false,
      'type': 'organic',
      'install_id': 'i2',
      'apple_search_ads': {
        'status': 'pending',
        'attribution': null,
        'resolved_at': null,
      },
    });
    expect(pending.appleSearchAds?.isPending, isTrue);
    expect(pending.appleSearchAds?.isAttributed, isFalse);
    expect(pending.appleSearchAds?.campaignId, isNull);

    final none = AdtoAppInstallResponse.fromJson({
      'matched': false,
      'type': 'organic',
      'install_id': 'i3',
      'apple_search_ads': null,
    });
    expect(none.appleSearchAds, isNull);
    expect(none.toJson().containsKey('apple_search_ads'), isFalse);
  });
}
