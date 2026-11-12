import 'package:flutter/services.dart';
import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_adto_adid/flutter_adto_adid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('adto_adid');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(MethodCall call) reply) {
    messenger.setMockMethodCallHandler(channel, (call) async => reply(call));
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('an allowed id is returned as is', () async {
    answer((_) => {'id': 'ABCD-1234', 'limited': false});
    final id = await AdtoAdId.provider();
    expect(id?.id, 'ABCD-1234');
    expect(id?.limited, isFalse);
  });

  test('a limited, empty or all-zero id carries no id', () async {
    for (final raw in [
      {'id': 'ABCD-1234', 'limited': true},
      {'id': '00000000-0000-0000-0000-000000000000', 'limited': false},
      {'id': '', 'limited': false},
      {'limited': true},
    ]) {
      answer((_) => raw);
      final id = await AdtoAdId.provider();
      expect(id?.limited, isTrue, reason: '$raw');
      expect(id?.id, isNull, reason: '$raw');
    }
  });

  test('no reader on the platform answers null', () async {
    answer((_) => null);
    expect(await AdtoAdId.provider(), isNull);
    answer((_) => throw PlatformException(code: 'unavailable'));
    expect(await AdtoAdId.provider(), isNull);
  });

  test('the tracking status maps the platform names', () async {
    answer(
      (call) => call.method == 'requestTracking' ? 'authorized' : 'denied',
    );
    expect(await AdtoAdId.trackingStatus(), AdtoTrackingStatus.denied);
    expect(await AdtoAdId.requestTracking(), AdtoTrackingStatus.authorized);
    answer((_) => 'something-new');
    expect(await AdtoAdId.trackingStatus(), AdtoTrackingStatus.notSupported);
  });

  test('the provider fits AdtoConfig.advertisingIdProvider', () {
    const config = AdtoConfig(
      apiKey: 'adto_pub_test',
      advertisingIdProvider: AdtoAdId.provider,
    );
    expect(config.collectsAdId, isTrue);
  });
}
