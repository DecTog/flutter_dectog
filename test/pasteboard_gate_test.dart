import 'package:flutter_dectog/src/services/pasteboard_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// The SDK sends only click-bearing pasteboard links, and clears the
/// pasteboard only after the server credited the link and only when nobody
/// copied anything since it was read.
void main() {
  group('carriesClickTag', () {
    test('a link with dtg_click or dtg_l is a signal', () {
      expect(
        PasteboardGate.carriesClickTag(
          'https://demo.dectog.com/welcome?dtg_click=abc123',
        ),
        isTrue,
      );
      expect(
        PasteboardGate.carriesClickTag(
          'https://demo.dectog.com/welcome?utm_source=x&dtg_click=abc123',
        ),
        isTrue,
      );
      expect(
        PasteboardGate.carriesClickTag('myapp://product/42?dtg_l=demo/welcome'),
        isTrue,
      );
    });

    test('a bare share link is not, and is never sent', () {
      expect(
        PasteboardGate.carriesClickTag('https://demo.dectog.com/welcome'),
        isFalse,
      );
      expect(
        PasteboardGate.carriesClickTag('https://example.com/?x=dtg_click'),
        isFalse,
      );
    });
  });

  group('clearIfUnchanged', () {
    late int count;
    late int clears;
    late PasteboardGate gate;

    setUp(() {
      count = 7;
      clears = 0;
      gate = PasteboardGate(
        changeCount: () async => count,
        clear: () async {
          clears++;
          count++; // clearing is a change, as on the real pasteboards
          return true;
        },
      );
    });

    test('clears when the pasteboard is as it was read', () async {
      final mark = await gate.remember();
      expect(await gate.clearIfUnchanged(mark), isTrue);
      expect(clears, 1);
    });

    test('leaves it when the user copied something since', () async {
      final mark = await gate.remember();
      count = 8;
      expect(await gate.clearIfUnchanged(mark), isFalse);
      expect(clears, 0);
    });

    test('never clears what it did not read', () async {
      expect(await gate.clearIfUnchanged(null), isFalse);
      expect(clears, 0);
    });

    test('no change counter means no clearing', () async {
      final blind = PasteboardGate(
        changeCount: () async => null,
        clear: () async {
          clears++;
          return true;
        },
      );
      expect(await blind.clearIfUnchanged(await blind.remember()), isFalse);
      expect(clears, 0);
    });

    test('a counter that throws means no clearing', () async {
      final broken = PasteboardGate(
        changeCount: () async => throw StateError('no pasteboard'),
        clear: () async {
          clears++;
          return true;
        },
      );
      expect(await broken.remember(), isNull);
      expect(await broken.clearIfUnchanged(7), isFalse);
      expect(clears, 0);
    });

    test('clears once', () async {
      final mark = await gate.remember();
      await gate.clearIfUnchanged(mark);
      expect(await gate.clearIfUnchanged(mark), isFalse);
      expect(clears, 1);
    });

    test('two reads keep their own marks: one that is not credited costs '
        'the other nothing', () async {
      final install = await gate.remember(); // the first-launch read
      final paste = await gate.remember(); // the paste control, meanwhile
      // The install verdict did not credit its read (its mark is dropped);
      // the paste claim was upgraded.
      expect(install, paste);
      expect(await gate.clearIfUnchanged(paste), isTrue);
      expect(clears, 1);
    });

    test('a read does not clear what was copied after it', () async {
      final first = await gate.remember();
      count = 8; // the user copies another link, and it is read too
      final second = await gate.remember();
      expect(await gate.clearIfUnchanged(first), isFalse); // first credited
      expect(clears, 0);
      expect(await gate.clearIfUnchanged(second), isTrue); // second credited
      expect(clears, 1);
    });
  });
}
