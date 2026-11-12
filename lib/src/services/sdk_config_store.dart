import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/adto_sdk_config.dart';
import 'sdk_storage.dart';

/// The server's SDK settings, cached on disk with the time they were
/// fetched, so a launch without network still uses the last known values.
class SdkConfigStore {
  SdkConfigStore._internal();
  static final SdkConfigStore _instance = SdkConfigStore._internal();
  factory SdkConfigStore() => _instance;

  static const String fileName = '.adto_sdk_config.json';

  AdtoSdkConfig? _config;
  DateTime? _fetchedAt;
  Future<Directory> Function()? _directoryProvider;
  bool _loaded = false;

  AdtoSdkConfig? get config => _config;

  @visibleForTesting
  void resetForTest({Future<Directory> Function()? directoryProvider}) {
    _config = null;
    _fetchedAt = null;
    _loaded = false;
    _directoryProvider = directoryProvider;
  }

  Future<File> _file() async {
    final dir = await (_directoryProvider?.call() ?? SdkStorage().directory());
    return File('${dir.path}/$fileName');
  }

  /// The cached settings, read once per process.
  Future<AdtoSdkConfig?> load() async {
    if (_loaded) return _config;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map<String, dynamic>) {
          final c = decoded['config'];
          _config =
              c is Map<String, dynamic> ? AdtoSdkConfig.fromJson(c) : null;
          _fetchedAt = DateTime.tryParse(
            decoded['fetched_at'] as String? ?? '',
          );
        }
      }
    } catch (_) {}
    return _config;
  }

  /// Whether the cache is younger than its `cache_seconds`.
  bool isFresh({DateTime? now}) {
    final at = _fetchedAt;
    final c = _config;
    if (at == null || c == null) return false;
    return (now ?? DateTime.now()).difference(at) <
        Duration(seconds: c.cacheSeconds);
  }

  Future<void> save(AdtoSdkConfig config, {DateTime? now}) async {
    _config = config;
    _fetchedAt = now ?? DateTime.now();
    _loaded = true;
    try {
      await (await _file()).writeAsString(
        jsonEncode({
          'fetched_at': _fetchedAt!.toIso8601String(),
          'config': config.toJson(),
        }),
      );
    } catch (_) {}
  }
}
