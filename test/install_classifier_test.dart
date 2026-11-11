import 'package:flutter_adto/src/services/install_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const day = 24 * 3600 * 1000;
  const t0 = 1760000000000;

  group('Android', () {
    test('first install: lastUpdateTime == firstInstallTime', () {
      expect(
        classifyInstallState(
          isAndroid: true,
          firstInstallTs: t0,
          lastUpdateTs: t0,
        ),
        'install',
      );
    });

    test(
      'an update within the 24 h buffer is still an install (Branch rule)',
      () {
        expect(
          classifyInstallState(
            isAndroid: true,
            firstInstallTs: t0,
            lastUpdateTs: t0 + day - 1,
          ),
          'install',
        );
      },
    );

    test(
      'an app updated days after its first install is an UPDATE — an existing user, never fingerprinted',
      () {
        expect(
          classifyInstallState(
            isAndroid: true,
            firstInstallTs: t0,
            lastUpdateTs: t0 + 30 * day,
          ),
          'update',
        );
      },
    );

    test('unknown timestamps yield null', () {
      expect(classifyInstallState(isAndroid: true, firstInstallTs: t0), isNull);
      expect(classifyInstallState(isAndroid: true), isNull);
    });
  });

  group('iOS', () {
    test(
      'keychain first-install older than this container by > 24 h is a reinstall',
      () {
        expect(
          classifyInstallState(
            isAndroid: false,
            keychainFirstInstallTs: t0,
            documentsCtimeTs: t0 + 10 * day,
            executableCtimeTs: t0 + 10 * day,
            libraryCtimeTs: t0 + 10 * day,
          ),
          'reinstall',
        );
      },
    );

    test('a keychain date written on this install is not a reinstall', () {
      expect(
        classifyInstallState(
          isAndroid: false,
          keychainFirstInstallTs: t0,
          documentsCtimeTs: t0 + 1000,
          executableCtimeTs: t0,
          libraryCtimeTs: t0,
        ),
        'install',
      );
    });

    test('a binary newer than the container by > 24 h is an update', () {
      expect(
        classifyInstallState(
          isAndroid: false,
          executableCtimeTs: t0 + 5 * day,
          libraryCtimeTs: t0,
        ),
        'update',
      );
      expect(
        classifyInstallState(
          isAndroid: false,
          executableCtimeTs: t0 + 3600 * 1000,
          libraryCtimeTs: t0,
        ),
        'install',
      );
    });

    test('only a container date → install; nothing → null', () {
      expect(
        classifyInstallState(isAndroid: false, documentsCtimeTs: t0),
        'install',
      );
      expect(classifyInstallState(isAndroid: false), isNull);
    });
  });
}
