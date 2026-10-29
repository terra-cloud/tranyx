import 'dart:async';
import 'package:tranyx_web/client/ledger_summary.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 10, 29);
  final ledger = <Map<String, dynamic>>[
    {'type': 'credit', 'category': 'job_payout', 'amount': 1455.0, 'status': 'Released', 'timestamp': now.subtract(const Duration(days: 8)).millisecondsSinceEpoch},
    {'type': 'debit', 'category': 'withdrawal', 'amount': 3500.0, 'status': 'Completed', 'timestamp': now.subtract(const Duration(days: 40)).millisecondsSinceEpoch},
    {'type': 'debit', 'category': 'withdrawal', 'amount': 900.0, 'status': 'REJECTED', 'timestamp': now.millisecondsSinceEpoch},
    {'type': 'debit', 'category': 'purchase', 'amount': 2400.0, 'status': 'Successful', 'timestamp': now.millisecondsSinceEpoch},
    {'type': 'credit', 'category': 'refund', 'amount': 3000.0, 'status': 'Refunded', 'timestamp': now.millisecondsSinceEpoch},
    {'type': 'credit', 'category': 'topup', 'amount': 5000.0, 'status': 'Completed', 'timestamp': now.millisecondsSinceEpoch},
  ];
  test('tabs and totals', () {
    expect(ledger.where((t) => ledgerMatchesTab(t, 'earnings')).length, 3);
    expect(ledger.where((t) => ledgerMatchesTab(t, 'purchases')).length, 3);
    expect(ledger.where((t) => ledgerMatchesTab(t, 'deposits')).length, 2);
    expect(ledgerSum(ledger, (t) => t['category'] == 'withdrawal'), 3500.0); // rejected excluded
    expect(ledgerSum(ledger, (t) => t['category'] == 'refund'), 3000.0);
    expect(ledger.where((t) => ledgerInPeriod(t, 30, now: now)).length, 5);
    expect(ledgerCsv(ledger).split('\n').length, ledger.length + 1);
  });
  test('csv neutralises formula injection', () {
    final csv = ledgerCsv([
      {'date': 'Oct 29', 'title': '=HYPERLINK("x")', 'categoryLabel': '+cmd', 'method': '-1+1', 'status': '@SUM(A1)', 'type': 'debit', 'amount': 12.5},
    ]);
    final row = csv.split('\n')[1];
    expect(row, contains('"\'=HYPERLINK(""x"")"'));
    expect(row, contains('"\'+cmd"'));
    expect(row, contains('"\'-1+1"'));
    expect(row, contains('"\'@SUM(A1)"'));
    expect(row.endsWith(',12.50'), isTrue);
    expect(csvSafeCell('\tx'), '"\'\tx"');
    expect(csvSafeCell('\rx'), '"\'\rx"');
    expect(csvSafeCell(' =1+1'), '"\' =1+1"');
    expect(csvSafeCell('a=1'), '"a=1"');
    expect(csvSafeCell('\u00a0=1'), '"\'\u00a0=1"');
    expect(csvSafeCell('\u200b=1'), '"\'\u200b=1"');
    expect(csvSafeCell('\ufeff+1'), '"\'\ufeff+1"');
    expect(ledgerAmount({'amount': '12.5'}), 12.5);
    expect(ledgerAmount({'amount': 'abc'}), isNull);
    expect(ledgerAmount({'amount': 3}), 3.0);
    for (final v in ['NaN', 'Infinity', '-Infinity', double.nan, double.infinity, double.negativeInfinity]) {
      expect(ledgerAmount({'id': 'nf$v', 'amount': v}), isNull, reason: '$v');
    }
    final nanRows = [{'id': 'n1', 'amount': 5, 'type': 'credit'}, {'id': 'n2', 'amount': double.nan, 'type': 'credit'}];
    expect(ledgerSum(nanRows, (_) => true), 5.0);
    expect(ledgerCsv(nanRows).split('\n')[2].endsWith(',"INVALID_AMOUNT"'), isTrue);
    final bad = [{'id': 't1', 'amount': '12.5', 'type': 'credit'}, {'id': 't2', 'amount': 'abc', 'type': 'credit'}, {'id': 't3', 'amount': 2, 'type': 'credit'}];
    expect(ledgerSum(bad, (_) => true), 14.5);
    expect(ledgerCsv(bad).split('\n')[2].endsWith(',"INVALID_AMOUNT"'), isTrue);
    expect(ledgerCsv([{'amount': '7'}]).endsWith(',7.00'), isTrue);
  });

  test('invalid amount logs once per row', () {
    final logs = <String>[];
    runZoned(() {
      final row = {'id': 'once1', 'amount': 'bad'};
      ledgerAmount(row);
      ledgerAmount(row);
      ledgerCsv([row]);
      ledgerSum([row], (_) => true);
      ledgerAmount({'id': 'once2', 'amount': double.nan});
    }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => logs.add(line)));
    expect(logs.where((l) => l.contains('id=once1')).length, 1);
    expect(logs.where((l) => l.contains('id=once2')).length, 1);
  });
}
