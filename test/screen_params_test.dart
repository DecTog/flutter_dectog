import 'package:flutter_dectog/src/services/screen_params.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('screenParams', () {
    test('keeps strings, finite numbers and booleans; drops the rest', () {
      expect(
        screenParams({
          'id': 7,
          'price': 9.5,
          'ok': false,
          'name': 'shoes',
          'inf': double.infinity,
          'list': [1],
          'map': {'a': 1},
          'none': null,
          3: 'not a string key',
        }),
        {'id': 7, 'price': 9.5, 'ok': false, 'name': 'shoes'},
      );
    });

    test('cuts strings to 256 characters', () {
      expect(screenParams({'q': 'é' * 400})!['q'], 'é' * 256);
    });

    test('an allow-list keeps only its keys', () {
      expect(screenParams({'id': 1, 'email': 'a@b.c'}, allow: {'id'}), {
        'id': 1,
      });
      expect(screenParams({'email': 'a@b.c'}, allow: {'id'}), isNull);
    });

    test('nothing left is null', () {
      expect(screenParams(null), isNull);
      expect(screenParams({}), isNull);
      expect(screenParams({'x': null}), isNull);
    });
  });
}
