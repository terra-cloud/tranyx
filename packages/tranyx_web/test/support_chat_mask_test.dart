import 'dart:io';

import 'package:test/test.dart';

// TRAD-6: a full overwrite of support_chats/<uid> on every user message wiped the desk
// fields (status, assignedAgentId) staff set. Parent writes must use the masked setDocument.
void main() {
  test('support_chats parent doc is never fully overwritten', () {
    final src = File('lib/services/firebase_service.dart').readAsStringSync();
    expect(src.contains("createOrUpdate('support_chats/"), isFalse);
    expect("setDocument('support_chats/\$uid'".allMatches(src).length, 2);
  });
}
