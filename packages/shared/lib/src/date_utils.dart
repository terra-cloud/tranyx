library;

/// Standard short month abbreviations
const List<String> kShortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Safely parses [val] into a [DateTime].
/// Handles [DateTime], epoch ms ([int], [num]), ISO-8601 [String], numeric strings,
/// and objects with `millisecondsSinceEpoch` or `toDate()`.
DateTime? parseDateTime(dynamic val) {
  if (val == null) return null;
  if (val is DateTime) return val;
  if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
  if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt());
  if (val is String) {
    final parsed = DateTime.tryParse(val);
    if (parsed != null) return parsed;
    final asNum = num.tryParse(val);
    if (asNum != null) {
      return DateTime.fromMillisecondsSinceEpoch(asNum.toInt());
    }
  }
  try {
    final dynamic dyn = val;
    if (dyn.millisecondsSinceEpoch is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        dyn.millisecondsSinceEpoch as int,
      );
    }
    if (dyn.toDate is Function) {
      final res = dyn.toDate();
      if (res is DateTime) return res;
    }
  } catch (_) {}
  return null;
}

/// Safely extracts epoch milliseconds as an [int] for sorting or persistence.
int getEpochMs(dynamic val) {
  if (val == null) return 0;
  final dt = parseDateTime(val);
  return dt?.millisecondsSinceEpoch ?? 0;
}

/// Formats a posting date in a user-friendly, human-readable format.
///
/// Output examples:
/// - "Today" (or "Posted Today" when [withPrefix] is true)
/// - "Yesterday" (or "Posted Yesterday" when [withPrefix] is true)
/// - "2 days ago", "3 days ago" (when within 2-6 days)
/// - "Aug 25, 2026" (when 7 or more days ago)
String formatPostingDate(
  dynamic dateOrEpoch, {
  DateTime? now,
  bool withPrefix = false,
}) {
  final dt = parseDateTime(dateOrEpoch);
  if (dt == null) {
    return withPrefix ? 'Posted recently' : 'Recently';
  }

  final current = now ?? DateTime.now();
  final todayStart = DateTime(current.year, current.month, current.day);
  final targetStart = DateTime(dt.year, dt.month, dt.day);

  final diffDays = todayStart.difference(targetStart).inDays;

  String body;
  if (diffDays <= 0) {
    body = 'Today';
  } else if (diffDays == 1) {
    body = 'Yesterday';
  } else if (diffDays < 7) {
    body = '$diffDays days ago';
  } else {
    final monthName = kShortMonths[dt.month - 1];
    body = '$monthName ${dt.day}, ${dt.year}';
  }

  if (withPrefix) {
    if (diffDays >= 7) {
      return 'Posted on $body';
    }
    return 'Posted $body';
  }
  return body;
}

/// Returns true if [dateOrEpoch] occurred on the same calendar day as [now].
bool isPostedToday(dynamic dateOrEpoch, {DateTime? now}) {
  final dt = parseDateTime(dateOrEpoch);
  if (dt == null) return false;
  final current = now ?? DateTime.now();
  return dt.year == current.year &&
      dt.month == current.month &&
      dt.day == current.day;
}

/// Alias for [isPostedToday] to avoid getter shadowing in models.
bool isPostedTodayDate(dynamic dateOrEpoch, {DateTime? now}) =>
    isPostedToday(dateOrEpoch, now: now);

/// Returns true if [dateOrEpoch] was posted within [maxDays] days.
bool isRecentlyPosted(dynamic dateOrEpoch, {DateTime? now, int maxDays = 2}) {
  final dt = parseDateTime(dateOrEpoch);
  if (dt == null) return false;
  final current = now ?? DateTime.now();
  final todayStart = DateTime(current.year, current.month, current.day);
  final targetStart = DateTime(dt.year, dt.month, dt.day);
  final diffDays = todayStart.difference(targetStart).inDays;
  return diffDays >= 0 && diffDays <= maxDays;
}

/// Formats a posting date and time for detailed view.
/// Examples:
/// - "Posted on Aug 25, 2026 at 5:05 PM (2 days ago)"
/// - "Posted Today at 5:05 PM"
/// - "Posted Yesterday at 9:30 AM"
String formatPostingDateTime(dynamic dateOrEpoch, {DateTime? now}) {
  final dt = parseDateTime(dateOrEpoch);
  if (dt == null) return 'Posted recently';

  final current = now ?? DateTime.now();
  final todayStart = DateTime(current.year, current.month, current.day);
  final targetStart = DateTime(dt.year, dt.month, dt.day);
  final diffDays = todayStart.difference(targetStart).inDays;

  final hour12 = dt.hour == 0
      ? 12
      : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final amPm = dt.hour >= 12 ? 'PM' : 'AM';
  final minStr = dt.minute.toString().padLeft(2, '0');
  final timeStr = '$hour12:$minStr $amPm';

  if (diffDays <= 0) {
    return 'Posted Today at $timeStr';
  } else if (diffDays == 1) {
    return 'Posted Yesterday at $timeStr';
  } else if (diffDays < 7) {
    final monthName = kShortMonths[dt.month - 1];
    return 'Posted on $monthName ${dt.day}, ${dt.year} at $timeStr ($diffDays days ago)';
  } else {
    final monthName = kShortMonths[dt.month - 1];
    return 'Posted on $monthName ${dt.day}, ${dt.year} at $timeStr';
  }
}
