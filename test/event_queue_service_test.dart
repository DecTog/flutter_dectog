import 'dart:convert';
import 'dart:io';

import 'package:flutter_adto/src/services/event_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late EventQueueService queue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('adto_queue_test');
    queue = EventQueueService();
    await queue.resetForTest(
      directoryProvider: () async => tempDir,
      sender: null,
    );
  });

  tearDown(() async {
    await queue.resetForTest();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Map<String, Object?> ev(String name) => {
    'type': 'custom',
    'event_name': name,
  };

  test('enqueue persists to disk (one JSONL line per event, FIFO)', () async {
    await queue.enqueue(ev('a'));
    await queue.enqueue(ev('b'));
    expect(queue.pendingCount, 2);

    // Persistence contract: a fresh process reading this file must rebuild
    // exactly this queue (the load path runs once per process in _ensureFile).
    final file = File('${tempDir.path}/.dectog_event_queue.jsonl');
    expect(await file.exists(), isTrue);
    final lines = await file.readAsLines();
    expect(lines, hasLength(2));
    expect(jsonDecode(lines.first)['event_name'], 'a');
    expect(jsonDecode(lines.last)['event_name'], 'b');
  });

  test('flush sends one batch and removes it only on success', () async {
    var shouldSucceed = false;
    final batches = <List<Map<String, Object?>>>[];
    await queue.resetForTest(
      directoryProvider: () async => tempDir,
      sender: (batch) async {
        batches.add(List.of(batch));
        return shouldSucceed ? EventSendOutcome.sent : EventSendOutcome.retry;
      },
    );

    await queue.enqueue(ev('x'));
    await queue.enqueue(ev('y'));
    await queue.flush();
    expect(batches, hasLength(1)); // failed send
    expect(queue.pendingCount, 2); // nothing removed

    shouldSucceed = true;
    await queue.flush();
    expect(batches, hasLength(2));
    expect(queue.pendingCount, 0);
    // Batch order preserved (FIFO)
    expect(batches.last.map((e) => e['event_name']), ['x', 'y']);
  });

  test('oversized events are dropped, not queued', () async {
    await queue.enqueue({
      'type': 'custom',
      'event_name': 'huge',
      'metadata': {'blob': 'x' * 40 * 1024},
    });
    expect(queue.pendingCount, 0);
    expect(queue.droppedCount, 1);
  });

  test('queue is capped at 1000 events, oldest evicted first', () async {
    for (var i = 0; i < 1005; i++) {
      await queue.enqueue(ev('e$i'));
    }
    expect(queue.pendingCount, 1000);
    expect(queue.droppedCount, 5);
    // Every enqueue rewrites the JSONL file (O(n²) I/O by design — the queue
    // is tiny in practice); on a loaded CI box this exceeds the default
    // 30 s, and an abandoned test's enqueues would leak into the next ones.
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'stopped, the queue keeps events on disk and sends none until start',
    () async {
      final sent = <List<Map<String, Object?>>>[];
      Future<EventSendOutcome> sender(List<Map<String, Object?>> batch) async {
        sent.add(batch);
        return EventSendOutcome.sent;
      }

      queue.start(sender: sender);
      queue.stop();
      await queue.enqueue(ev('held'));
      await queue.flush();
      expect(sent, isEmpty);
      expect(queue.pendingCount, 1);
      final file = File('${tempDir.path}/.dectog_event_queue.jsonl');
      expect(
        (await file.readAsLines()).where((l) => l.isNotEmpty),
        hasLength(1),
      );

      queue.start(sender: sender);
      await queue.flush();
      expect(sent.single.single['event_name'], 'held');
      expect(queue.pendingCount, 0);
    },
  );

  test('batch is capped at 100 events per flush', () async {
    final sizes = <int>[];
    await queue.resetForTest(
      directoryProvider: () async => tempDir,
      sender: (batch) async {
        sizes.add(batch.length);
        return EventSendOutcome.sent;
      },
    );
    for (var i = 0; i < 150; i++) {
      await queue.enqueue(ev('e$i'));
    }
    // Enqueue-triggered flushes fire unawaited; the explicit flush picks up
    // whatever remains — total delivered is 150 across batches of ≤100.
    await queue.flush();
    // The unawaited threshold flush may have run first; just assert the cap
    // held on every observed batch and nothing is lost.
    for (final n in sizes) {
      expect(n, lessThanOrEqualTo(100));
    }
    expect(sizes.reduce((a, b) => a + b) + queue.pendingCount, 150);
  });

  test(
    'a batch the server rejected for good is dropped, not retried',
    () async {
      var calls = 0;
      await queue.resetForTest(
        directoryProvider: () async => tempDir,
        sender: (batch) async {
          calls++;
          return EventSendOutcome.drop;
        },
      );
      await queue.enqueue(ev('bad'));
      await queue.flush();
      expect(calls, 1);
      expect(
        queue.pendingCount,
        0,
        reason: 'a 400 must not wedge the queue head',
      );
      expect(queue.droppedBatchCount, 1);
      final file = File('${tempDir.path}/.dectog_event_queue.jsonl');
      expect((await file.readAsLines()).where((l) => l.isNotEmpty), isEmpty);
    },
  );

  test(
    'a flush after a restart sends the events an earlier launch queued',
    () async {
      await queue.enqueue(ev('held'));
      // A new process: nothing in memory until the file is read.
      await queue.resetForTest(
        directoryProvider: () async => tempDir,
        keepFile: true,
      );
      final sent = <List<Map<String, Object?>>>[];
      queue.start(
        sender: (batch) async {
          sent.add(batch);
          return EventSendOutcome.sent;
        },
      );
      await queue.flush();
      expect(sent, hasLength(1));
      expect(sent.single.single['event_name'], 'held');
      expect(queue.pendingCount, 0);
    },
  );

  test('a transient failure keeps the batch for the next tick', () async {
    await queue.resetForTest(
      directoryProvider: () async => tempDir,
      sender: (batch) async => EventSendOutcome.retry,
    );
    await queue.enqueue(ev('later'));
    await queue.flush();
    expect(queue.pendingCount, 1);
    expect(queue.droppedBatchCount, 0);
  });

  group('per-event ids and the queue TTL', () {
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test(
      'every queued event gets a client_event_id, resent unchanged',
      () async {
        final sent = <String>[];
        var outcome = EventSendOutcome.retry;
        await queue.resetForTest(
          directoryProvider: () async => tempDir,
          sender: (batch) async {
            sent.add(jsonEncode(batch));
            return outcome;
          },
        );
        await queue.enqueue(ev('a'));
        await queue.flush(); // lost response: the batch stays
        outcome = EventSendOutcome.sent;
        await queue.flush();
        expect(sent, hasLength(2));
        expect(sent[1], sent[0], reason: 'a resend is byte-identical');
        final id = (jsonDecode(sent[0]) as List).first['client_event_id'];
        expect(id, matches(uuid));
        expect(queue.pendingCount, 0);
      },
    );

    test(
      'the id survives a restart (it is persisted with the event)',
      () async {
        await queue.enqueue(ev('a'));
        final line =
            (await File(
                  '${tempDir.path}/.dectog_event_queue.jsonl',
                ).readAsLines())
                .single;
        expect(jsonDecode(line)['client_event_id'], matches(uuid));
      },
    );

    test('an id the caller set is kept', () async {
      await queue.enqueue({...ev('a'), 'client_event_id': 'mine-0001'});
      final line =
          (await File(
                '${tempDir.path}/.dectog_event_queue.jsonl',
              ).readAsLines())
              .single;
      expect(jsonDecode(line)['client_event_id'], 'mine-0001');
    });

    test('events older than the 7-day TTL are dropped, never sent', () async {
      final sent = <List<Map<String, Object?>>>[];
      await queue.resetForTest(
        directoryProvider: () async => tempDir,
        sender: (batch) async {
          sent.add(batch);
          return EventSendOutcome.sent;
        },
      );
      final old = DateTime.now().subtract(const Duration(days: 8));
      await queue.enqueue({
        ...ev('stale'),
        'client_timestamp': old.toIso8601String(),
      });
      await queue.enqueue({
        ...ev('fresh'),
        'client_timestamp': DateTime.now().toIso8601String(),
      });
      await queue.flush();
      expect(sent.single.map((e) => e['event_name']), ['fresh']);
      expect(queue.droppedCount, 1);
      expect(EventQueueService.eventTtl, const Duration(days: 7));
    });
  });
}
