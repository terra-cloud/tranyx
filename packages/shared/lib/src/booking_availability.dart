import 'date_utils.dart';

/// Represents a booked or reserved date range for a vehicle or property.
class BookingDateRange {
  final String id;
  final int startMs;
  final int endMs;
  final String status;

  DateTime get startDate => DateTime.fromMillisecondsSinceEpoch(startMs);
  DateTime get endDate => DateTime.fromMillisecondsSinceEpoch(endMs);

  const BookingDateRange({
    required this.id,
    required this.startMs,
    required this.endMs,
    this.status = 'Approved',
  });

  /// Factory to parse from Firestore map (request doc or rental listing doc)
  factory BookingDateRange.fromMap(Map map, [String? docId]) {
    final start = getEpochMs(map['startDate']);
    final end = getEpochMs(map['endDate']);
    final status = map['status']?.toString() ?? 'Approved';
    final id = docId ?? map['id']?.toString() ?? '';
    return BookingDateRange(
      id: id,
      startMs: start,
      endMs: end,
      status: status,
    );
  }

  /// Whether this booking is active and occupies the calendar
  bool get isConfirmedBooking {
    final s = status.toLowerCase().trim();
    return s == 'approved' ||
        s == 'booked' ||
        s == 'active' ||
        s == 'ongoing' ||
        s == 'awaiting signature' ||
        s == 'on the way' ||
        s == 'on the way to rentee' ||
        s == 'returning';
  }
}

/// Helper methods for determining date-based booking availability and preventing overlaps.
class BookingAvailabilityHelper {
  /// Checks whether two time intervals overlap.
  /// Standard formula: startA < endB && endA > startB
  static bool hasOverlap(int startA, int endA, int startB, int endB) {
    if (startA <= 0 || endA <= 0 || startB <= 0 || endB <= 0) return false;
    return startA < endB && endA > startB;
  }

  /// Checks if a date is in the past (before today's midnight)
  static bool isDateInPast(DateTime date, [DateTime? referenceNow]) {
    final now = referenceNow ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.isBefore(today);
  }

  /// Checks if a specific day is booked by any active booking range
  static bool isDateBooked(DateTime date, Iterable<BookingDateRange> ranges) {
    final startOfDayMs = DateTime(date.year, date.month, date.day, 0, 0, 0).millisecondsSinceEpoch;
    final endOfDayMs = DateTime(date.year, date.month, date.day, 23, 59, 59, 999).millisecondsSinceEpoch;

    for (final r in ranges) {
      if (!r.isConfirmedBooking) continue;
      if (endOfDayMs >= r.startMs && startOfDayMs <= r.endMs) {
        return true;
      }
    }
    return false;
  }

  /// Checks if the proposed time interval [startMs, endMs] overlaps with any active booking range.
  static bool hasRangeOverlap(int startMs, int endMs, Iterable<BookingDateRange> ranges) {
    for (final r in ranges) {
      if (!r.isConfirmedBooking) continue;
      if (hasOverlap(startMs, endMs, r.startMs, r.endMs)) {
        return true;
      }
    }
    return false;
  }

  /// Returns all day-level [DateTime] instances in [startDate, endDate] that conflict with active bookings.
  static List<DateTime> findConflictingDates(
    DateTime startDate,
    DateTime endDate,
    Iterable<BookingDateRange> ranges,
  ) {
    final conflicts = <DateTime>[];
    DateTime curr = DateTime(startDate.year, startDate.month, startDate.day);
    final endDay = DateTime(endDate.year, endDate.month, endDate.day);

    while (!curr.isAfter(endDay)) {
      if (isDateBooked(curr, ranges)) {
        conflicts.add(curr);
      }
      curr = curr.add(const Duration(days: 1));
    }
    return conflicts;
  }

  /// Calculates the next available date starting from [from] where no booking exists.
  static DateTime calculateNextAvailableStartDate(
    DateTime from,
    Iterable<BookingDateRange> ranges,
  ) {
    DateTime candidate = DateTime(from.year, from.month, from.day, from.hour, from.minute);
    if (isDateInPast(candidate)) {
      final now = DateTime.now();
      candidate = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
      if (candidate.hour == 0) {
        candidate = DateTime(now.year, now.month, now.day + 1, 9, 0);
      }
    }

    // Advance day by day until a day without active booking is found
    int maxDaysToCheck = 730; // 2 years limit to prevent infinite loops
    while (maxDaysToCheck > 0) {
      if (!isDateBooked(candidate, ranges)) {
        return candidate;
      }
      candidate = DateTime(candidate.year, candidate.month, candidate.day + 1, candidate.hour, candidate.minute);
      maxDaysToCheck--;
    }
    return candidate;
  }

  /// Returns only the requests from [requests] whose date ranges overlap with [approvedStart, approvedEnd].
  /// Used when host approves a booking, so only overlapping pending requests are rejected.
  static List<Map<String, dynamic>> filterConflictingRequests(
    int approvedStart,
    int approvedEnd,
    Iterable<Map<String, dynamic>> requests, {
    String? currentRequestId,
  }) {
    final conflicts = <Map<String, dynamic>>[];
    for (final req in requests) {
      final id = req['id']?.toString();
      if (currentRequestId != null && id == currentRequestId) continue;

      final reqStart = getEpochMs(req['startDate']);
      final reqEnd = getEpochMs(req['endDate']);
      if (hasOverlap(approvedStart, approvedEnd, reqStart, reqEnd)) {
        conflicts.add(req);
      }
    }
    return conflicts;
  }
}
