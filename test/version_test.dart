import 'dart:io';

import 'package:flutter_adto/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(
      packageVersion,
      match!.group(1),
      reason:
          'lib/src/version.dart must be updated together with '
          'the version in pubspec.yaml',
    );
  });

  test('iOS podspec version matches the package version', () {
    final podspec = File('ios/flutter_adto.podspec').readAsStringSync();
    final match = RegExp(
      r"^  s\.version\s*=\s*'([^']+)'",
      multiLine: true,
    ).firstMatch(podspec);
    expect(
      match,
      isNotNull,
      reason: 'ios/flutter_adto.podspec must declare s.version',
    );
    expect(
      packageVersion,
      match!.group(1),
      reason:
          'ios/flutter_adto.podspec must be updated together with '
          'the version in pubspec.yaml',
    );
  });

  test('the newest CHANGELOG entry is the package version', () {
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final match = RegExp(
      r'^## \[([^\]]+)\]',
      multiLine: true,
    ).firstMatch(changelog);
    expect(
      match,
      isNotNull,
      reason: 'CHANGELOG.md must have a "## [x.y.z]" entry',
    );
    expect(
      match!.group(1),
      packageVersion,
      reason: 'add a CHANGELOG.md entry for every version bump',
    );
  });

  test('the README install snippet accepts the package version', () {
    final readme = File('README.md').readAsStringSync();
    final match = RegExp(
      r'^\s*flutter_adto:\s*\^(\d+)\.(\d+)\.(\d+)',
      multiLine: true,
    ).firstMatch(readme);
    expect(match, isNotNull, reason: 'README.md must show the pubspec line');
    final version = packageVersion.split('-').first.split('.');
    expect(
      match!.group(1),
      version[0],
      reason: 'the README caret range must cover the current major version',
    );
  });

  test('the x-dectog-sdk identity carries the package version', () {
    expect(sdkIdentity, 'flutter_adto/$packageVersion');
  });
}
