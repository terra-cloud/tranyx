import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('both sign-up account types say they can use rentals', () {
    final src = File('lib/client/views/auth_view.dart').readAsStringSync();
    const note = 'You can rent out and rent vehicles and properties.';
    expect(note.allMatches(src), hasLength(2));
    expect(src, contains("title: 'Nyxian Worker'"));
    expect(src, contains("title: 'Employer'"));
  });
}
