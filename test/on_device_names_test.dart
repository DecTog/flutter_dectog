import 'dart:io';

import 'package:flutter_adto/src/services/install_state_store.dart';
import 'package:flutter_adto/src/services/sdk_config_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Once an app ships, its users' install state lives under these names. A
/// later version that renamed any of them would lose that state, and every
/// existing user would register as a new install. So the folder, the files
/// and the iOS Keychain service are pinned here.
void main() {
  test('the state files keep their names', () {
    expect(InstallStateStore.fileName, '.adto_install.json');
    expect(SdkConfigStore.fileName, '.adto_sdk_config.json');
  });

  // The private names are pinned at the source, where a rename would land.
  final frozen = <String, List<String>>{
    'lib/src/services/sdk_storage.dart': ["_subfolder = 'adto'"],
    'lib/src/services/sdk_state_store.dart': ["'.adto_sdk_state.json'"],
    'lib/src/services/event_queue_service.dart': ["'.adto_event_queue.jsonl'"],
    'ios/flutter_adto/Sources/flutter_adto/AdtoKeychain.swift': [
      '"app.adto.sdk"',
    ],
  };
  for (final entry in frozen.entries) {
    test('${entry.key} keeps ${entry.value.join(', ')}', () {
      final source = File(entry.key).readAsStringSync();
      for (final literal in entry.value) {
        expect(source, contains(literal));
      }
    });
  }
}
