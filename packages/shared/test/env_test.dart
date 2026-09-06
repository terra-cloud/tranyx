import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Env Tests', () {
    test('Env.basemapsApiKey resolves correctly', () {
      final key = Env.basemapsApiKey;
      expect(key, isNotEmpty);
      expect(key, equals('cb1_2xny_1_736c21e1c18dab2405ac1774'));
    });
  });
}
