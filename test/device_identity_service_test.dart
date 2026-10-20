import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dectog/src/services/device_identity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dectog_device_identifiers');

  void mockDeviceId(Object? Function() reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getDeviceId');
          return reply();
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    DeviceIdentityService().resetForTest();
  });

  test('returns and caches the native device id (ANDROID_ID / IDFV)', () async {
    mockDeviceId(() => '8af8770a27cfd182');
    final service = DeviceIdentityService();
    final first = await service.getDeviceId();
    expect(first, '8af8770a27cfd182');

    // Second read must come from the cache even if the channel changes.
    mockDeviceId(() => 'different-value');
    expect(await service.getDeviceId(), '8af8770a27cfd182');
    expect(service.hasStableId, isTrue);
  });

  test(
    'blank native value returns null (device_id omitted, no phantom devices)',
    () async {
      mockDeviceId(() => '');
      final service = DeviceIdentityService();
      expect(await service.getDeviceId(), isNull);
      expect(service.hasStableId, isFalse);
    },
  );

  test('forwards the persist opt-in to the channel (default false)', () async {
    final args = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          args.add(call.arguments);
          return 'idfv';
        });
    final service = DeviceIdentityService();
    await service.getDeviceId();
    service.resetForTest();
    await service.getDeviceId(persist: true);
    expect(args, [
      {'persist': false},
      {'persist': true},
    ]);
  });

  test('platform exception returns null without throwing', () async {
    mockDeviceId(() => throw PlatformException(code: 'unavailable'));
    final service = DeviceIdentityService();
    expect(await service.getDeviceId(), isNull);
  });
}
