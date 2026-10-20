import 'dart:io';

import 'package:flutter_dectog/src/services/sdk_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  final store = SdkStateStore();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dectog_state_test');
    await store.resetForTest(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    await store.resetForTest();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('persisted state survives a restart once loaded', () async {
    await store.setCustomerId('user-42');
    await store.setEnabled(false);
    await store.setInstallId('install-1');

    await store.resetForTest(
      directoryProvider: () async => tempDir,
      simulateRestart: true,
    );
    expect(store.customerId, isNull, reason: 'getters read memory only');

    await store.load();
    expect(store.customerId, 'user-42');
    expect(store.enabled, isFalse);
    expect(store.installId, 'install-1');
  });

  test(
    'a setter racing the first load keeps the other persisted fields',
    () async {
      await store.setCustomerId('user-42');
      await store.setEnabled(false);

      await store.resetForTest(
        directoryProvider: () async => tempDir,
        simulateRestart: true,
      );
      await Future.wait([store.load(), store.setInstallId('install-2')]);

      await store.resetForTest(
        directoryProvider: () async => tempDir,
        simulateRestart: true,
      );
      await store.load();
      expect(store.customerId, 'user-42');
      expect(store.enabled, isFalse);
      expect(store.installId, 'install-2');
    },
  );

  test(
    'last identify persists; setEnabled(false) keeps it (the event stays queued), logout clears it',
    () async {
      await store.setCustomerId('user-42', identifyKey: 'k1');

      await store.resetForTest(
        directoryProvider: () async => tempDir,
        simulateRestart: true,
      );
      await store.load();
      expect(store.lastIdentify, 'k1');

      await store.setEnabled(false);
      expect(store.lastIdentify, 'k1');
      expect(store.customerId, 'user-42');

      await store.setCustomerId('user-42', identifyKey: 'k2');
      await store.setCustomerId(null);
      expect(store.lastIdentify, isNull);
    },
  );

  test(
    'without a stored choice the config default applies; a choice wins',
    () async {
      store.defaultEnabled = false;
      expect(store.enabled, isFalse);
      await store.setEnabled(true);
      await store.resetForTest(
        directoryProvider: () async => tempDir,
        simulateRestart: true,
      );
      await store.load();
      store.defaultEnabled = false;
      expect(store.enabled, isTrue);
    },
  );

  test('collection is enabled by default and the choice persists', () async {
    expect(store.enabled, isTrue);
    await store.setEnabled(false);
    await store.resetForTest(
      directoryProvider: () async => tempDir,
      simulateRestart: true,
    );
    await store.load();
    expect(store.enabled, isFalse);

    await store.setEnabled(true);
    await store.resetForTest(
      directoryProvider: () async => tempDir,
      simulateRestart: true,
    );
    await store.load();
    expect(store.enabled, isTrue);
  });

  test('the ping day survives a restart', () async {
    await store.setPingDay('2026-10-18');
    await store.resetForTest(
      directoryProvider: () async => tempDir,
      simulateRestart: true,
    );
    await store.load();
    expect(store.pingDay, '2026-10-18');
  });
}
