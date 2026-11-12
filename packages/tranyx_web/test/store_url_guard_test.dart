import 'package:test/test.dart';
import 'package:tranyx_web/components/store_url_guard.dart';

void main() {
  test('accepts official store listings', () {
    expect(safeStoreUrl('https://apps.apple.com/ph/app/tranyx/id123'), isNotNull);
    expect(safeStoreUrl('https://play.google.com/store/apps/details?id=com.terraph.tranyx'), isNotNull);
    expect(safeStoreUrl('https://apps.apple.com/app/x', hosts: {kAppStoreHost}), isNotNull);
  });
  test('rejects other schemes, hosts, userInfo and ports', () {
    for (final bad in [
      '',
      'http://apps.apple.com/app/x',
      'javascript:alert(1)',
      'https://evil.com/apps.apple.com',
      'https://apps.apple.com.evil.com/app',
      'https://evilapps.apple.com/app',
      'https://itunes.apple.com/app',
      'https://user@apps.apple.com/app',
      'https://user:pw@play.google.com/store',
      'https://apps.apple.com:8443/app',
      'https://play.google.com:443/store',
      '//play.google.com/store',
    ]) {
      expect(safeStoreUrl(bad), isNull, reason: bad);
    }
  });
  test('per-store pinning', () {
    expect(safeStoreUrl('https://play.google.com/store', hosts: {kAppStoreHost}), isNull);
    expect(safeStoreUrl('https://apps.apple.com/app', hosts: {kPlayStoreHost}), isNull);
  });
}
