import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_dectog/src/services/sdk_signature.dart';
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
    final headers = sdkSignatureHeaders('dtg_testkey', '{"device_id":"d1"}');
    final ts = int.parse(headers['x-dectog-timestamp']!);
    expect(ts, greaterThan(1760000000)); // unix seconds, not milliseconds
    expect(
      headers['x-dectog-signature'],
      'v1=${referenceMac('dtg_testkey', headers['x-dectog-timestamp']!, '{"device_id":"d1"}')}',
    );
  });

  test('signs the empty string for GETs', () {
    final headers = sdkSignatureHeaders('dtg_testkey', '');
    expect(
      headers['x-dectog-signature'],
      'v1=${referenceMac('dtg_testkey', headers['x-dectog-timestamp']!, '')}',
    );
    // Distinct from a one-char body — the binding is real.
    final other = sdkSignatureHeaders('dtg_testkey', 'x');
    expect(other['x-dectog-signature'], isNot(headers['x-dectog-signature']));
  });

  test('the MAC key is the API key: different keys, different signatures', () {
    final a = sdkSignatureHeaders('dtg_aaaa', 'same-body');
    final b = sdkSignatureHeaders('dtg_bbbb', 'same-body');
    expect(a['x-dectog-signature'], isNot(b['x-dectog-signature']));
  });

  test('timestamps move forward in whole seconds', () {
    final first = sdkSignatureHeaders('k', '');
    final second = sdkSignatureHeaders('k', '');
    final t1 = int.parse(first['x-dectog-timestamp']!);
    final t2 = int.parse(second['x-dectog-timestamp']!);
    expect(t2, greaterThanOrEqualTo(t1));
  });
}
