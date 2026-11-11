import 'dart:io';

import 'package:flutter_adto/src/services/install_state_store.dart';
import 'package:flutter_adto/src/services/sdk_config_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// flutter_adto is flutter_dectog renamed. An app that moves from one to the
/// other must find its users' state where flutter_dectog left it, or every
/// existing user registers as a new install. These names are therefore frozen:
/// the folder, the files and the iOS Keychain service keep their DecTog names.
void main() {
  test('the state files keep the names flutter_dectog wrote', () {
    expect(InstallStateStore.fileName, '.dectog_install.json');
    expect(SdkConfigStore.fileName, '.dectog_sdk_config.json');
  });

  // The private names are pinned at the source, where a rename would land.
  final frozen = <String, List<String>>{
    'lib/src/services/sdk_storage.dart': ["_subfolder = 'dectog'"],
    'lib/src/services/sdk_state_store.dart': ["'.dectog_sdk_state.json'"],
    'lib/src/services/event_queue_service.dart': [
      "'.dectog_event_queue.jsonl'",
    ],
    'ios/flutter_adto/Sources/flutter_adto/AdtoKeychain.swift': [
      '"app.dectog.sdk"',
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
