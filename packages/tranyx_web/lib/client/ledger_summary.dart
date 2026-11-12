/// W58 Transaction History helpers: tab/period matching and totals over the live unified ledger.
bool ledgerIsCancelled(Map<String, dynamic> tx) {
  final status = (tx['status'] ?? '').toString().toUpperCase();
  return tx['type'] == 'cancelled' || status == 'CANCELLED' || status == 'REJECTED';
}

/// tabs: 'all' | 'earnings' | 'purchases' | 'deposits'
bool ledgerMatchesTab(Map<String, dynamic> tx, String tab) {
  final cat = tx['category'];
  final credit = tx['type'] == 'credit';
  switch (tab) {
    case 'earnings':
      return cat == 'job_payout' || cat == 'withdrawal' || (credit && cat != 'topup' && cat != 'refund');
    case 'purchases':
      return cat == 'purchase' || cat == 'fee' || cat == 'refund' || cat == 'topup' || (tx['type'] == 'debit' && cat != 'withdrawal');
    case 'deposits':
      return cat == 'topup' || cat == 'refund';
    default:
      return true;
  }
}

bool ledgerInPeriod(Map<String, dynamic> tx, int periodDays, {DateTime? now}) {
  if (periodDays <= 0) return true;
  final ts = (tx['timestamp'] as num?)?.toInt() ?? 0;
  final cutoff = (now ?? DateTime.now()).subtract(Duration(days: periodDays)).millisecondsSinceEpoch;
  return ts >= cutoff;
}

double ledgerSum(Iterable<Map<String, dynamic>> items, bool Function(Map<String, dynamic>) where) {
  var total = 0.0;
  for (final tx in items) {
    if (ledgerIsCancelled(tx) || !where(tx)) continue;
    final a = ledgerAmount(tx);
    if (a == null) continue; // invalid amount: excluded, never counted as 0
    total += a;
  }
  return total;
}

/// Amount as double; num or numeric String. Returns null (and logs once per tx id) if missing/unparseable/non-finite.
double? ledgerAmount(Map<String, dynamic> tx) {
  final a = tx['amount'];
  double? v;
  if (a is num) v = a.toDouble();
  if (a is String) v = num.tryParse(a.trim())?.toDouble();
  if (v != null && !v.isFinite) v = null;
  if (v == null) _warnInvalidAmount(tx);
  return v;
}

final Set<String> _loggedInvalidAmounts = {};
void _warnInvalidAmount(Map<String, dynamic> tx) {
  final id = (tx['id'] ?? '?').toString();
  if (_loggedInvalidAmounts.add(id)) print('[ledger] invalid amount on tx id=$id');
}

/// Neutralises spreadsheet formula injection: cells starting with tab or CR, or whose first non-whitespace char is = + - @, get a leading single quote.
String csvSafeCell(Object? v) {
  var s = (v ?? '').toString();
  final t = s.replaceFirst(RegExp('^[\\s\u200B\u200C\u200D\uFEFF]+'), '');
  if (s.isNotEmpty && ('\t\r'.contains(s[0]) || (t.isNotEmpty && '=+-@'.contains(t[0])))) s = "'$s";
  return '"${s.replaceAll('"', '""')}"';
}

/// CSV of the given (already user-scoped) ledger rows. Amount is a real number, never user text.
String ledgerCsv(Iterable<Map<String, dynamic>> items) {
  final rows = <String>['Date,Title,Category,Method,Status,Type,Amount'];
  for (final tx in items) {
    final a = ledgerAmount(tx);
    final amount = a == null ? csvSafeCell('INVALID_AMOUNT') : a.toStringAsFixed(2);
    rows.add([...[tx['date'], tx['title'], tx['categoryLabel'], tx['method'], tx['status'], tx['type']].map(csvSafeCell), amount].join(','));
  }
  return rows.join('\n');
}
