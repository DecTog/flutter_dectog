// A stand-in AdTo API for tool/device_restart_test.sh. It records
// every install registration and answers 503 until told otherwise, then the
// organic verdict of test/fixtures/wire/. Every other /api/v1 call gets a
// 200. Request signatures are not checked.
//
//   dart run tool/mock_install_server.dart [port]
//   POST /_mock/accept   start answering installs with 200
//   GET  /_mock/installs the recorded install bodies, in order
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8799 : int.parse(args.first);
  final verdict =
      jsonDecode(
              File(
                'test/fixtures/wire/install-verdict-organic.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>
        ..remove(r'$source');
  final installs = <Map<String, dynamic>>[];
  var accept = false;

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('mock AdTo API on :$port');
  await for (final req in server) {
    final body = await utf8.decoder.bind(req).join();
    final path = req.uri.path;
    Object? answer = <String, dynamic>{};
    var status = 200;
    if (path == '/_mock/accept') {
      accept = true;
    } else if (path == '/_mock/installs') {
      answer = installs;
    } else if (req.method == 'POST' && path == '/api/v1/app-installs') {
      installs.add(jsonDecode(body) as Map<String, dynamic>);
      stdout.writeln(
        'install #${installs.length} '
        'attempt_id=${installs.last['install_attempt_id']} '
        '-> ${accept ? 200 : 503}',
      );
      if (accept) {
        answer = verdict;
      } else {
        status = 503;
        answer = {
          'error': {
            'code': 'unavailable',
            'message': 'mock outage',
            'request_id': 'mock',
          },
        };
      }
    } else if (path == '/api/v1/attribution') {
      status = 404;
      answer = {
        'error': {
          'code': 'not_found',
          'message': 'no install',
          'request_id': 'mock',
        },
      };
    }
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(answer));
    await req.response.close();
  }
}
