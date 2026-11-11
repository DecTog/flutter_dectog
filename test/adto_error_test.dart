import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdtoError.fromResponse (server error envelope)', () {
    test('reads code, message and request id from the envelope', () {
      final e = AdtoError.fromResponse(
        statusCode: 401,
        body:
            '{"error":{"code":"invalid_signature","message":"Invalid SDK request signature","request_id":"8c1f-AMS"}}',
        fallbackMessage: 'Request failed (HTTP 401)',
        headerRequestId: 'header-id',
      );
      expect(e.type, AdtoErrorType.api);
      expect(e.statusCode, 401);
      expect(e.code, 'invalid_signature');
      expect(e.message, 'Invalid SDK request signature');
      expect(e.requestId, '8c1f-AMS');
      expect(e.toString(), contains('invalid_signature'));
      expect(e.toString(), contains('8c1f-AMS'));
    });

    test('keeps detail fields and extra details', () {
      final e = AdtoError.fromResponse(
        statusCode: 409,
        body:
            '{"error":{"code":"conflict","message":"Slug already exists","slug":"spring","request_id":"r1"}}',
        fallbackMessage: 'Create failed (HTTP 409)',
        extraDetails: {'retry_after_ms': 1000},
      );
      expect(e.details?['slug'], 'spring');
      expect(e.details?['retry_after_ms'], 1000);
    });

    test('a body that is not the envelope falls back to the header id', () {
      final e = AdtoError.fromResponse(
        statusCode: 502,
        body: '<html>Bad gateway</html>',
        fallbackMessage: 'Create failed (HTTP 502)',
        headerRequestId: 'from-header',
      );
      expect(e.message, 'Create failed (HTTP 502)');
      expect(e.code, isNull);
      expect(e.requestId, 'from-header');
    });

    test('the pre-envelope string shape is not mistaken for a message', () {
      final e = AdtoError.fromResponse(
        statusCode: 400,
        body: '{"error":"old shape"}',
        fallbackMessage: 'Create failed (HTTP 400)',
      );
      expect(e.message, 'Create failed (HTTP 400)');
      expect(e.code, isNull);
    });
  });
}
