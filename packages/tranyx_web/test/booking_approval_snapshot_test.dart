import 'package:test/test.dart';
import 'package:tranyx_web/services/booking_approval_snapshot.dart';

void main() {
  test('approve still reads a request that omitted duration and multiplier', () {
    final snap = BookingApprovalSnapshot.fromRequest({
      'renteeId': 'renter-1',
      'renteeName': null,
      'durationType': null,
      'multiplier': null,
      'status': 'Pending',
    });
    expect(snap.renteeId, 'renter-1');
    expect(snap.renteeName, 'Renter');
    expect(snap.durationType, 'daily');
    expect(snap.multiplier, 1);
  });

  test('approve keeps duration and multiplier when the request has them', () {
    final snap = BookingApprovalSnapshot.fromRequest({
      'renterId': 'renter-2',
      'renterName': 'Ana',
      'rentalDurationType': 'weekly',
      'rentalMultiplier': 2,
    });
    expect(snap.renteeId, 'renter-2');
    expect(snap.renteeName, 'Ana');
    expect(snap.durationType, 'weekly');
    expect(snap.multiplier, 2);
  });
}
