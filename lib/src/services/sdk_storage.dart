import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'identifier_channel.dart';

/// The SDK's private, backup-excluded directory.
///
/// Every piece of SDK state — the install sentinel, the persisted SDK
/// state and the event queue — lives here. Earlier builds kept them in the app
/// documents directory, which Android Auto Backup and iCloud restore copy
/// onto a FRESH install: a restored `tracked` sentinel then suppressed the
/// install POST for good. AppsFlyer
/// excludes its preferences from backup and Adjust marks its state files
/// with `NSURLIsExcludedFromBackupKey`; this does the same:
///
///  - Android: `Context.getNoBackupFilesDir()` (via the identifier channel),
///    excluded from both key/value backup and Auto Backup by the platform.
///  - iOS: the Application Support directory with
///    `NSURLIsExcludedFromBackupKey` set on our subfolder (the key applies
///    to the folder's contents).
///  - elsewhere / on any failure: the Application Support directory.
///
/// Resolved once per process; tests inject a temp directory.
class SdkStorage {
  SdkStorage._internal();
  static final SdkStorage _instance = SdkStorage._internal();

  factory SdkStorage() => _instance;

  static const String _subfolder = 'adto';

  Future<Directory>? _directory;
  Future<Directory> Function()? _override;

  /// The storage directory, created on first use.
  Future<Directory> directory() => _directory ??= _resolve();

  Future<Directory> _resolve() async {
    final override = _override;
    if (override != null) return override();
    Directory base;
    try {
      if (Platform.isAndroid) {
        final noBackup = await IdentifierChannel().getNoBackupDirectory();
        base =
            noBackup != null
                ? Directory(noBackup)
                : await getApplicationSupportDirectory();
      } else {
        base = await getApplicationSupportDirectory();
      }
    } catch (_) {
      // path_provider itself failed (headless embed): the documents dir is
      // the last resort, better than no persistence at all.
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/$_subfolder');
    try {
      await dir.create(recursive: true);
    } catch (_) {}
    if (Platform.isIOS) {
      // Best effort: a failed flag leaves the files backed up, which is
      // what earlier builds did everywhere — never worse than before.
      await IdentifierChannel().excludeFromBackup(dir.path);
    }
    return dir;
  }

  /// Tests: point every store at a temp directory (null restores the
  /// platform resolution). Resets the cached resolution either way.
  @visibleForTesting
  void overrideForTest(Future<Directory> Function()? provider) {
    _override = provider;
    _directory = null;
  }
}
