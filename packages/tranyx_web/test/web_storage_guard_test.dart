import 'dart:io';

import 'package:test/test.dart';

// Guard for the e11dd5c regression: web/index.html loads only the app/auth/firestore
// compat SDKs, so any firebase.storage() call throws at runtime. Uploads go through
// ImgBBService until the Storage migration adds the SDK script and storage.rules.
void main() {
  test('firebase.storage() is not used unless the Storage SDK is loaded', () {
    final html = File('web/index.html').readAsStringSync();
    final loadsStorage = html.contains('firebase-storage-compat.js');
    expect(html.contains('firebase.storage('), loadsStorage ? anything : isFalse);
  });
}
