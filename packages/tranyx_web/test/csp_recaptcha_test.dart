import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('hosting CSP allows the reCAPTCHA Enterprise connect hosts', () {
    final hosting = jsonDecode(File('../../firebase.json').readAsStringSync())['hosting'] as Map;
    final headers = ((hosting['headers'] as List).first as Map)['headers'] as List;
    final csp = headers
        .cast<Map>()
        .firstWhere((header) => header['key'] == 'Content-Security-Policy')['value'] as String;
    final connect = RegExp(r'connect-src [^;]+').firstMatch(csp)!.group(0)!;
    for (final origin in const [
      'https://www.google.com/recaptcha/',
      'https://www.gstatic.com/recaptcha/',
      'https://www.recaptcha.net',
      'https://recaptcha.net',
      'https://recaptcha.google.com',
      'https://signaler-pa.clients6.google.com',
      'https://signaler-pa.googleapis.com',
      'https://signaler-pa.youtube.com',
      'https://play.google.com',
      'https://content-firebaseappcheck.googleapis.com',
      'https://firebasevertexai.googleapis.com',
    ]) {
      expect(connect, contains(origin), reason: origin);
    }
    expect(csp, contains('frame-src'));
    expect(csp, contains('https://recaptcha.google.com/recaptcha/'));
  });
}
