import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('resolveRentalNavRole', () {
    const hostId = 'host_123';
    const renteeId = 'rentee_456';
    const strangerId = 'stranger_789';

    group('Delivery phase ("On the way to Rentee")', () {
      test('when rentalType is deliver: Host is publisher, Rentee is subscriber', () {
        expect(
          resolveRentalNavRole(
            currentUserId: hostId,
            hostId: hostId,
            renteeId: renteeId,
            status: 'On the way to Rentee',
            rentalType: 'deliver',
          ),
          equals(RentalNavRole.publisher),
        );

        expect(
          resolveRentalNavRole(
            currentUserId: renteeId,
            hostId: hostId,
            renteeId: renteeId,
            status: 'On the way to Rentee',
            rentalType: 'deliver',
          ),
          equals(RentalNavRole.subscriber),
        );

        expect(
          resolveRentalNavRole(
            currentUserId: strangerId,
            hostId: hostId,
            renteeId: renteeId,
            status: 'On the way to Rentee',
            rentalType: 'deliver',
          ),
          equals(RentalNavRole.none),
        );
      });

      test('when rentalType is pickup: Neither Host nor Rentee is publisher/subscriber', () {
        expect(
          resolveRentalNavRole(
            currentUserId: hostId,
            hostId: hostId,
            renteeId: renteeId,
            status: 'On the way to Rentee',
            rentalType: 'pickup',
          ),
          equals(RentalNavRole.none),
        );

        expect(
          resolveRentalNavRole(
            currentUserId: renteeId,
            hostId: hostId,
            renteeId: renteeId,
            status: 'On the way to Rentee',
            rentalType: 'pickup',
          ),
          equals(RentalNavRole.none),
        );
      });
    });

    group('Return phase ("Returning")', () {
      test('Rentee is publisher, Host is subscriber regardless of rentalType', () {
        for (final st in ['Returning', 'returning', 'return', 'Arrived at Return Location', 'arrived at return location']) {
          expect(
            resolveRentalNavRole(
              currentUserId: renteeId,
              hostId: hostId,
              renteeId: renteeId,
              status: st,
              rentalType: 'deliver',
            ),
            equals(RentalNavRole.publisher),
          );

          expect(
            resolveRentalNavRole(
              currentUserId: hostId,
              hostId: hostId,
              renteeId: renteeId,
              status: st,
              rentalType: 'deliver',
            ),
            equals(RentalNavRole.subscriber),
          );

          expect(
            resolveRentalNavRole(
              currentUserId: renteeId,
              hostId: hostId,
              renteeId: renteeId,
              status: st,
              rentalType: 'pickup',
            ),
            equals(RentalNavRole.publisher),
          );

          expect(
            resolveRentalNavRole(
              currentUserId: hostId,
              hostId: hostId,
              renteeId: renteeId,
              status: st,
              rentalType: 'pickup',
            ),
            equals(RentalNavRole.subscriber),
          );
        }
      });
    });

    group('Other statuses', () {
      test('Active, Completed, Cancelled return none', () {
        for (final st in ['Active', 'Completed', 'Cancelled', 'Approved', 'Pending']) {
          expect(
            resolveRentalNavRole(
              currentUserId: hostId,
              hostId: hostId,
              renteeId: renteeId,
              status: st,
              rentalType: 'deliver',
            ),
            equals(RentalNavRole.none),
          );
          expect(
            resolveRentalNavRole(
              currentUserId: renteeId,
              hostId: hostId,
              renteeId: renteeId,
              status: st,
              rentalType: 'deliver',
            ),
            equals(RentalNavRole.none),
          );
        }
      });
    });
  });
}
