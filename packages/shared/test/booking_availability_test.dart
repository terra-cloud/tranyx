import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('BookingAvailabilityHelper & BookingDateRange Tests', () {
    // Example: Vehicle rented Sept 10 to Sept 15, 2026
    final sept10 = DateTime(2026, 9, 10, 10, 0);
    final sept15 = DateTime(2026, 9, 15, 10, 0);

    final booking1 = BookingDateRange(
      id: 'req_1',
      startMs: sept10.millisecondsSinceEpoch,
      endMs: sept15.millisecondsSinceEpoch,
      status: 'Approved',
    );

    // Another booking: Sept 20 to Sept 25, 2026 (Multiple bookings AC5)
    final sept20 = DateTime(2026, 9, 20, 10, 0);
    final sept25 = DateTime(2026, 9, 25, 10, 0);
    final booking2 = BookingDateRange(
      id: 'req_2',
      startMs: sept20.millisecondsSinceEpoch,
      endMs: sept25.millisecondsSinceEpoch,
      status: 'Booked',
    );

    final ranges = [booking1, booking2];

    test('AC2 & AC4: Dates before, during, and after existing rental', () {
      // Sept 1 to 9 -> Available
      for (int day = 1; day <= 9; day++) {
        final date = DateTime(2026, 9, day);
        expect(
          BookingAvailabilityHelper.isDateBooked(date, ranges),
          isFalse,
          reason: 'Sept $day should be available',
        );
      }

      // Sept 10 to 15 -> Unavailable
      for (int day = 10; day <= 15; day++) {
        final date = DateTime(2026, 9, day);
        expect(
          BookingAvailabilityHelper.isDateBooked(date, ranges),
          isTrue,
          reason: 'Sept $day should be unavailable',
        );
      }

      // Sept 16 to 19 -> Available (before booking2)
      for (int day = 16; day <= 19; day++) {
        final date = DateTime(2026, 9, day);
        expect(
          BookingAvailabilityHelper.isDateBooked(date, ranges),
          isFalse,
          reason: 'Sept $day should be available',
        );
      }

      // Sept 20 to 25 -> Unavailable (booking2)
      for (int day = 20; day <= 25; day++) {
        final date = DateTime(2026, 9, day);
        expect(
          BookingAvailabilityHelper.isDateBooked(date, ranges),
          isTrue,
          reason: 'Sept $day should be unavailable',
        );
      }

      // Sept 26 onward -> Available
      final sept26 = DateTime(2026, 9, 26);
      expect(BookingAvailabilityHelper.isDateBooked(sept26, ranges), isFalse);
    });

    test('AC3: Prevent overlapping bookings', () {
      // Overlap: Sept 8 to 12 (starts before, ends inside booking1)
      final overlapStart = DateTime(2026, 9, 8).millisecondsSinceEpoch;
      final overlapEnd = DateTime(2026, 9, 12).millisecondsSinceEpoch;
      expect(
        BookingAvailabilityHelper.hasRangeOverlap(overlapStart, overlapEnd, ranges),
        isTrue,
      );

      // Overlap: Sept 12 to 14 (completely inside booking1)
      final insideStart = DateTime(2026, 9, 12).millisecondsSinceEpoch;
      final insideEnd = DateTime(2026, 9, 14).millisecondsSinceEpoch;
      expect(
        BookingAvailabilityHelper.hasRangeOverlap(insideStart, insideEnd, ranges),
        isTrue,
      );

      // Overlap: Sept 8 to 18 (encloses booking1)
      final encloseStart = DateTime(2026, 9, 8).millisecondsSinceEpoch;
      final encloseEnd = DateTime(2026, 9, 18).millisecondsSinceEpoch;
      expect(
        BookingAvailabilityHelper.hasRangeOverlap(encloseStart, encloseEnd, ranges),
        isTrue,
      );

      // Non-overlap: Sept 1 to 9 (strictly before booking1)
      final beforeStart = DateTime(2026, 9, 1).millisecondsSinceEpoch;
      final beforeEnd = DateTime(2026, 9, 9).millisecondsSinceEpoch;
      expect(
        BookingAvailabilityHelper.hasRangeOverlap(beforeStart, beforeEnd, ranges),
        isFalse,
      );

      // Non-overlap: Sept 16 to 19 (between booking1 and booking2)
      final betweenStart = DateTime(2026, 9, 16).millisecondsSinceEpoch;
      final betweenEnd = DateTime(2026, 9, 19).millisecondsSinceEpoch;
      expect(
        BookingAvailabilityHelper.hasRangeOverlap(betweenStart, betweenEnd, ranges),
        isFalse,
      );
    });

    test('Find conflicting dates between requested range and bookings', () {
      // Requesting Sept 14 to 17
      final conflicts = BookingAvailabilityHelper.findConflictingDates(
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 17),
        ranges,
      );

      expect(conflicts.length, equals(2)); // Sept 14 and Sept 15
      expect(conflicts.map((d) => d.day).toList(), equals([14, 15]));
    });

    test('calculateNextAvailableStartDate advances past booked dates', () {
      // If user starts looking from Sept 10 (which is booked until Sept 15)
      final candidate = DateTime(2026, 9, 10, 10, 0);
      final nextAvail = BookingAvailabilityHelper.calculateNextAvailableStartDate(
        candidate,
        ranges,
      );

      expect(nextAvail.day, equals(16));
      expect(nextAvail.month, equals(9));
    });

    test('Selective auto-rejection: only filter overlapping pending requests', () {
      final pendingRequests = [
        {
          'id': 'req_overlap_1',
          'startDate': DateTime(2026, 9, 11).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 9, 14).millisecondsSinceEpoch,
        },
        {
          'id': 'req_non_overlap_future',
          'startDate': DateTime(2026, 9, 16).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 9, 19).millisecondsSinceEpoch,
        },
        {
          'id': 'req_overlap_2',
          'startDate': DateTime(2026, 9, 14).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 9, 18).millisecondsSinceEpoch,
        },
      ];

      final conflicts = BookingAvailabilityHelper.filterConflictingRequests(
        sept10.millisecondsSinceEpoch,
        sept15.millisecondsSinceEpoch,
        pendingRequests,
      );

      final conflictIds = conflicts.map((r) => r['id']).toList();
      expect(conflictIds, contains('req_overlap_1'));
      expect(conflictIds, contains('req_overlap_2'));
      expect(conflictIds, isNot(contains('req_non_overlap_future')));
    });

    test('AC6: Completed or cancelled bookings do not block availability', () {
      final completedBooking = BookingDateRange(
        id: 'past_1',
        startMs: DateTime(2026, 8, 1).millisecondsSinceEpoch,
        endMs: DateTime(2026, 8, 5).millisecondsSinceEpoch,
        status: 'Completed',
      );
      final cancelledBooking = BookingDateRange(
        id: 'cancelled_1',
        startMs: DateTime(2026, 9, 10).millisecondsSinceEpoch,
        endMs: DateTime(2026, 9, 15).millisecondsSinceEpoch,
        status: 'Cancelled',
      );

      expect(completedBooking.isConfirmedBooking, isFalse);
      expect(cancelledBooking.isConfirmedBooking, isFalse);

      final inactiveRanges = [completedBooking, cancelledBooking];
      final date = DateTime(2026, 9, 12);
      expect(BookingAvailabilityHelper.isDateBooked(date, inactiveRanges), isFalse);
    });
  });
}
