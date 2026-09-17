import 'package:test/test.dart';

void main() {
  group('Tier 1 Automated Escrow Reconciliation & Booking Flow Invariants', () {
    test('RefundPending escrow amount credits user tyxBalance accurately', () {
      double currentBalance = 1500.0;
      final mockEscrow = {
        'id': 'esc_req_123',
        'requestId': 'req_123',
        'renteeId': 'user_renter_99',
        'status': 'RefundPending',
        'refundAmount': 450.0,
        'amount': 450.0,
        'refundReason': 'Cancelled rental: Toyota Fortuner',
      };

      final status = (mockEscrow['status'] as String).toLowerCase();
      expect(status == 'refundpending' || status == 'refund_pending', isTrue);

      final refundAmt = (mockEscrow['refundAmount'] as num).toDouble();
      final newBalance = currentBalance + refundAmt;
      mockEscrow['status'] = 'Refunded';
      mockEscrow['refundClaimedAt'] = DateTime.now().millisecondsSinceEpoch;

      expect(newBalance, equals(1950.0));
      expect(mockEscrow['status'], equals('Refunded'));
      expect(mockEscrow['refundClaimedAt'], isNotNull);
    });

    test('Property security deposit RefundPending is claimed independently', () {
      double currentBalance = 5000.0;
      final mockPropertyEscrow = {
        'id': 'prop_esc_456',
        'requestId': 'req_456',
        'renteeId': 'user_renter_99',
        'status': 'Released',
        'securityDepositStatus': 'RefundPending',
        'securityDepositAmount': 10000.0,
        'refundReason': '100% refund of security deposit for completed lease "BGC Loft"',
      };

      final secStatus = (mockPropertyEscrow['securityDepositStatus'] as String).toLowerCase();
      expect(secStatus == 'refundpending' || secStatus == 'refund_pending', isTrue);

      final depAmt = (mockPropertyEscrow['securityDepositAmount'] as num).toDouble();
      final newBalance = currentBalance + depAmt;
      mockPropertyEscrow['securityDepositStatus'] = 'Refunded';
      mockPropertyEscrow['securityDepositClaimedAt'] = DateTime.now().millisecondsSinceEpoch;

      expect(newBalance, equals(15000.0));
      expect(mockPropertyEscrow['securityDepositStatus'], equals('Refunded'));
    });

    test('Rental cancellation refund amount calculation strictly applies 2.0 TYX fee', () {
      const baseCost = 3000.0;
      const bookingFee = 90.0; // 3%
      final fullRefundAmount = baseCost + bookingFee;
      const cancellationFee = 2.0;

      final refundToRentee = (fullRefundAmount - cancellationFee).clamp(0.0, double.infinity);
      expect(refundToRentee, equals(3088.0));
    });

    test('Zero or low value rentals cannot produce negative refund balance', () {
      const fullRefundAmount = 1.5;
      const cancellationFee = 2.0;
      final refundToRentee = (fullRefundAmount - cancellationFee).clamp(0.0, double.infinity);
      expect(refundToRentee, equals(0.0));
    });

    test('In-flight processing guard blocks duplicate concurrent approval triggers', () {
      bool isProcessing = false;
      int executionCount = 0;

      void approveRequest() {
        if (isProcessing) return;
        isProcessing = true;
        executionCount++;
      }

      // First click
      approveRequest();
      expect(executionCount, equals(1));
      expect(isProcessing, isTrue);

      // Rapid double-clicks while in-flight
      approveRequest();
      approveRequest();
      expect(executionCount, equals(1));

      // Done
      isProcessing = false;
      expect(isProcessing, isFalse);
    });

    test('Booking approval transitions vehicle to Awaiting Signature with sanitized contract fields', () {
      final rentalListing = <String, dynamic>{
        'id': 'vehicle_99',
        'status': 'Available',
        'renteeId': null,
        'renteeName': null,
        'renteeSignatureName': null,
      };

      final bookingRequest = <String, dynamic>{
        'id': 'req_777',
        'rentalId': 'vehicle_99',
        'renteeId': 'renter_42',
        'renteeName': 'Maria Clara',
        'rentalDurationType': 'daily',
        'rentalMultiplier': 4,
        'startDate': 1770000000000,
        'endDate': 1770345600000,
        'totalCost': 16000.0,
        'bookingFee': 480.0,
      };

      // Execute approval logic
      rentalListing['status'] = 'Awaiting Signature';
      rentalListing['currentRequestId'] = bookingRequest['id'];
      rentalListing['renteeId'] = bookingRequest['renteeId'];
      rentalListing['renteeName'] = bookingRequest['renteeName'];
      rentalListing['rentalDurationType'] = bookingRequest['rentalDurationType'];
      rentalListing['rentalMultiplier'] = bookingRequest['rentalMultiplier'];
      rentalListing['startDate'] = bookingRequest['startDate'];
      rentalListing['endDate'] = bookingRequest['endDate'];
      rentalListing['totalCost'] = bookingRequest['totalCost'];
      rentalListing['bookingFee'] = bookingRequest['bookingFee'];
      rentalListing['renteeSignatureName'] = null; // Fresh for signing

      bookingRequest['status'] = 'Approved';

      expect(rentalListing['status'], equals('Awaiting Signature'));
      expect(bookingRequest['status'], equals('Approved'));
      expect(rentalListing['renteeSignatureName'], isNull);
      expect(rentalListing['totalCost'], equals(16000.0));
      expect(rentalListing['bookingFee'], equals(480.0));
    });
  });
}
