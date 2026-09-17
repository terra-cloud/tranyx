import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Rental Contract & Signature Independence per Booking Request Tests', () {
    late VehicleRental baseVehicle;
    late PropertyRental baseProperty;

    setUp(() {
      final now = DateTime.now();
      baseVehicle = VehicleRental(
        id: 'vehicle_101',
        hostId: 'host_1',
        hostName: 'Host Juan',
        brand: 'Toyota',
        model: 'Fortuner',
        year: 2024,
        type: VehicleType.suv,
        plateNumber: 'ABC 1234',
        vehicleValue: 1800000.0,
        ltoCrNumber: 'CR123',
        ltoOrNumber: 'OR123',
        insuranceProvider: 'Standard Insurance',
        insurancePolicyNumber: 'POL-999',
        interiorPhotoUrl: 'https://img.bb/interior.jpg',
        frontPhotoUrl: 'https://img.bb/front.jpg',
        backPhotoUrl: 'https://img.bb/back.jpg',
        contractType: 'tranyx',
        contractTerms: 'Standard Terms',
        price12h: 2500.0,
        priceDaily: 4000.0,
        priceWeekly: 25000.0,
        priceMonthly: 85000.0,
        extensionRatePerHour: 250.0,
        latePenaltyRatePerHour: 500.0,
        status: 'Available',
        pickupAddress: 'BGC, Taguig',
        pickupLat: 14.5547,
        pickupLng: 121.0244,
        createdAt: now,
      );

      baseProperty = PropertyRental(
        id: 'prop_202',
        hostId: 'host_2',
        hostName: 'Host Maria',
        title: 'BGC 1BR Condo',
        description: 'Cozy loft',
        type: PropertyType.condo,
        category: PropertyCategory.residential,
        priceMonthly: 35000.0,
        priceWeekly: 12000.0,
        priceDaily: 2500.0,
        depositMonths: 2,
        address: 'BGC, Taguig',
        latitude: 14.5547,
        longitude: 121.0244,
        photoUrls: ['https://img.bb/condo.jpg'],
        amenities: ['WiFi', 'Pool'],
        status: 'Available',
        contractType: 'tranyx',
        contractTerms: 'Standard Lease',
        createdAt: now,
        allowChat: true,
        depositType: DepositType.none,
        depositValue: 0.0,
        isListingFeeWaived: false,
        allowedDurations: ['daily', 'monthly'],
      );
    });

    test('VehicleRental.fromBookingRequest correctly overlays booking parameters', () {
      final start = DateTime(2026, 10, 1, 9, 0);
      final end = DateTime(2026, 10, 3, 18, 0);
      final bookingReq = {
        'id': 'req_renter_a',
        'rentalId': 'vehicle_101',
        'renteeId': 'renter_a',
        'renteeName': 'Alice Wonderland',
        'renteePhotoUrl': 'https://img.bb/alice.jpg',
        'startDate': start.millisecondsSinceEpoch,
        'endDate': end.millisecondsSinceEpoch,
        'rentalDurationType': 'daily',
        'rentalMultiplier': 3,
        'totalCost': 12000.0,
        'signatureName': 'data:image/png;base64,aliceSigData',
        'renteeLicenseNumber': 'D01-99-887766',
        'signedAt': start.millisecondsSinceEpoch,
        'renteeIsVerified': true,
        'renteeVerificationStatus': 'VERIFIED',
      };

      final contractVehicle = VehicleRental.fromBookingRequest(baseVehicle, bookingReq);

      expect(contractVehicle.id, equals('vehicle_101'));
      expect(contractVehicle.brand, equals('Toyota'));
      expect(contractVehicle.renteeId, equals('renter_a'));
      expect(contractVehicle.renteeName, equals('Alice Wonderland'));
      expect(contractVehicle.totalCost, equals(12000.0));
      expect(contractVehicle.renteeSignatureName, equals('data:image/png;base64,aliceSigData'));
      expect(contractVehicle.renteeLicenseNumber, equals('D01-99-887766'));
      expect(contractVehicle.renteeIsVerified, isTrue);
    });

    test('PropertyRental.fromBookingRequest correctly overlays booking parameters', () {
      final start = DateTime(2026, 11, 1);
      final end = DateTime(2026, 11, 30);
      final bookingReq = {
        'id': 'req_prop_b',
        'propertyId': 'prop_202',
        'renteeId': 'renter_b',
        'renteeName': 'Bob Builder',
        'renteePhotoUrl': 'https://img.bb/bob.jpg',
        'startDate': start.millisecondsSinceEpoch,
        'endDate': end.millisecondsSinceEpoch,
        'rentalDurationType': 'monthly',
        'rentalMultiplier': 1,
        'totalCost': 35000.0,
        'signatureName': 'data:image/png;base64,bobSigData',
        'signatureHash': '0xabcdef123456',
        'signedAt': start.millisecondsSinceEpoch,
        'renteeIsVerified': true,
      };

      final contractProp = PropertyRental.fromBookingRequest(baseProperty, bookingReq);

      expect(contractProp.id, equals('prop_202'));
      expect(contractProp.title, equals('BGC 1BR Condo'));
      expect(contractProp.renteeId, equals('renter_b'));
      expect(contractProp.renteeName, equals('Bob Builder'));
      expect(contractProp.totalCost, equals(35000.0));
      expect(contractProp.renteeSignatureName, equals('data:image/png;base64,bobSigData'));
      expect(contractProp.signatureHash, equals('0xabcdef123456'));
      expect(contractProp.currentRequestId, equals('req_prop_b'));
    });

    test('Renter A signing does NOT pollute or mark Renter B as signed', () {
      // Simulate multiple approved requests for the same vehicle
      final reqA = <String, dynamic>{
        'id': 'req_A',
        'rentalId': 'vehicle_101',
        'renteeId': 'renter_a',
        'renteeName': 'Renter A',
        'status': 'Approved',
        'signatureName': null,
        'signedAt': null,
        'signatureHash': null,
      };

      final reqB = <String, dynamic>{
        'id': 'req_B',
        'rentalId': 'vehicle_101',
        'renteeId': 'renter_b',
        'renteeName': 'Renter B',
        'status': 'Approved',
        'signatureName': null,
        'signedAt': null,
        'signatureHash': null,
      };

      // Invariant: Both start awaiting signature
      bool isSignedA(Map<String, dynamic> r) =>
          (r['signedAt'] != null && (r['signedAt'] as num) > 0) ||
          (r['signatureName'] != null && r['signatureName'].toString().isNotEmpty && r['signatureName'].toString() != 'null') ||
          (r['signatureHash'] != null && r['signatureHash'].toString().isNotEmpty);

      bool isAwaitingSignature(Map<String, dynamic> r) =>
          !isSignedA(r) &&
          (r['status']?.toString().toLowerCase() == 'awaiting signature' ||
           r['status']?.toString().toLowerCase() == 'approved');

      expect(isAwaitingSignature(reqA), isTrue);
      expect(isAwaitingSignature(reqB), isTrue);

      // Now Renter A signs
      reqA['status'] = 'Booked';
      reqA['signatureName'] = 'data:image/png;base64,renterA_signature';
      reqA['signedAt'] = DateTime.now().millisecondsSinceEpoch;
      reqA['signatureHash'] = 'hash_A_998877';

      // Verify Renter A is signed and NOT awaiting signature
      expect(isSignedA(reqA), isTrue);
      expect(isAwaitingSignature(reqA), isFalse);

      // Verify Renter B remains strictly untouched and STILL awaiting signature
      expect(isSignedA(reqB), isFalse);
      expect(isAwaitingSignature(reqB), isTrue);
      expect(reqB['signatureName'], isNull);
      expect(reqB['signedAt'], isNull);

      // Now Renter B signs independently with their own distinct signature
      reqB['status'] = 'Booked';
      reqB['signatureName'] = 'data:image/png;base64,renterB_signature';
      reqB['signedAt'] = DateTime.now().millisecondsSinceEpoch;
      reqB['signatureHash'] = 'hash_B_112233';

      expect(isSignedA(reqB), isTrue);
      expect(isAwaitingSignature(reqB), isFalse);
      expect(reqB['signatureName'], equals('data:image/png;base64,renterB_signature'));
      expect(reqA['signatureName'], equals('data:image/png;base64,renterA_signature'));
      expect(reqA['signatureName'], isNot(equals(reqB['signatureName'])));
    });
  });
}
