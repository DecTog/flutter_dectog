import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'install_state_store.dart' show uuidV4;
import 'sdk_storage.dart';

/// What the server said about one batch.
enum EventSendOutcome {
  /// Accepted: the batch leaves the queue.
  sent,

  /// Transient failure (network, 5xx, 401/408/429): the batch stays at the
  /// head and is retried on the next tick.
  retry,

  /// Rejected for good (other 4xx — malformed events): the batch is
  /// discarded so it can never wedge the queue head (Branch drops 400–451).
  drop,
}

/// Sends one batch of queued events.
typedef EventBatchSender =
    Future<EventSendOutcome> Function(List<Map<String, Object?>> batch);

/// Durable post-install event queue.
///
/// Events (identify / lead / conversion / custom) are appended to a JSONL
/// file in the SDK's backup-excluded storage directory (see
/// [SdkStorage]) and delivered in batches to POST /api/v1/events. Constants
/// follow values battle-tested by comparable SDKs: flush at 20
/// events or every 30 s, at most 1000 queued events, batches of 100, 32 KB
/// ceiling per serialized event. Delivery is at-least-once; a failed batch
/// stays at the head of the queue for the next tick unless the server
/// rejected it for good ([EventSendOutcome.drop]).
///
/// Each event is stamped with a `client_event_id` when it is queued and
/// persisted with it, so a resend is byte-identical and the server stores it
/// once. Events older than [eventTtl] (by `client_timestamp`) are dropped
/// unsent: the server deduplicates for as long as it keeps an event, and it
/// drops events older than 7 days, as the queue does.
///
/// Pure Dart (dart:io) so it is unit-testable with a temp directory and a
/// mock sender — no platform channel and no HTTP import here.
class EventQueueService {
  EventQueueService._internal();
  static final EventQueueService _instance = EventQueueService._internal();

  /// Singleton instance (matches the other SDK services).
  factory EventQueueService() => _instance;

  static const String _queueFileName = '.dectog_event_queue.jsonl';

  static const int _flushThreshold = 20;
  static const Duration _flushInterval = Duration(seconds: 30);
  static const int _maxQueueSize = 1000;
  static const int _maxBatchSize = 100;
  static const int _maxEventBytes = 32 * 1024;

  /// How long an undelivered event is kept.
  static const Duration eventTtl = Duration(days: 7);

  final List<Map<String, Object?>> _queue = [];
  File? _file;
  Future<void>? _loading;
  Timer? _timer;
  EventBatchSender? _sender;
  bool _sending = false;
  int _droppedEvents = 0;
  int _droppedBatches = 0;

  /// For tests and dispose: inject the directory + sender and reset state.
  @visibleForTesting
  Future<void> resetForTest({
    Future<Directory> Function()? directoryProvider,
    EventBatchSender? sender,
    bool keepFile = false,
  }) async {
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _file = null;
    _loading = null;
    _sender = sender;
    _sending = false;
    _droppedEvents = 0;
    _droppedBatches = 0;
    if (directoryProvider != null) {
      final dir = await directoryProvider();
      _file = File('${dir.path}/$_queueFileName');
      // keepFile: a simulated restart, whose first use reads the file.
      if (keepFile) return;
      _loading = Future.value(); // the test dir starts empty by definition
      if (await _file!.exists()) {
        await _file!.delete();
      }
    }
  }

  /// Begin periodic flushing. Safe to call repeatedly.
  void start({required EventBatchSender sender}) {
    _sender = sender;
    _timer ??= Timer.periodic(_flushInterval, (_) => flush());
  }

  /// Number of events currently queued (visible for tests/diagnostics).
  int get pendingCount => _queue.length;

  /// Events discarded (oversized or evicted under the size cap).
  @visibleForTesting
  int get droppedCount => _droppedEvents;

  /// Batches the server rejected for good.
  @visibleForTesting
  int get droppedBatchCount => _droppedBatches;

  /// Stop sending, keeping queued events (and new ones) on disk for the
  /// next [start]. Also what `setEnabled(false)` does; a flush called
  /// while stopped sends nothing.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _sender = null;
  }

  /// Load persisted events once per process. Concurrent callers share one
  /// read, so an enqueue racing the first load can't persist over it.
  Future<void> _ensureFile() => _loading ??= _load();

  Future<void> _load() async {
    _file ??= File('${(await SdkStorage().directory()).path}/$_queueFileName');
    // Corrupt lines are dropped — a half-written tail line must never wedge
    // the queue.
    if (await _file!.exists()) {
      final lines = await _file!.readAsLines();
      final persisted = <Map<String, Object?>>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, Object?>) persisted.add(decoded);
        } catch (_) {}
      }
      _queue.insertAll(0, persisted);
    }
  }

  /// Queue one event. Oversized events are dropped (counted), never block
  /// the caller. Triggers a flush once the threshold is reached.
  Future<void> enqueue(Map<String, Object?> input) async {
    final event = {
      ...input,
      'client_event_id': input['client_event_id'] ?? uuidV4(),
    };
    final encoded = jsonEncode(event);
    if (utf8.encode(encoded).length > _maxEventBytes) {
      _droppedEvents++;
      return;
    }
    await _ensureFile();
    _queue.add(event);
    while (_queue.length > _maxQueueSize) {
      _queue.removeAt(0); // oldest events go first under pressure
      _droppedEvents++;
    }
    await _persist();
    if (_queue.length >= _flushThreshold) {
      unawaited(flush());
    }
  }

  /// Try to deliver up to [_maxBatchSize] events. A transient failure keeps
  /// the batch queued, a permanent rejection discards it; concurrent calls
  /// coalesce.
  Future<void> flush() async {
    final sender = _sender;
    if (sender == null || _sending) return;
    _sending = true;
    try {
      // The file first: events an earlier launch queued are in it, not yet
      // in memory, until something loads it.
      await _ensureFile();
      await _dropExpired();
      final batch = _queue.take(_maxBatchSize).toList();
      if (batch.isEmpty) return;
      final outcome = await sender(batch);
      switch (outcome) {
        case EventSendOutcome.sent:
          _queue.removeRange(0, batch.length);
          await _persist();
        case EventSendOutcome.drop:
          _droppedBatches++;
          _queue.removeRange(0, batch.length);
          await _persist();
        case EventSendOutcome.retry:
          break;
      }
    } catch (_) {
      // Sender errors mean "retry later" — the batch stays queued.
    } finally {
      _sending = false;
    }
  }

  /// Drop events queued longer than [eventTtl] ago (counted as dropped).
  Future<void> _dropExpired() async {
    final cutoff = DateTime.now().subtract(eventTtl);
    final before = _queue.length;
    _queue.removeWhere((event) {
      final at = event['client_timestamp'];
      final parsed = at is String ? DateTime.tryParse(at) : null;
      return parsed != null && parsed.isBefore(cutoff);
    });
    final expired = before - _queue.length;
    if (expired > 0) {
      _droppedEvents += expired;
      await _persist();
    }
  }

  Future<void> _persist() async {
    final file = _file;
    if (file == null) return;
    try {
      final sink = file.openWrite();
      for (final event in _queue) {
        sink.writeln(jsonEncode(event));
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      // Persistence is best-effort; the in-memory queue still flushes.
    }
  }
}
