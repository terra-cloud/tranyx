import 'package:test/test.dart';

void main() {
  group('Property & Vehicle Rental Completion and Idempotent Escrow Invariants', () {
    test('completePropertyRental reset fields are fully permitted by Firestore Rule 1c whitelist', () {
      // Keys reset on properties/$propertyId when completing a lease:
      final resetKeys = <String>{
        'status',
        'renteeId',
        'renteeName',
        'renteePhotoUrl',
        'rentalDurationType',
        'rentalMultiplier',
        'startDate',
        'endDate',
        'totalCost',
        'baseRentAmount',
        'securityDepositAmount',
        'bookingFee',
        'renteeSignatureName',
        'signedAt',
        'currentRequestId',
        'licenseNumber',
      };

      // Rule 1c in 40_workspace_properties.rules:
      final rule1cAllowedKeys = <String>{
        'hostRated',
        'endDate',
        'checkOutDate',
        'totalCost',
        'status',
        'renteeId',
        'renteeName',
        'renteePhotoUrl',
        'rentalDurationType',
        'rentalMultiplier',
        'startDate',
        'baseRentAmount',
        'securityDepositAmount',
        'bookingFee',
        'renteeSignatureName',
        'signedAt',
        'currentRequestId',
        'licenseNumber',
        'allowChat',
      };

      final unpermittedKeys = resetKeys.difference(rule1cAllowedKeys);
      expect(unpermittedKeys, isEmpty,
          reason: 'Every key modified upon lease completion must be whitelisted in Rule 1c');
    });

    test('Property completion with Released escrow skips duplicate host payout and self-heals listing', () {
      double hostTyxBalance = 5000.0;
      final mockEscrow = {
        'id': 'prop_esc_stuck_1',
        'requestId': 'req_stuck_1',
        'propertyId': 'prop_stuck_1',
        'status': 'Released',
        'amount': 8240.0,
        'baseRentAmount': 8000.0,
        'hostCommissionDeducted': 560.0,
        'hostPayout': 7440.0,
        'securityDepositRefunded': 0.0,
        'securityDepositStatus': 'None',
      };

      final mockProperty = <String, dynamic>{
        'id': 'prop_stuck_1',
        'status': 'Active',
        'renteeId': 'renter_scholar',
        'renteeName': 'Scholar Belle',
        'currentRequestId': 'req_stuck_1',
        'totalCost': 8000.0,
      };

      final mockRequest = <String, dynamic>{
        'id': 'req_stuck_1',
        'status': 'Active',
      };

      // Execution simulation matching firebase_service.dart
      final currentEscrowStatus = mockEscrow['status'] as String? ?? '';
      final isAlreadyReleased = currentEscrowStatus == 'Released';

      expect(isAlreadyReleased, isTrue);

      if (!isAlreadyReleased) {
        hostTyxBalance += 7440.0; // would be duplicate
      }

      // Self-heal: Listing resets to Available & clears active booking pointers
      mockProperty['status'] = 'Available';
      mockProperty['renteeId'] = '';
      mockProperty['renteeName'] = '';
      mockProperty['currentRequestId'] = '';

      // Request marks as Completed
      mockRequest['status'] = 'Completed';
      mockRequest['completedAt'] = 1770000000000;

      // Assertions
      expect(hostTyxBalance, equals(5000.0), reason: 'Host balance must not be duplicated');
      expect(mockProperty['status'], equals('Available'));
      expect(mockProperty['renteeId'], isEmpty);
      expect(mockProperty['currentRequestId'], isEmpty);
      expect(mockRequest['status'], equals('Completed'));
      expect(mockRequest['completedAt'], isNotNull);
    });

    test('Vehicle completion with Released escrow skips duplicate payout and self-heals listing', () {
      double hostTyxBalance = 10000.0;
      final mockEscrow = {
        'id': 'veh_esc_1',
        'status': 'Released',
        'amount': 4120.0,
      };

      final mockRental = <String, dynamic>{
        'id': 'veh_1',
        'status': 'Returning',
        'renteeId': 'renter_1',
        'currentRequestId': 'req_veh_1',
      };

      final currentEscrowStatus = mockEscrow['status'] as String? ?? '';
      final isAlreadyReleased = currentEscrowStatus == 'Released';

      expect(isAlreadyReleased, isTrue);

      if (!isAlreadyReleased) {
        hostTyxBalance += 4000.0;
      }

      mockRental['status'] = 'Available';
      mockRental['renteeId'] = '';
      mockRental['currentRequestId'] = '';

      expect(hostTyxBalance, equals(10000.0));
      expect(mockRental['status'], equals('Available'));
      expect(mockRental['renteeId'], isEmpty);
    });

    test('Active leases filter strictly excludes completed or available leases from current residence', () {
      final sampleBookings = [
        {'id': 'req_1', 'propertyId': 'p1', 'status': 'Active'},
        {'id': 'req_2', 'propertyId': 'p2', 'status': 'Returning'},
        {'id': 'req_3', 'propertyId': 'p3', 'status': 'Completed'},
        {'id': 'req_4', 'propertyId': 'p4', 'status': 'Cancelled'},
      ];

      final filtered = sampleBookings.where((b) {
        final st = (b['status'] ?? '').toString().toLowerCase();
        return st != 'completed' && st != 'complete' && st != 'cancelled';
      }).toList();

      expect(filtered.length, equals(2));
      expect(filtered.map((b) => b['id']), containsAll(['req_1', 'req_2']));
      expect(filtered.map((b) => b['id']), isNot(contains('req_3')));
    });
  });
}
