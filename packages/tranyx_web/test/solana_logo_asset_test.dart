import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Solana logo asset ships with the web build and every Solana option uses it', () {
    expect(File('web/images/solana_logo.png').existsSync(), isTrue);
    final helpers = File('lib/components/ui_helpers.dart').readAsStringSync();
    expect(helpers, contains("'/images/solana_logo.png'"));
    for (final f in [
      'lib/client/widgets/payment_modal.dart',
      'lib/client/widgets/withdraw_modal.dart',
      'lib/client/views/profile_view.dart',
    ]) {
      expect(File(f).readAsStringSync(), contains('solanaLogo('), reason: f);
    }
  });
}
