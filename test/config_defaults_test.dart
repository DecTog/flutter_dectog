import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AdtoAdvertisingId?> _adId() async => const AdtoAdvertisingId(id: 'ad');

void main() {
  test('config defaults', () {
    const c = AdtoConfig(apiKey: 'dtg_test');
    expect(c.installReferrerTimeout, const Duration(seconds: 5));
    expect(c.collect, isNull);
    // null collects the device tier, no ASA token, no ad id, and
    // leaves the pasteboard and OEM referrers to the dashboard.
    expect(c.collectsDeviceTier, isTrue);
    expect(c.collectsAppleSearchAdsToken, isFalse);
    expect(c.collectsAdId, isFalse);
    expect(c.pasteboardSetting, isNull);
    expect(c.oemReferrersSetting, isNull);
    expect(c.persistDeviceId, isTrue);
  });

  test('a collect set is exact: what it leaves out is off', () {
    const none = AdtoConfig(apiKey: 'dtg_test', collect: {});
    expect(none.collectsDeviceTier, isFalse);
    expect(none.collectsAppleSearchAdsToken, isFalse);
    expect(none.pasteboardSetting, isFalse);
    expect(none.oemReferrersSetting, isFalse);
    expect(
      const AdtoConfig(
        apiKey: 'dtg_test',
        collect: {},
        advertisingIdProvider: _adId,
      ).collectsAdId,
      isFalse,
    );

    const all = AdtoConfig(
      apiKey: 'dtg_test',
      collect: {...AdtoCollection.values},
    );
    expect(all.collectsDeviceTier, isTrue);
    expect(all.collectsAppleSearchAdsToken, isTrue);
    expect(all.pasteboardSetting, isTrue);
    expect(all.oemReferrersSetting, isTrue);
    // The ad id also needs a provider.
    expect(all.collectsAdId, isFalse);
  });

  test('the ad id is on by default once a provider is given', () {
    const c = AdtoConfig(apiKey: 'dtg_test', advertisingIdProvider: _adId);
    expect(c.collectsAdId, isTrue);
  });

  test(
    'pasteboard read: platform default is iOS on / Android off, explicit values win',
    () {
      expect(AdtoConfig.resolveReadClipboard(null, isIOS: true), isTrue);
      expect(AdtoConfig.resolveReadClipboard(null, isIOS: false), isFalse);
      expect(AdtoConfig.resolveReadClipboard(false, isIOS: true), isFalse);
      expect(AdtoConfig.resolveReadClipboard(true, isIOS: false), isTrue);

      const optOut = AdtoConfig(
        apiKey: 'dtg_test',
        collect: {AdtoCollection.deviceTier},
      );
      expect(optOut.readClipboardFor(isIOS: true), isFalse);
      const forced = AdtoConfig(
        apiKey: 'dtg_test',
        collect: {AdtoCollection.pasteboard},
      );
      expect(forced.readClipboardFor(isIOS: false), isTrue);
    },
  );

  test('toString never leaks the key and names the collection', () {
    const c = AdtoConfig(
      apiKey: 'dtg_0123456789abcdef',
      collect: {AdtoCollection.deviceTier, AdtoCollection.appleSearchAdsToken},
    );
    final s = c.toString();
    expect(s, isNot(contains('0123456789abcdef')));
    expect(s, contains('referrerTimeout: 5000ms'));
    expect(s, contains('collect: deviceTier,appleSearchAdsToken'));
    expect(s, contains('adId: false'));
    expect(
      const AdtoConfig(apiKey: 'dtg_test').toString(),
      contains('collect: defaults'),
    );
    expect(const AdtoConfig(apiKey: 'short').toString(), contains('***'));
  });
}
