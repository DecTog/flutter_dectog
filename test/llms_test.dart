import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/gen_llms.dart';

/// llms.txt ships in the package for agents, generated from
/// doc/api-reference.md, which is also the docs site's API reference.
void main() {
  final reference = File('doc/api-reference.md').readAsStringSync();

  test(
    'llms.txt is generated from the current sources (dart run tool/gen_llms.dart)',
    () {
      expect(File('llms.txt').readAsStringSync(), expectedLlms());
    },
  );

  test('the reference documents every FlutterDectog member', () {
    final source = File('lib/flutter_dectog.dart').readAsStringSync();
    final body = source.substring(
      source.indexOf('abstract interface class FlutterDectog'),
    );
    final members =
        RegExp(
          r'^  (?!factory|//)[\w<>?, ]+?\s(?:get\s+)?(\w+)\s*[({;]',
          multiLine: true,
        ).allMatches(body).map((m) => m.group(1)!).toSet();
    expect(
      members,
      containsAll([
        'initialize',
        'onLinkClick',
        'setEnabled',
        'getLinks',
        'dispose',
      ]),
    );
    final missing =
        members.where((m) => !reference.contains('| `$m` |')).toList();
    expect(
      missing,
      isEmpty,
      reason: 'add a row for each to doc/api-reference.md',
    );
  });

  test('the reference names every public type', () {
    final types = <String>{};
    for (final dir in ['lib/src/models', 'lib/src/widgets']) {
      for (final f in Directory(dir).listSync().whereType<File>()) {
        final text = f.readAsStringSync();
        types.addAll(
          RegExp(
            r'^(?:abstract |final |sealed |base |interface )*(?:class|enum|extension|typedef) ([A-Z]\w*)',
            multiLine: true,
          ).allMatches(text).map((m) => m.group(1)!),
        );
      }
    }
    expect(
      types,
      containsAll([
        'DectogConfig',
        'DectogAppInstallResponse',
        'DectogLinkPage',
      ]),
    );
    final missing =
        types.where((t) => !RegExp('\\b$t\\b').hasMatch(reference)).toList();
    expect(missing, isEmpty, reason: 'document each in doc/api-reference.md');
  });

  test(
    'the generator keeps every reference section and puts the types first',
    () {
      final llms = File('llms.txt').readAsStringSync();
      for (final title in parseReference(reference).sections.keys) {
        expect(llms, contains('## $title\n'));
      }
      expect(
        llms.indexOf('## DectogConfig'),
        lessThan(llms.indexOf('## FlutterDectog')),
      );
      expect(llms, contains('## Link URLs the SDK recognizes'));
    },
  );
}
