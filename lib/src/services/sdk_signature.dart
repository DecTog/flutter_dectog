import 'dart:convert';

import 'package:crypto/crypto.dart';

/// SDK request signature, mirroring the worker's `verifySdkSignature`
/// (apps/worker/src/auth.ts). Required on every authenticated /api/v1 call:
///
///   x-adto-timestamp: <unix seconds>
///   x-adto-signature: v1=<hex>
///   v1 = HMAC-SHA256(apiKey, "$ts.${sha256hex(rawBody)}")
///
/// The MAC key is the API key itself — the server stores only its sha256 but
/// recomputes the MAC from the presented Bearer credential. GET/HEAD sign the
/// empty string. The ts+body binding makes in-window replays harmless while
/// tolerating device-clock skew inside the server's ±30-minute window
/// (AppsFlyer's af_sig pattern).
Map<String, String> sdkSignatureHeaders(String apiKey, String rawBody) {
  final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final bodyHash = sha256.convert(utf8.encode(rawBody)).toString();
  final mac =
      Hmac(
        sha256,
        utf8.encode(apiKey),
      ).convert(utf8.encode('$ts.$bodyHash')).toString();
  return {'x-adto-timestamp': ts, 'x-adto-signature': 'v1=$mac'};
}
