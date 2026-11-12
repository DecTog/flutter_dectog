import 'dart:convert';
import 'dart:io';

import 'package:flutter_adto/src/adto_impl.dart';
import 'package:flutter_test/flutter_test.dart';

/// The golden link-URL cases in test/fixtures/url-cases.json, shared by every
/// SDK port, plus the guarantees around them.
void main() {
  final cases =
      (jsonDecode(File('test/fixtures/url-cases.json').readAsStringSync())
              as Map<String, dynamic>)['cases']
          as List<dynamic>;

  group('url-cases.json', () {
    for (final c in cases.cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final result = parseAdtoUrl(
          Uri.parse(c['url'] as String),
          c['baseUrl'] as String,
          linkRootDomain: c['linkRootDomain'] as String?,
          linkDomains:
              (c['linkDomains'] as List<dynamic>? ?? const []).cast<String>(),
          username: c['username'] as String?,
        );
        final want = c['expect'] as Map<String, dynamic>?;
        expect(result, want?.cast<String, String>());
      });
    }
  });

  test('the full URI, path included, survives for the host app router', () {
    // AdtoLinkClick.originalUrl is uri.toString(): the deep-link path is
    // the HOST APP's route, delivered verbatim, with adto_click readable.
    const raw =
        'istoria://products/42?color=black&adto_click=abc123&adto_l=demo/welcome';
    final uri = Uri.parse(raw);
    expect(uri.toString(), raw);
    expect(uri.queryParameters['adto_click'], 'abc123');
    expect(uri.queryParameters['color'], 'black');
  });
}
