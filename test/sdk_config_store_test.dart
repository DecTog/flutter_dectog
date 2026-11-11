import 'dart:convert';
import 'dart:io';

import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_adto/src/services/sdk_config_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server's SDK settings are cached on disk for cache_seconds.
void main() {
  late Directory dir;
  final store = SdkConfigStore();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('adto_sdk_config');
    store.resetForTest(directoryProvider: () async => dir);
  });
  tearDown(() async {
    store.resetForTest();
    await dir.delete(recursive: true);
  });

  final fixture =
      jsonDecode(File('test/fixtures/wire/sdk-config.json').readAsStringSync())
          as Map<String, dynamic>;

  test('parses the wire shape', () {
    final c = AdtoSdkConfig.fromJson(fixture);
    expect(c.fbAppId, '1234567890');
    expect(c.readClipboardOnInstall, isTrue);
    expect(c.linkHosts, [
      'go.acme.app',
      'acme.dectog.com',
    ]); // as in the server's fixture
    expect(c.username, 'acme');
    expect(c.environment, AdtoEnvironment.live);
    expect(c.cacheSeconds, 3600);
    expect(
      AdtoSdkConfig.fromJson({...fixture, 'environment': 'test'}).environment,
      AdtoEnvironment.test,
    );
    expect(c.toJson()['environment'], 'live');
  });

  test(
    'a saved config survives a restart and is fresh for cache_seconds',
    () async {
      final t0 = DateTime(2026, 10, 14, 12);
      await store.save(AdtoSdkConfig.fromJson(fixture), now: t0);
      store.resetForTest(directoryProvider: () async => dir);
      final loaded = await store.load();
      expect(loaded?.fbAppId, '1234567890');
      expect(store.isFresh(now: t0.add(const Duration(minutes: 59))), isTrue);
      expect(store.isFresh(now: t0.add(const Duration(minutes: 61))), isFalse);
    },
  );

  test('nothing cached is not fresh', () async {
    expect(await store.load(), isNull);
    expect(store.isFresh(), isFalse);
  });
}
