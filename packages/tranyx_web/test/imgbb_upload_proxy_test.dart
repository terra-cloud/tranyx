// ImgBBService uploads only through the signed-in uploadImageProxy callable.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tranyx_web/services/firebase_service.dart';

const _json = {'content-type': 'application/json'};

void main() {
  final png = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4];
  final seen = <String>[];
  late http.Response Function() proxyReply;

  setUpAll(() {
    SecureFirebaseHttpClient.mockClient = MockClient((req) async {
      if (req.url.path.endsWith('/uploadImageProxy')) {
        seen.add('proxy');
        return proxyReply();
      }
      if (req.url.host == 'api.imgbb.com') {
        seen.add('imgbb');
        return http.Response('should-not-be-called', 200);
      }
      return http.Response(jsonEncode({'error': {'code': 404, 'status': 'NOT_FOUND', 'message': 'NOT_FOUND'}}), 404, headers: _json);
    });
  });

  setUp(() {
    seen.clear();
    proxyReply = () => http.Response(jsonEncode({'result': {'url': 'https://i.ibb.co/p/proxy.png'}}), 200, headers: _json);
  });

  Future<String?> upload({String? token = 'tok'}) =>
      ImgBBService(null, idToken: token).uploadImageBytes(png, 'pic.png');

  test('proxy answers: its URL is returned and imgbb is not called', () async {
    expect(await upload(), 'https://i.ibb.co/p/proxy.png');
    expect(seen, ['proxy']);
  });

  test('proxy refuses the file: the proxy message is shown', () async {
    proxyReply = () => http.Response(
          jsonEncode({'error': {'status': 'INVALID_ARGUMENT', 'message': 'Only JPEG, PNG, GIF or WebP images can be uploaded.'}}),
          400,
          headers: _json,
        );
    await expectLater(upload(), throwsA(isA<ImageUploadException>().having((e) => e.message, 'message', contains('Only JPEG'))));
    expect(seen, ['proxy']);
  });

  test('signed-out: no proxy call', () async {
    await expectLater(upload(token: null), throwsA(isA<ImageUploadException>().having((e) => e.message, 'message', contains('Sign in'))));
    expect(seen, isEmpty);
  });
}
