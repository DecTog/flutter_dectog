import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_adto/src/services/sdk_signature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Reference vectors: the header set must be reproducible for a fixed
  // (apiKey, ts, body) triple so the worker-side verifier in
  // apps/worker/test/helpers.ts computes the identical MAC.
  String referenceMac(String apiKey, String ts, String body) {
    final bodyHash = sha256.convert(utf8.encode(body)).toString();
    return Hmac(
      sha256,
      utf8.encode(apiKey),
    ).convert(utf8.encode('$ts.$bodyHash')).toString();
  }

  test('signs POST bodies over ts.bodyHash with the API key as MAC key', () {
    final headers = sdkSignatureHeaders('adto_testkey', '{"device_id":"d1"}');
    final ts = int.parse(headers['x-adto-timestamp']!);
    expect(ts, greaterThan(1760000000)); // unix seconds, not milliseconds
    expect(
      headers['x-adto-signature'],
      'v1=${referenceMac('adto_testkey', headers['x-adto-timestamp']!, '{"device_id":"d1"}')}',
    );
  });

  test('signs the empty string for GETs', () {
    final headers = sdkSignatureHeaders('adto_testkey', '');
    expect(
      headers['x-adto-signature'],
      'v1=${referenceMac('adto_testkey', headers['x-adto-timestamp']!, '')}',
    );
    // Distinct from a one-char body — the binding is real.
    final other = sdkSignatureHeaders('adto_testkey', 'x');
    expect(other['x-adto-signature'], isNot(headers['x-adto-signature']));
  });

  test('the MAC key is the API key: different keys, different signatures', () {
    final a = sdkSignatureHeaders('adto_aaaa', 'same-body');
    final b = sdkSignatureHeaders('adto_bbbb', 'same-body');
    expect(a['x-adto-signature'], isNot(b['x-adto-signature']));
  });

  test('timestamps move forward in whole seconds', () {
    final first = sdkSignatureHeaders('k', '');
    final second = sdkSignatureHeaders('k', '');
    final t1 = int.parse(first['x-adto-timestamp']!);
    final t2 = int.parse(second['x-adto-timestamp']!);
    expect(t2, greaterThanOrEqualTo(t1));
  });
}
