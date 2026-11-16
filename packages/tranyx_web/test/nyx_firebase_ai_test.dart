import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tranyx_web/services/tranyx_firebase_ai.dart';

const _json = {'content-type': 'application/json'};

http.Response _ok(String text) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'content': {
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  }),
  200,
  headers: _json,
);

void main() {
  final logs = <String>[];
  late void Function(String message) previousLog;

  setUp(() {
    logs.clear();
    previousLog = TranyxFirebaseAi.log;
    TranyxFirebaseAi.log = logs.add;
  });

  tearDown(() {
    TranyxFirebaseAi.log = previousLog;
  });

  test('Gemini Developer API path is projects/models, not the Vertex publishers route', () {
    final uri = TranyxFirebaseAi.endpoint('tranyx-app');
    expect(uri.path, '/v1beta/projects/tranyx-app/models/gemini-flash-latest:generateContent');
    expect(uri.path, isNot(contains('publishers')));
    expect(
      TranyxFirebaseAi.failureLog(
        401,
        jsonEncode({
          'error': {
            'status': 'UNAUTHENTICATED',
            'message':
                'Firebase App Check token is invalid. See https://example.test/secret AIzaSySECRETKEY123456 token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1In0.c2ln',
          },
        }),
      ),
      allOf(
        contains('status=401'),
        contains('UNAUTHENTICATED'),
        contains('[url]'),
        contains('[key]'),
        contains('[token]'),
        isNot(contains('AIza')),
      ),
    );
    expect(TranyxFirebaseAi.shouldRetry(404), isFalse);
    expect(TranyxFirebaseAi.shouldRetry(503), isTrue);
  });

  test('a 200 on the model path is the answer, and the App Check header is sent', () async {
    final posts = <http.Request>[];
    final client = MockClient((request) async {
      posts.add(request);
      return _ok('Escrow pays the worker after the completion QR.');
    });
    final answer = await TranyxFirebaseAi().reply(
      message: 'How does gig escrow work?',
      signedIn: true,
      idToken: 'id-token',
      nowMs: 1_700_000_000_000,
      httpClient: client,
      retryDelay: Duration.zero,
      appCheck: (_, _) async => 'app-check-token',
    );
    expect(answer, 'Escrow pays the worker after the completion QR.');
    expect(posts, hasLength(1));
    expect(posts.single.url.path, endsWith('/models/gemini-flash-latest:generateContent'));
    expect(posts.single.url.path, isNot(contains('publishers')));
    expect(posts.single.headers['x-firebase-appcheck'], 'app-check-token');
    expect(posts.single.headers['authorization'], 'Firebase id-token');
    expect(logs, isEmpty);
  });

  test('a 503 is retried once and the second answer is shown', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'error': {'status': 'UNAVAILABLE', 'message': 'overloaded'},
          }),
          503,
          headers: _json,
        );
      }
      return _ok('A host approves the booking, then the renter signs.');
    });
    final answer = await TranyxFirebaseAi().reply(
      message: 'How does a rental booking work?',
      signedIn: false,
      nowMs: 1_700_000_000_000,
      httpClient: client,
      retryDelay: Duration.zero,
      appCheck: (_, _) async => 'app-check-token',
    );
    expect(calls, 2);
    expect(answer, 'A host approves the booking, then the renter signs.');
    expect(logs.single, contains('status=503'));
  });

  test('the Vertex 404 is logged and not retried', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return http.Response('<html>Error 404 (Not Found)</html>', 404);
    });
    final answer = await TranyxFirebaseAi().reply(
      message: 'How does gig escrow work?',
      signedIn: true,
      nowMs: 1_700_000_000_000,
      httpClient: client,
      retryDelay: Duration.zero,
      appCheck: (_, _) async => 'app-check-token',
    );
    expect(calls, 1);
    expect(answer, TranyxFirebaseAi.unavailable);
    expect(logs.single, contains('status=404'));
    expect(logs.single, contains('non-json body'));
    expect(logs.single, isNot(contains('<html>')));
  });

  test('a missing App Check token is refreshed once after 401', () async {
    var reads = 0;
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      if (request.headers['x-firebase-appcheck'] == 'fresh') return _ok('Withdrawals use the wallet screen.');
      return http.Response(
        jsonEncode({
          'error': {'code': 401, 'status': 'UNAUTHENTICATED', 'message': 'Firebase App Check token is invalid.'},
        }),
        401,
        headers: _json,
      );
    });
    final answer = await TranyxFirebaseAi().reply(
      message: 'How do I withdraw from my wallet?',
      signedIn: true,
      nowMs: 1_700_000_000_000,
      httpClient: client,
      retryDelay: Duration.zero,
      appCheck: (_, _) async {
        reads += 1;
        return reads == 1 ? null : 'fresh';
      },
    );
    expect(reads, 2);
    expect(calls, 2);
    expect(answer, 'Withdrawals use the wallet screen.');
    expect(
      logs.single,
      allOf(contains('status=401'), contains('appCheck=missing'), contains('App Check token is invalid')),
    );
  });
}
