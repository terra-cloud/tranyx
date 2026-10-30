// ImgBBService: the server-side proxy (uploadImageProxy) is tried first; the direct imgbb upload is only the
// fallback when the proxy is unavailable. Host failures read as clear messages (not a bare CORS error).
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tranyx_web/services/firebase_service.dart';

const _json = {'content-type': 'application/json'};

void main() {
  final png = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4];
  final seen = <String>[]; // 'proxy' | 'imgbb' | 'firestore'
  late http.Response Function() proxyReply;
  late http.Response Function() imgbbReply;

  setUpAll(() {
    SecureFirebaseHttpClient.mockClient = MockClient((req) async {
      if (req.url.path.endsWith('/uploadImageProxy')) {
        seen.add('proxy');
        return proxyReply();
      }
      if (req.url.host.contains('firestore')) {
        seen.add('firestore');
        // config/imgbb holds the fallback key (a fake one in this test)
        if (req.method == 'GET' && req.url.path.endsWith('config/imgbb')) {
          return http.Response(jsonEncode({'name': 'projects/p/databases/(default)/documents/config/imgbb', 'fields': {'apiKey': {'stringValue': 'fake-key'}}}), 200, headers: _json);
        }
        return http.Response(jsonEncode({'error': {'code': 404, 'status': 'NOT_FOUND', 'message': 'NOT_FOUND'}}), 404, headers: _json);
      }
      return http.Response('{}', 200);
    });
  });

  setUp(() {
    seen.clear();
    proxyReply = () => http.Response(jsonEncode({'result': {'url': 'https://i.ibb.co/p/proxy.png'}}), 200, headers: _json);
    imgbbReply = () => http.Response(jsonEncode({'data': {'url': 'https://i.ibb.co/d/direct.png'}}), 200);
  });

  Future<String?> upload({String? token = 'tok'}) => http.runWithClient(
        () => ImgBBService(null, idToken: token).uploadImageBytes(png, 'pic.png'),
        () => MockClient((req) async {
          if (req.url.host == 'api.imgbb.com') {
            seen.add('imgbb');
            return imgbbReply();
          }
          return http.Response('{}', 404);
        }),
      );

  test('proxy answers: its URL is used and imgbb is never contacted from the browser', () async {
    expect(await upload(), 'https://i.ibb.co/p/proxy.png');
    expect(seen, ['proxy']);
  });

  test('proxy not deployed (non-JSON 404): falls back to the direct upload', () async {
    proxyReply = () => http.Response('<html>Not Found</html>', 404);
    expect(await upload(), 'https://i.ibb.co/d/direct.png');
    expect(seen.where((s) => s != 'firestore'), ['proxy', 'imgbb']);
  });

  test('proxy refuses the file (INVALID_ARGUMENT): the proxy message is shown, no direct retry', () async {
    proxyReply = () => http.Response(
          jsonEncode({'error': {'status': 'INVALID_ARGUMENT', 'message': 'Only JPEG, PNG, GIF or WebP images can be uploaded.'}}),
          400,
          headers: _json,
        );
    await expectLater(upload(), throwsA(isA<ImageUploadException>().having((e) => e.message, 'message', contains('Only JPEG'))));
    expect(seen, ['proxy']);
  });

  test('signed-out: no proxy call (needs a user), direct only', () async {
    expect(await upload(token: null), 'https://i.ibb.co/d/direct.png');
    expect(seen, isNot(contains('proxy')));
  });

  test('both fail: a clear message instead of a silent failure', () async {
    proxyReply = () => http.Response('<html>nope</html>', 404);
    imgbbReply = () => http.Response('<html>Gateway Time-out</html>', 504);
    await expectLater(upload(), throwsA(isA<ImageUploadException>().having((e) => e.message, 'message', contains('image host'))));
  });
}
