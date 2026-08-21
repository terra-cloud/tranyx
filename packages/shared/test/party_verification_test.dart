import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('PartyVerificationHelper Contract Verification Tests', () {
    test('Scenario 1: Unverified user correctly identified and labeled', () {
      final isVerified = PartyVerificationHelper.isPartyVerified(
        isVerified: false,
        status: 'UNVERIFIED',
        level: 0,
        idVerified: false,
      );
      expect(isVerified, isFalse);

      final label = PartyVerificationHelper.formatIdentityStatusLabel(
        isVerified: false,
        status: 'UNVERIFIED',
        level: 0,
        idVerified: false,
      );
      expect(label, equals('Identity Status: Unverified Account'));
      expect(label.contains('Verified ('), isFalse);
    });

    test('Scenario 1: Fallback evaluation when values are null or falsy', () {
      final isVerified = PartyVerificationHelper.isPartyVerified(
        isVerified: null,
        status: null,
        level: null,
        idVerified: null,
      );
      expect(isVerified, isFalse);

      final label = PartyVerificationHelper.formatIdentityStatusLabel(
        isVerified: null,
        status: null,
        level: null,
        idVerified: null,
      );
      expect(label, equals('Identity Status: Unverified Account'));
    });

    test('Scenario 2: Verified User with Government ID (KYC completed)', () {
      final isVerified = PartyVerificationHelper.isPartyVerified(
        isVerified: true,
        status: 'VERIFIED',
        level: 2,
        idVerified: true,
      );
      expect(isVerified, isTrue);

      final tier = PartyVerificationHelper.formatVerificationTier(
        isVerified: true,
        status: 'VERIFIED',
        level: 2,
        idVerified: true,
      );
      expect(tier, equals('Government ID Verified'));

      final label = PartyVerificationHelper.formatIdentityStatusLabel(
        isVerified: true,
        status: 'VERIFIED',
        level: 2,
        idVerified: true,
      );
      expect(label, equals('Identity Status: Verified (Government ID Verified)'));
    });

    test('Scenario 3: Tiered Verification (Level 3 Pro, Basic, Custom)', () {
      final labelLevel3 = PartyVerificationHelper.formatIdentityStatusLabel(
        level: 3,
      );
      expect(labelLevel3, equals('Identity Status: Verified (Level 3 Pro Verified)'));

      final labelExplicit = PartyVerificationHelper.formatIdentityStatusLabel(
        isVerified: true,
        explicitTier: 'Enterprise Verified',
      );
      expect(labelExplicit, equals('Identity Status: Verified (Enterprise Verified)'));
    });

    test('Scenario 4: Immutable serialization snapshot for VehicleRental and PropertyRental', () {
      final vehicle = VehicleRental(
        id: 'v123',
        hostId: 'host_01',
        hostName: 'Carlos Host',
        hostIsVerified: true,
        hostVerificationStatus: 'VERIFIED',
        hostVerificationTier: 'Government ID Verified',
        renteeId: 'renter_01',
        renteeName: 'Maria Lessee',
        renteeIsVerified: false,
        renteeVerificationStatus: 'UNVERIFIED',
        renteeVerificationTier: 'None',
        brand: 'Toyota',
        model: 'HiAce',
        year: 2024,
        type: VehicleType.van,
        plateNumber: 'ABC 1234',
        vehicleValue: 1500000.0,
        ltoCrNumber: 'CR123',
        ltoOrNumber: 'OR123',
        insuranceProvider: 'Standard Insurance',
        insurancePolicyNumber: 'POL999',
        interiorPhotoUrl: '',
        frontPhotoUrl: '',
        backPhotoUrl: '',
        contractType: 'tranyx',
        contractTerms: '',
        price12h: 0.0,
        priceDaily: 3500.0,
        priceWeekly: 21000.0,
        priceMonthly: 80000.0,
        extensionRatePerHour: 200.0,
        latePenaltyRatePerHour: 400.0,
        status: 'Available',
        pickupAddress: 'Naic, Cavite',
        pickupLat: 14.3,
        pickupLng: 120.7,
        createdAt: DateTime.now(),
      );

      final map = vehicle.toMap();
      expect(map['hostIsVerified'], isTrue);
      expect(map['hostVerificationStatus'], equals('VERIFIED'));
      expect(map['hostVerificationTier'], equals('Government ID Verified'));
      expect(map['renteeIsVerified'], isFalse);
      expect(map['renteeVerificationStatus'], equals('UNVERIFIED'));

      final restored = VehicleRental.fromMap(map, 'v123');
      expect(restored.hostIsVerified, isTrue);
      expect(restored.hostVerificationStatus, equals('VERIFIED'));
      expect(restored.hostVerificationTier, equals('Government ID Verified'));
      expect(restored.renteeIsVerified, isFalse);
      expect(restored.renteeVerificationStatus, equals('UNVERIFIED'));
    });
  });
}
