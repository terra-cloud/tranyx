import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'helpers/fake_firestore.dart';

void main() {
  group('TransitRepository Collection & Flow Integration Tests', () {
    late FakeFirebaseFirestore firestore;
    late TransitRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = TransitRepository(firestore);
    });

    test('Verify user balance retrieval and update collections', () async {
      firestore.db['users/user123'] = {
        'name': 'Test Host',
        'email': 'host@tranyx.com',
        'accountType': 'nyxian',
        'tyxBalance': 1000.0,
      };

      final profile = await repo.getUser('user123');
      expect(profile, isNotNull);
      expect(profile!.name, equals('Test Host'));
      expect(profile.tyxBalance, equals(1000.0));

      await repo.updateTyxBalance('user123', 850.0);
      final updatedProfile = await repo.getUser('user123');
      expect(updatedProfile!.tyxBalance, equals(850.0));

      expect(firestore.collectionQueries, contains('users'));
    });

    test('Verify vehicle rental creation & collection references', () async {
      firestore.db['users/host123'] = {
        'name': 'Vehicle Host',
        'email': 'host@tranyx.com',
        'accountType': 'nyxian',
        'tyxBalance': 500.0,
      };
      firestore.db['settings/platform_fees'] = {
        'listingFeeRate': 0.015,
      };

      final rental = VehicleRental(
        id: '',
        hostId: 'host123',
        hostName: 'Vehicle Host',
        brand: 'Honda',
        model: 'Civic',
        year: 2022,
        type: VehicleType.car,
        plateNumber: 'ABC 123',
        vehicleValue: 1000000.0,
        ltoCrNumber: 'CR123',
        ltoOrNumber: 'OR123',
        insuranceProvider: 'Standard Insurance',
        insurancePolicyNumber: 'POL123',
        interiorPhotoUrl: 'interior.jpg',
        frontPhotoUrl: 'front.jpg',
        backPhotoUrl: 'back.jpg',
        contractType: 'tranyx',
        contractTerms: 'Standard Terms',
        price12h: 1500.0,
        priceDaily: 2500.0,
        priceWeekly: 15000.0,
        priceMonthly: 50000.0,
        extensionRatePerHour: 200.0,
        latePenaltyRatePerHour: 500.0,
        status: 'Available',
        pickupAddress: 'Manila',
        pickupLat: 14.5995,
        pickupLng: 120.9842,
        createdAt: DateTime.now(),
      );

      final rentalId = await repo.createRental(rental);
      expect(rentalId, isNotEmpty);

      // Verify listing fee of 1.5% is deducted: 2500 * 0.015 = 37.5
      final host = await repo.getUser('host123');
      expect(host!.tyxBalance, equals(500.0 - 37.5));

      // Assert that collections accessed align with target names
      expect(firestore.collectionQueries, contains('users'));
      expect(firestore.collectionQueries, contains('transactions'));
      expect(firestore.collectionQueries, contains('rentals'));
    });

    test(
      'Verify booking request flow updates all target collections',
      () async {
        // 1. Setup host and renter profiles
        firestore.db['users/host123'] = {
          'name': 'Host User',
          'email': 'host@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 1000.0,
        };
        firestore.db['users/renter123'] = {
          'name': 'Renter User',
          'email': 'renter@tranyx.com',
          'accountType': 'employer',
          'tyxBalance': 5000.0,
        };

        // 2. Setup rental listing
        firestore.db['rentals/rental123'] = {
          'id': 'rental123',
          'hostId': 'host123',
          'hostName': 'Host User',
          'priceDaily': 2000.0,
          'brand': 'Toyota',
          'model': 'Vios',
          'year': 2021,
          'status': 'Available',
        };

        // 3. Create booking request (Convenience fee = 3% of cost)
        // Total cost = 2000.0, bookingFee = 60.0, totalRequired = 2060.0
        await repo.createBookingRequest(
          rentalId: 'rental123',
          renteeId: 'renter123',
          renteeName: 'Renter User',
          renteePhotoUrl: null,
          durationType: 'daily',
          multiplier: 1,
          licenseNumber: 'DL12345',
          totalCost: 2000.0,
          hireWithDriver: false,
          rentalType: 'pickup',
          deliveryAddress: null,
          startDate: DateTime.now().millisecondsSinceEpoch,
          endDate: DateTime.now()
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
        );

        // Assert renter wallet is debited by 2060.0
        final renter = await repo.getUser('renter123');
        expect(renter!.tyxBalance, equals(5000.0 - 2060.0));

        // Assert all collections used for booking are exactly as expected
        expect(firestore.collectionQueries, contains('rentals'));
        expect(firestore.collectionQueries, contains('users'));
        expect(firestore.collectionQueries, contains('transactions'));
        expect(firestore.collectionQueries, contains('rental_requests'));
        expect(firestore.collectionQueries, contains('rental_escrows'));
        expect(firestore.collectionQueries, contains('notifications'));

        // Check request status and escrow exist in DB
        final reqDocs = await firestore.collection('rental_requests').get();
        expect(reqDocs.docs.length, equals(1));
        expect(reqDocs.docs.first.data()['status'], equals('Pending'));
        expect(reqDocs.docs.first.data()['totalCost'], equals(2000.0));

        final escrowDocs = await firestore.collection('rental_escrows').get();
        expect(escrowDocs.docs.length, equals(1));
        expect(escrowDocs.docs.first.data()['amount'], equals(2000.0));
        expect(escrowDocs.docs.first.data()['status'], equals('Held'));
      },
    );

    test(
      'Verify approval, contract signature, and completion of vehicle rental',
      () async {
        // 1. Initial State Setup
        firestore.db['users/host123'] = {
          'name': 'Host User',
          'email': 'host@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 1000.0,
        };
        firestore.db['rentals/rental123'] = {
          'id': 'rental123',
          'hostId': 'host123',
          'hostName': 'Host User',
          'priceDaily': 2000.0,
          'brand': 'Toyota',
          'model': 'Vios',
          'year': 2021,
          'status': 'Available',
        };
        firestore.db['rental_requests/req123'] = {
          'id': 'req123',
          'rentalId': 'rental123',
          'renteeId': 'renter123',
          'renteeName': 'Renter User',
          'durationType': 'daily',
          'multiplier': 1,
          'totalCost': 2000.0,
          'bookingFee': 60.0,
          'status': 'Pending',
        };
        firestore.db['rental_escrows/req123'] = {
          'requestId': 'req123',
          'rentalId': 'rental123',
          'renteeId': 'renter123',
          'hostId': 'host123',
          'amount': 2000.0,
          'status': 'Held',
        };

        // 2. Approve Request
        await repo.approveBookingRequest('req123', 'rental123', true);

        // Verify request status is updated and escrow shifted to vehicle ID
        final reqDoc = await firestore
            .collection('rental_requests')
            .doc('req123')
            .get();
        expect(reqDoc.data()!['status'], equals('Approved'));

        final escrowDoc = await firestore
            .collection('rental_escrows')
            .doc('rental123')
            .get();
        expect(escrowDoc.exists, isTrue);
        expect(escrowDoc.data()!['amount'], equals(2000.0));

        final canonicalReqEscrow = await firestore
            .collection('rental_escrows')
            .doc('req123')
            .get();
        expect(canonicalReqEscrow.exists, isTrue);
        expect(canonicalReqEscrow.data()!['amount'], equals(2000.0));

        final rentalDocAfterApproval = await firestore
            .collection('rentals')
            .doc('rental123')
            .get();
        expect(
          rentalDocAfterApproval.data()!['status'],
          equals('Awaiting Signature'),
        );

        // 3. Sign Contract
        await repo.signVehicleContract('rental123', 'signature_data_url');
        final rentalDocAfterSigning = await firestore
            .collection('rentals')
            .doc('rental123')
            .get();
        expect(rentalDocAfterSigning.data()!['status'], equals('Booked'));

        // 4. Complete Rental & release escrow (3% platform commission deducted)
        // hostPayout = 2000 - (2000 * 0.03) = 1940.0
        await repo.completeRental('rental123');

        // Verify host received payout
        final host = await repo.getUser('host123');
        expect(host!.tyxBalance, equals(1000.0 + 1940.0));

        // Verify escrow is marked Released
        final escrowDocCompleted = await firestore
            .collection('rental_escrows')
            .doc('rental123')
            .get();
        expect(escrowDocCompleted.data()!['status'], equals('Released'));

        // Verify rental_history document is created
        final historyDocs = await firestore.collection('rental_history').get();
        expect(historyDocs.docs.length, equals(1));
        expect(historyDocs.docs.first.data()['status'], equals('Completed'));

        // Verify rental status goes back to Available
        final finalRentalDoc = await firestore
            .collection('rentals')
            .doc('rental123')
            .get();
        expect(finalRentalDoc.data()!['status'], equals('Available'));
      },
    );

    test(
      'Verify property rental creation, booking & completion collections',
      () async {
        firestore.db['users/host123'] = {
          'name': 'Property Host',
          'email': 'host@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 1000.0,
        };
        firestore.db['users/renter123'] = {
          'name': 'Renter User',
          'email': 'renter@tranyx.com',
          'accountType': 'employer',
          'tyxBalance': 20000.0,
        };

        final property = PropertyRental(
          id: '',
          hostId: 'host123',
          hostName: 'Property Host',
          title: 'Modern Condo',
          description: 'Cozy condo in center',
          type: PropertyType.condo,
          category: PropertyCategory.residential,
          priceMonthly: 10000.0,
          priceWeekly: 3000.0,
          priceDaily: 500.0,
          depositMonths: 1,
          address: 'Condo Street 12',
          latitude: 14.5995,
          longitude: 120.9842,
          photoUrls: ['condo.jpg'],
          amenities: ['wifi'],
          status: 'Available',
          contractType: 'tranyx',
          contractTerms: 'Standard Property Terms',
          createdAt: DateTime.now(),
        );

        // 1. Create Property Listing (0% Free Listing: ₱0.00 upfront fee)
        final propertyId = await repo.createPropertyRental(property);
        expect(propertyId, isNotEmpty);

        final hostAfterListing = await repo.getUser('host123');
        expect(hostAfterListing!.tyxBalance, equals(1000.0)); // 0% listing fee

        expect(firestore.collectionQueries, contains('properties'));

        // 2. Request Booking (totalCost = 10000.0, customer booking fee = 3% = 300.0, total required = 10300.0)
        await repo.createPropertyBookingRequest(
          propertyId: propertyId,
          renteeId: 'renter123',
          renteeName: 'Renter User',
          renteePhotoUrl: null,
          durationType: 'monthly',
          multiplier: 1,
          totalCost: 10000.0,
          contractType: 'tranyx',
          contractTerms: 'Standard Property Terms',
          startDate: DateTime.now().millisecondsSinceEpoch,
          endDate: DateTime.now()
              .add(const Duration(days: 30))
              .millisecondsSinceEpoch,
        );

        final renter = await repo.getUser('renter123');
        expect(renter!.tyxBalance, equals(20000.0 - 10300.0));

        expect(firestore.collectionQueries, contains('property_requests'));
        expect(firestore.collectionQueries, contains('property_escrows'));

        // 3. Setup approval mock state and run completePropertyRental
        firestore.db['properties/$propertyId'] = {
          'id': propertyId,
          'hostId': 'host123',
          'hostName': 'Property Host',
          'title': 'Modern Condo',
          'status': 'Booked',
          'totalCost': 10000.0,
          'baseRentAmount': 10000.0,
          'renteeId': 'renter123',
        };
        firestore.db['property_escrows/$propertyId'] = {
          'propertyId': propertyId,
          'renteeId': 'renter123',
          'hostId': 'host123',
          'amount': 10300.0,
          'baseRentAmount': 10000.0,
          'hostCommissionRate': 0.07,
          'status': 'Held',
        };

        // 4. Complete Property lease (7% host commission of 10000 = 700, net payout = 9300)
        await repo.completePropertyRental(propertyId);

        // Verify host wallet has payout (1000 initial + 9300 net earnings)
        final hostFinal = await repo.getUser('host123');
        expect(hostFinal!.tyxBalance, equals(1000.0 + 9300.0));

        // Verify property_history doc created
        final histDocs = await firestore.collection('property_history').get();
        expect(histDocs.docs.length, equals(1));
        expect(histDocs.docs.first.data()['status'], equals('Completed'));

        expect(firestore.collectionQueries, contains('property_history'));
      },
    );

    test(
      'Verify submission of ratings writes to correct collections',
      () async {
        firestore.db['users/targetUser'] = {
          'name': 'Rated User',
          'hostRating': 5.0,
          'hostRatingCount': 1,
          'renterRating': 4.0,
          'renterRatingCount': 1,
        };

        // Case 1: Rating is for a vehicle rental in rental_history
        firestore.db['rental_history/rh123'] = {'id': 'rh123'};
        await repo.submitRentalRating(
          rentalId: 'rh123',
          callerUid: 'caller123',
          targetUid: 'targetUser',
          stars: 3.0,
          role: 'host',
        );
        final histDoc = await firestore
            .collection('rental_history')
            .doc('rh123')
            .get();
        expect(histDoc.data()!['hostRatedBy_caller123'], isTrue);

        // Case 2: Rating is for a property rental in property_history
        firestore.db['property_history/ph123'] = {'id': 'ph123'};
        await repo.submitRentalRating(
          rentalId: 'ph123',
          callerUid: 'caller123',
          targetUid: 'targetUser',
          stars: 3.0,
          role: 'host',
        );
        final propHistDoc = await firestore
            .collection('property_history')
            .doc('ph123')
            .get();
        expect(propHistDoc.data()!['hostRatedBy_caller123'], isTrue);

        expect(firestore.collectionQueries, contains('users'));
        expect(firestore.collectionQueries, contains('rental_history'));
        expect(firestore.collectionQueries, contains('property_history'));
      },
    );

    test(
      'Verify rental extension request, approval, and rejection flows',
      () async {
        // 1. Setup mock states
        firestore.db['users/host123'] = {
          'name': 'Host User',
          'email': 'host@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 1000.0,
        };
        firestore.db['users/renter123'] = {
          'name': 'Renter User',
          'email': 'renter@tranyx.com',
          'accountType': 'employer',
          'tyxBalance': 5000.0,
        };
        firestore.db['rentals/rental123'] = {
          'id': 'rental123',
          'hostId': 'host123',
          'hostName': 'Host User',
          'priceDaily': 2000.0,
          'brand': 'Toyota',
          'model': 'Vios',
          'year': 2021,
          'status': 'Active',
          'endDate': 100000000,
          'totalCost': 2000.0,
        };
        firestore.db['rental_escrows/rental123'] = {
          'rentalId': 'rental123',
          'amount': 2000.0,
          'status': 'Held',
        };

        // 2. Renter requests an extension: 12 hours for 1000 TYXBIT
        await repo.createExtensionRequest(
          rentalId: 'rental123',
          renteeId: 'renter123',
          extendHours: 12,
          fee: 1000.0,
        );

        // Verify renter balance is debited by 1000
        final renter = await repo.getUser('renter123');
        expect(renter!.tyxBalance, equals(5000.0 - 1000.0));

        // Verify rental_extensions has the pending request
        final extDocs = await firestore.collection('rental_extensions').get();
        expect(extDocs.docs.length, equals(1));
        final extId = extDocs.docs.first.id;
        final extData = extDocs.docs.first.data();
        expect(extData['status'], equals('Pending'));
        expect(extData['extendHours'], equals(12));
        expect(extData['fee'], equals(1000.0));

        // Verify rental_extension_escrows has the held fee
        final extEscrowDocs = await firestore
            .collection('rental_extension_escrows')
            .get();
        expect(extEscrowDocs.docs.length, equals(1));
        expect(extEscrowDocs.docs.first.data()['amount'], equals(1000.0));
        expect(extEscrowDocs.docs.first.data()['status'], equals('Held'));

        // 3. Host approves the extension request
        await repo.approveExtension(extId);

        // Verify extension is approved
        final approvedExt = await firestore
            .collection('rental_extensions')
            .doc(extId)
            .get();
        expect(approvedExt.data()!['status'], equals('Approved'));

        // Verify extension escrow merged into main rental escrow
        final mainEscrow = await firestore
            .collection('rental_escrows')
            .doc('rental123')
            .get();
        expect(mainEscrow.data()!['amount'], equals(2000.0 + 1000.0));

        // Verify extension escrow is deleted
        final extEscrowDeleted = await firestore
            .collection('rental_extension_escrows')
            .doc(extId)
            .get();
        expect(extEscrowDeleted.exists, isFalse);

        // Verify rental totalCost and endDate are updated
        final updatedRental = await firestore
            .collection('rentals')
            .doc('rental123')
            .get();
        expect(updatedRental.data()!['totalCost'], equals(2000.0 + 1000.0));
        expect(
          updatedRental.data()!['endDate'],
          equals(100000000 + (12 * 3600 * 1000)),
        );

        // 4. Test Rejection flow on another extension
        // Reset renter balance to 5000.0
        await repo.updateTyxBalance('renter123', 5000.0);
        await repo.createExtensionRequest(
          rentalId: 'rental123',
          renteeId: 'renter123',
          extendHours: 24,
          fee: 2000.0,
        );

        final extDocs2 = await firestore.collection('rental_extensions').get();
        final extId2 = extDocs2.docs
            .firstWhere((doc) => doc.data()['status'] == 'Pending')
            .id;

        // Reject the extension
        await repo.rejectExtension(extId2);

        // Verify extension is rejected
        final rejectedExt = await firestore
            .collection('rental_extensions')
            .doc(extId2)
            .get();
        expect(rejectedExt.data()!['status'], equals('Rejected'));

        // Verify renter is refunded (5000 - 2000 + 2000 = 5000)
        final renterRefunded = await repo.getUser('renter123');
        expect(renterRefunded!.tyxBalance, equals(5000.0));

        // Verify extension escrow is deleted
        final extEscrowDeleted2 = await firestore
            .collection('rental_extension_escrows')
            .doc(extId2)
            .get();
        expect(extEscrowDeleted2.exists, isFalse);
      },
    );

    test('Verify KYC submission collections', () async {
      firestore.db['users/user123'] = {
        'name': 'KYC User',
        'verificationLevel': 0,
      };

      await repo.saveKycSubmission('user123', {
        'fullName': 'KYC User Full',
        'idNumber': 'ID123',
      });

      final kycDoc = await firestore
          .collection('kyc_submissions')
          .doc('user123')
          .get();
      expect(kycDoc.exists, isTrue);
      expect(kycDoc.data()!['fullName'], equals('KYC User Full'));

      final userDoc = await firestore.collection('users').doc('user123').get();
      expect(userDoc.data()!['verificationLevel'], equals(1));

      expect(firestore.collectionQueries, contains('kyc_submissions'));
      expect(firestore.collectionQueries, contains('users'));
    });

    test(
      'Verify checkAndAwardOnboardingQuests awards register_account immediately',
      () async {
        firestore.db['users/user123'] = {
          'name': 'Test User',
          'email': 'user123@tranyx.com',
          'accountType': 'nyxian',
          'terraPoints': 0,
          'earnedRewards': <String>[],
        };

        final newlyAwarded = await repo.checkAndAwardOnboardingQuests(
          'user123',
        );
        expect(newlyAwarded, isTrue);

        final userDoc = await firestore
            .collection('users')
            .doc('user123')
            .get();
        final earnedRewards = List<String>.from(
          userDoc.data()!['earnedRewards'] as List,
        );
        expect(earnedRewards, contains('register_account'));
        expect(
          userDoc.data()!['terraPoints'],
          equals(500),
        ); // register_account is 500 points

        // Check points history
        final historyDocs = await firestore.collection('points_history').get();
        expect(historyDocs.docs.length, equals(1));
        expect(
          historyDocs.docs.first.data()['questId'],
          equals('register_account'),
        );
      },
    );

    group('Vehicle Rental License Requirements (With Driver vs Self-Drive)', () {
      setUp(() {
        firestore.db['users/renter_vip'] = {
          'name': 'VIP Renter',
          'email': 'vip@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 10000.0,
        };
        firestore.db['rentals/car_deluxe'] = {
          'id': 'car_deluxe',
          'hostId': 'host_deluxe',
          'hostName': 'Host Deluxe',
          'priceDaily': 3000.0,
          'driverDailyPrice': 500.0,
          'offersDriver': true,
          'brand': 'Toyota',
          'model': 'Fortuner',
          'year': 2023,
          'status': 'Available',
        };
      });

      test('TC-RENT-01: Booking with Chauffeur (WITH_DRIVER) omits license and succeeds', () async {
        // Given With Driver mode, license is omitted (null)
        await repo.createBookingRequest(
          rentalId: 'car_deluxe',
          renteeId: 'renter_vip',
          renteeName: 'VIP Renter',
          renteePhotoUrl: null,
          durationType: 'daily',
          multiplier: 2,
          licenseNumber: null, // Omitted
          totalCost: 7000.0, // 2 * (3000 + 500)
          hireWithDriver: true, // With Driver mode
          rentalType: 'pickup',
          deliveryAddress: null,
          startDate: DateTime.now().millisecondsSinceEpoch,
          endDate: DateTime.now().add(const Duration(days: 2)).millisecondsSinceEpoch,
        );

        final reqDocs = await firestore.collection('rental_requests').get();
        final req = reqDocs.docs.first.data();
        expect(req['hireWithDriver'], isTrue);
        expect(req['licenseNumber'], isNull);
        expect(req['status'], equals('Pending'));
      });

      test('TC-RENT-02: Self-Drive with Valid License (SELF_DRIVE) stores license and succeeds', () async {
        await repo.createBookingRequest(
          rentalId: 'car_deluxe',
          renteeId: 'renter_vip',
          renteeName: 'VIP Renter',
          renteePhotoUrl: null,
          durationType: 'daily',
          multiplier: 1,
          licenseNumber: 'N01-88-123456', // Valid License
          totalCost: 3000.0,
          hireWithDriver: false, // Self-Drive mode
          rentalType: 'pickup',
          deliveryAddress: null,
          startDate: DateTime.now().millisecondsSinceEpoch,
          endDate: DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
        );

        final reqDocs = await firestore.collection('rental_requests').get();
        final req = reqDocs.docs.last.data();
        expect(req['hireWithDriver'], isFalse);
        expect(req['licenseNumber'], equals('N01-88-123456'));
      });

      test('TC-RENT-03: Self-Drive Missing License validation logic check', () {
        // Verification of validation logic used in UI layers
        bool validateRentalLicense({
          required bool isProperty,
          required bool hireWithDriver,
          required String licenseInput,
        }) {
          final bool requiresLicense = isProperty || !hireWithDriver;
          if (requiresLicense && licenseInput.trim().isEmpty) {
            return false;
          }
          return true;
        }

        // Empty license in Self-Drive -> must fail validation
        final selfDriveEmptyValid = validateRentalLicense(
          isProperty: false,
          hireWithDriver: false,
          licenseInput: '',
        );
        expect(selfDriveEmptyValid, isFalse);

        // Valid license in Self-Drive -> must pass
        final selfDriveValid = validateRentalLicense(
          isProperty: false,
          hireWithDriver: false,
          licenseInput: 'N01-88-123456',
        );
        expect(selfDriveValid, isTrue);
      });

      test('TC-RENT-04: Mode Switch Edge Case (SELF_DRIVE -> WITH_DRIVER)', () async {
        // User typed license while in Self-Drive, then toggled to With Driver
        const typedLicense = 'N01-88-123456';
        String? resolveLicense({required bool hireWithDriver, required String license}) =>
            hireWithDriver ? null : license;

        // User switches mode to With Driver
        const hireWithDriver = true;
        final effectiveLicense = resolveLicense(
          hireWithDriver: hireWithDriver,
          license: typedLicense,
        );

        await repo.createBookingRequest(
          rentalId: 'car_deluxe',
          renteeId: 'renter_vip',
          renteeName: 'VIP Renter',
          renteePhotoUrl: null,
          durationType: 'daily',
          multiplier: 1,
          licenseNumber: effectiveLicense, // Omitted
          totalCost: 3500.0,
          hireWithDriver: hireWithDriver,
          rentalType: 'pickup',
          deliveryAddress: null,
          startDate: DateTime.now().millisecondsSinceEpoch,
          endDate: DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
        );

        final reqDocs = await firestore.collection('rental_requests').get();
        final req = reqDocs.docs.last.data();
        expect(req['hireWithDriver'], isTrue);
        expect(req['licenseNumber'], isNull);
      });
    });

    group('Date-based Availability & Marketplace Visibility Tests', () {
      test('Active/Rented listing remains bookable for non-overlapping future dates', () async {
        final now = DateTime.now();
        final nowMs = now.millisecondsSinceEpoch;
        final currentRentalEnd = now.add(const Duration(days: 3)).millisecondsSinceEpoch;

        firestore.db['users/host1'] = {
          'name': 'Host',
          'email': 'host@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 1000.0,
        };
        firestore.db['users/renter_active'] = {
          'name': 'Active Renter',
          'email': 'active@tranyx.com',
          'accountType': 'employer',
          'tyxBalance': 5000.0,
        };
        firestore.db['users/renter_future'] = {
          'name': 'Future Renter',
          'email': 'future@tranyx.com',
          'accountType': 'employer',
          'tyxBalance': 5000.0,
        };

        // Listing is currently rented
        firestore.db['rentals/car_rented'] = {
          'id': 'car_rented',
          'hostId': 'host1',
          'hostName': 'Host',
          'brand': 'Toyota',
          'model': 'Vios',
          'priceDaily': 2000.0,
          'status': 'Rented',
          'rentalStartDate': nowMs,
          'rentalEndDate': currentRentalEnd,
        };

        // Existing approved request for the active rental
        firestore.db['rental_requests/req_active'] = {
          'id': 'req_active',
          'rentalId': 'car_rented',
          'renteeId': 'renter_active',
          'status': 'Approved',
          'startDate': nowMs,
          'endDate': currentRentalEnd,
        };

        // 1. Check approved requests retrieval includes active rental dates
        final approvedReqs = await repo.getApprovedRequestsForVehicle('car_rented');
        expect(approvedReqs.length, greaterThanOrEqualTo(1));

        // 2. Future booking outside the active rental range (e.g. days 5 to 7) succeeds
        final futureStart = now.add(const Duration(days: 5)).millisecondsSinceEpoch;
        final futureEnd = now.add(const Duration(days: 7)).millisecondsSinceEpoch;

        await repo.createBookingRequest(
          rentalId: 'car_rented',
          renteeId: 'renter_future',
          renteeName: 'Future Renter',
          renteePhotoUrl: null,
          durationType: 'daily',
          multiplier: 2,
          licenseNumber: 'DL-FUTURE-1',
          totalCost: 4000.0,
          hireWithDriver: false,
          rentalType: 'pickup',
          deliveryAddress: null,
          startDate: futureStart,
          endDate: futureEnd,
        );

        final reqDocs = await firestore.collection('rental_requests').get();
        expect(reqDocs.docs.any((d) => d.data()['renteeId'] == 'renter_future'), isTrue);

        // 3. Overlapping booking (e.g. days 1 to 4) is rejected
        final overlapStart = now.add(const Duration(days: 1)).millisecondsSinceEpoch;
        final overlapEnd = now.add(const Duration(days: 4)).millisecondsSinceEpoch;

        expect(
          () => repo.createBookingRequest(
            rentalId: 'car_rented',
            renteeId: 'renter_future',
            renteeName: 'Future Renter',
            renteePhotoUrl: null,
            durationType: 'daily',
            multiplier: 3,
            licenseNumber: 'DL-FUTURE-1',
            totalCost: 6000.0,
            hireWithDriver: false,
            rentalType: 'pickup',
            deliveryAddress: null,
            startDate: overlapStart,
            endDate: overlapEnd,
          ),
          throwsA(predicate((e) => e.toString().contains('Selected dates overlap'))),
        );
      });

      test('approveBookingRequest rejects only conflicting pending requests, leaving non-overlapping requests pending', () async {
        final now = DateTime.now();
        final start1 = now.add(const Duration(days: 2)).millisecondsSinceEpoch;
        final end1 = now.add(const Duration(days: 5)).millisecondsSinceEpoch;

        final overlapStart = now.add(const Duration(days: 3)).millisecondsSinceEpoch;
        final overlapEnd = now.add(const Duration(days: 6)).millisecondsSinceEpoch;

        final futureStart = now.add(const Duration(days: 10)).millisecondsSinceEpoch;
        final futureEnd = now.add(const Duration(days: 12)).millisecondsSinceEpoch;

        firestore.db['rentals/car_multi'] = {
          'id': 'car_multi',
          'hostId': 'host_multi',
          'status': 'Available',
          'brand': 'Honda',
          'model': 'Civic',
        };

        firestore.db['rental_requests/req1'] = {
          'id': 'req1',
          'rentalId': 'car_multi',
          'renteeId': 'renter1',
          'renteeName': 'Renter 1',
          'status': 'Pending',
          'durationType': 'daily',
          'multiplier': 3,
          'totalCost': 3000.0,
          'startDate': start1,
          'endDate': end1,
        };

        firestore.db['rental_requests/req_conflict'] = {
          'id': 'req_conflict',
          'rentalId': 'car_multi',
          'renteeId': 'renter_conflict',
          'renteeName': 'Renter Conflict',
          'status': 'Pending',
          'durationType': 'daily',
          'multiplier': 3,
          'totalCost': 3000.0,
          'startDate': overlapStart,
          'endDate': overlapEnd,
        };

        firestore.db['rental_requests/req_future'] = {
          'id': 'req_future',
          'rentalId': 'car_multi',
          'renteeId': 'renter_future',
          'renteeName': 'Renter Future',
          'status': 'Pending',
          'durationType': 'daily',
          'multiplier': 2,
          'totalCost': 2000.0,
          'startDate': futureStart,
          'endDate': futureEnd,
        };

        // Approve req1
        await repo.approveBookingRequest('req1', 'car_multi', true);

        // req1 is approved
        final req1 = (await firestore.collection('rental_requests').doc('req1').get()).data()!;
        expect(req1['status'], equals('Approved'));

        // req_conflict overlaps with req1 -> automatically rejected
        final reqConflict = (await firestore.collection('rental_requests').doc('req_conflict').get()).data()!;
        expect(reqConflict['status'], equals('Rejected'));

        // req_future does NOT overlap with req1 -> remains Pending!
        final reqFuture = (await firestore.collection('rental_requests').doc('req_future').get()).data()!;
        expect(reqFuture['status'], equals('Pending'));
      });

      test('Property: Active rental allows non-overlapping future bookings, rejects overlaps', () async {
        final now = DateTime.now();
        final nowMs = now.millisecondsSinceEpoch;
        final endLeaseMs = now.add(const Duration(days: 30)).millisecondsSinceEpoch;

        firestore.db['users/host_p'] = {
          'name': 'Host P',
          'email': 'hostp@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 1000.0,
        };
        firestore.db['users/renter_p1'] = {
          'name': 'Renter P1',
          'email': 'renterp1@tranyx.com',
          'accountType': 'employer',
          'tyxBalance': 20000.0,
        };
        firestore.db['users/renter_p2'] = {
          'name': 'Renter P2',
          'email': 'renterp2@tranyx.com',
          'accountType': 'employer',
          'tyxBalance': 20000.0,
        };

        firestore.db['properties/prop_rented'] = {
          'id': 'prop_rented',
          'hostId': 'host_p',
          'title': 'Studio Apartment',
          'priceMonthly': 10000.0,
          'status': 'Rented',
          'startDate': nowMs,
          'endDate': endLeaseMs,
        };

        firestore.db['property_requests/req_prop_active'] = {
          'id': 'req_prop_active',
          'propertyId': 'prop_rented',
          'renteeId': 'renter_p1',
          'status': 'Approved',
          'startDate': nowMs,
          'endDate': endLeaseMs,
        };

        final approved = await repo.getApprovedRequestsForProperty('prop_rented');
        expect(approved.length, greaterThanOrEqualTo(1));

        // Future booking (days 35 to 65) succeeds
        final futureStart = now.add(const Duration(days: 35)).millisecondsSinceEpoch;
        final futureEnd = now.add(const Duration(days: 65)).millisecondsSinceEpoch;

        await repo.createPropertyBookingRequest(
          propertyId: 'prop_rented',
          renteeId: 'renter_p2',
          renteeName: 'Renter P2',
          renteePhotoUrl: null,
          durationType: 'monthly',
          multiplier: 1,
          totalCost: 10000.0,
          baseRentAmount: 10000.0,
          securityDepositAmount: 0.0,
          customerPlatformFeeRate: 0.03,
          hostCommissionRate: 0.07,
          contractType: 'Standard',
          contractTerms: 'Terms',
          startDate: futureStart,
          endDate: futureEnd,
          licenseNumber: 'DL-PROP-2',
        );

        final pDocs = await firestore.collection('property_requests').get();
        expect(pDocs.docs.any((d) => d.data()['renteeId'] == 'renter_p2'), isTrue);

        // Overlapping booking (days 10 to 40) is rejected
        final overlapStart = now.add(const Duration(days: 10)).millisecondsSinceEpoch;
        final overlapEnd = now.add(const Duration(days: 40)).millisecondsSinceEpoch;

        expect(
          () => repo.createPropertyBookingRequest(
            propertyId: 'prop_rented',
            renteeId: 'renter_p2',
            renteeName: 'Renter P2',
            renteePhotoUrl: null,
            durationType: 'monthly',
            multiplier: 1,
            totalCost: 10000.0,
            baseRentAmount: 10000.0,
            securityDepositAmount: 0.0,
            customerPlatformFeeRate: 0.03,
            hostCommissionRate: 0.07,
            contractType: 'Standard',
            contractTerms: 'Terms',
            startDate: overlapStart,
            endDate: overlapEnd,
            licenseNumber: 'DL-PROP-2',
          ),
          throwsA(predicate((e) => e.toString().contains('Selected dates overlap'))),
        );
      });
    });

    group('Vehicle Posting Details Editing (Strict 0-Record Rule) Tests', () {
      test('TC-EDIT-01: Vehicle with zero reservation/booking records can be edited successfully', () async {
        firestore.db['rentals/car_fresh'] = {
          'id': 'car_fresh',
          'hostId': 'host123',
          'brand': 'Toyota',
          'model': 'Vios',
          'year': 2022,
          'plateNumber': 'ABC-1234',
          'status': 'Available',
          'priceDaily': 2000.0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        };

        // No records in rental_requests for car_fresh
        final requests = await repo.getAllRequestsForVehicle('car_fresh');
        expect(requests, isEmpty);

        // Edit listing details
        await repo.updateRental('car_fresh', {
          'brand': 'Toyota',
          'model': 'Vios GR-S',
          'year': 2023,
          'plateNumber': 'ABC-1234',
          'status': 'Available',
          'priceDaily': 2500.0,
        });

        final updated = (await firestore.collection('rentals').doc('car_fresh').get()).data()!;
        expect(updated['model'], equals('Vios GR-S'));
        expect(updated['year'], equals(2023));
        expect(updated['priceDaily'], equals(2500.0));
      });

      test('TC-EDIT-02: Vehicle with reservation/booking records throws Exception on edit attempt', () async {
        firestore.db['rentals/car_booked_before'] = {
          'id': 'car_booked_before',
          'hostId': 'host123',
          'brand': 'Honda',
          'model': 'Civic',
          'year': 2021,
          'plateNumber': 'XYZ-9876',
          'status': 'Available',
          'priceDaily': 3000.0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        };

        // Add a booking/reservation record in rental_requests
        firestore.db['rental_requests/req_past'] = {
          'id': 'req_past',
          'rentalId': 'car_booked_before',
          'renteeId': 'renter123',
          'status': 'Completed',
          'totalCost': 6000.0,
        };

        final requests = await repo.getAllRequestsForVehicle('car_booked_before');
        expect(requests, isNotEmpty);

        // Attempting to edit must fail because reservation/booking records exist
        expect(
          () => repo.updateRental('car_booked_before', {
            'priceDaily': 3500.0,
          }),
          throwsA(predicate((e) =>
              e.toString().contains('Records of reservations or bookings exist for this unit'))),
        );
      });

      test('TC-EDIT-03: Vehicle currently rented throws Exception on edit attempt', () async {
        firestore.db['rentals/car_active'] = {
          'id': 'car_active',
          'hostId': 'host123',
          'brand': 'Ford',
          'model': 'Ranger',
          'status': 'Rented',
          'renteeId': 'renter456',
          'priceDaily': 4000.0,
        };

        expect(
          () => repo.updateRental('car_active', {
            'priceDaily': 4500.0,
          }),
          throwsA(predicate((e) =>
              e.toString().contains('Cannot edit a vehicle listing that is currently booked or active'))),
        );
      });
    });

    group('Host Manage Rental View & Booking Availability Synchronization Tests', () {
      test('AC1 & AC5: Vehicle and Property requests across all states are returned for Host Manage Rental', () async {
        // Vehicle requests
        firestore.db['rental_requests/v_req_1'] = {
          'id': 'v_req_1',
          'rentalId': 'vehicle_101',
          'renteeId': 'renter_a',
          'renteeName': 'Alice',
          'status': 'Pending',
          'startDate': DateTime(2026, 9, 10).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 9, 15).millisecondsSinceEpoch,
          'totalCost': 5000.0,
        };
        firestore.db['rental_requests/v_req_2'] = {
          'id': 'v_req_2',
          'rentalId': 'vehicle_101',
          'renteeId': 'renter_b',
          'renteeName': 'Bob',
          'status': 'Approved',
          'startDate': DateTime(2026, 9, 20).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 9, 25).millisecondsSinceEpoch,
          'totalCost': 6000.0,
        };
        // Unrelated vehicle request
        firestore.db['rental_requests/v_req_other'] = {
          'id': 'v_req_other',
          'rentalId': 'vehicle_other',
          'renteeId': 'renter_c',
          'status': 'Pending',
        };

        // Property requests
        firestore.db['property_requests/p_req_1'] = {
          'id': 'p_req_1',
          'propertyId': 'prop_201',
          'renteeId': 'tenant_x',
          'renteeName': 'Tenant X',
          'status': 'Pending',
          'startDate': DateTime(2026, 10, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 11, 1).millisecondsSinceEpoch,
          'totalCost': 25000.0,
        };
        firestore.db['property_requests/p_req_2'] = {
          'id': 'p_req_2',
          'propertyId': 'prop_201',
          'renteeId': 'tenant_y',
          'renteeName': 'Tenant Y',
          'status': 'Active',
          'startDate': DateTime(2026, 9, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 9, 30).millisecondsSinceEpoch,
          'totalCost': 25000.0,
        };

        final vRequests = await repo.getAllRequestsForVehicle('vehicle_101');
        expect(vRequests.length, equals(2));
        expect(vRequests.map((r) => r['id']), containsAll(['v_req_1', 'v_req_2']));

        final pRequests = await repo.getAllRequestsForProperty('prop_201');
        expect(pRequests.length, equals(2));
        expect(pRequests.map((r) => r['id']), containsAll(['p_req_1', 'p_req_2']));
      });

      test('AC4: Newly created pending vehicle booking immediately locks calendar dates', () async {
        firestore.db['rentals/vehicle_avail'] = {
          'id': 'vehicle_avail',
          'status': 'Available',
        };
        final sept10 = DateTime(2026, 9, 10, 10, 0).millisecondsSinceEpoch;
        final sept15 = DateTime(2026, 9, 15, 10, 0).millisecondsSinceEpoch;

        firestore.db['rental_requests/req_pending_vehicle'] = {
          'id': 'req_pending_vehicle',
          'rentalId': 'vehicle_avail',
          'renteeId': 'renter_new',
          'status': 'Pending',
          'startDate': sept10,
          'endDate': sept15,
          'totalCost': 4000.0,
        };

        final approvedOrPending = await repo.getApprovedRequestsForVehicle('vehicle_avail');
        expect(approvedOrPending.length, equals(1));
        expect(approvedOrPending.first['id'], equals('req_pending_vehicle'));

        // Verify calendar date check locks Sept 10 to 15
        final ranges = approvedOrPending.map((m) => BookingDateRange.fromMap(m)).toList();
        expect(
          BookingAvailabilityHelper.isDateBooked(DateTime(2026, 9, 12), ranges),
          isTrue,
        );
        expect(
          BookingAvailabilityHelper.isDateBooked(DateTime(2026, 9, 16), ranges),
          isFalse,
        );
      });

      test('AC4: Newly created pending property booking immediately locks calendar dates', () async {
        firestore.db['properties/prop_avail'] = {
          'id': 'prop_avail',
          'status': 'Available',
        };
        final oct1 = DateTime(2026, 10, 1).millisecondsSinceEpoch;
        final oct15 = DateTime(2026, 10, 15).millisecondsSinceEpoch;

        firestore.db['property_requests/req_pending_prop'] = {
          'id': 'req_pending_prop',
          'propertyId': 'prop_avail',
          'renteeId': 'tenant_new',
          'status': 'Pending',
          'startDate': oct1,
          'endDate': oct15,
          'totalCost': 15000.0,
        };

        final approvedOrPending = await repo.getApprovedRequestsForProperty('prop_avail');
        expect(approvedOrPending.length, equals(1));
        expect(approvedOrPending.first['id'], equals('req_pending_prop'));

        final ranges = approvedOrPending.map((m) => BookingDateRange.fromMap(m)).toList();
        expect(
          BookingAvailabilityHelper.isDateBooked(DateTime(2026, 10, 5), ranges),
          isTrue,
        );
        expect(
          BookingAvailabilityHelper.isDateBooked(DateTime(2026, 10, 20), ranges),
          isFalse,
        );
      });

      test('AC6: Completed/Cancelled bookings do not lock calendar but are preserved in records', () async {
        firestore.db['rentals/v_history'] = {
          'id': 'v_history',
          'status': 'Available',
        };
        firestore.db['rental_requests/req_done'] = {
          'id': 'req_done',
          'rentalId': 'v_history',
          'status': 'Completed',
          'startDate': DateTime(2026, 8, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 8, 5).millisecondsSinceEpoch,
        };
        firestore.db['rental_requests/req_cancelled'] = {
          'id': 'req_cancelled',
          'rentalId': 'v_history',
          'status': 'Cancelled',
          'startDate': DateTime(2026, 9, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 9, 5).millisecondsSinceEpoch,
        };

        // Host manage rental sees both records
        final all = await repo.getAllRequestsForVehicle('v_history');
        expect(all.length, equals(2));

        // Availability ignores completed and cancelled bookings
        final blocking = await repo.getApprovedRequestsForVehicle('v_history');
        expect(blocking, isEmpty);
      });
    });

    group('Stop Receiving Bookings & Safe Listing Deletion Tests (AC1-AC8)', () {
      test('AC1 & AC7: Host can pause future bookings and resume them for vehicles and properties', () async {
        firestore.db['rentals/v_pause'] = {
          'id': 'v_pause',
          'status': 'Available',
          'acceptingBookings': true,
        };
        firestore.db['properties/p_pause'] = {
          'id': 'p_pause',
          'status': 'Available',
          'acceptingBookings': true,
        };

        // Pause vehicle bookings
        await repo.setVehicleAcceptingBookings('v_pause', false);
        expect(firestore.db['rentals/v_pause']!['status'], equals('Not Accepting Bookings'));
        expect(firestore.db['rentals/v_pause']!['acceptingBookings'], isFalse);

        // Resume vehicle bookings
        await repo.setVehicleAcceptingBookings('v_pause', true);
        expect(firestore.db['rentals/v_pause']!['status'], equals('Available'));
        expect(firestore.db['rentals/v_pause']!['acceptingBookings'], isTrue);

        // Pause property bookings
        await repo.setPropertyAcceptingBookings('p_pause', false);
        expect(firestore.db['properties/p_pause']!['status'], equals('Not Accepting Bookings'));
        expect(firestore.db['properties/p_pause']!['acceptingBookings'], isFalse);

        // Resume property bookings
        await repo.setPropertyAcceptingBookings('p_pause', true);
        expect(firestore.db['properties/p_pause']!['status'], equals('Available'));
        expect(firestore.db['properties/p_pause']!['acceptingBookings'], isTrue);
      });

      test('AC1 & AC7: Booking requests are strictly blocked when listing is paused / not accepting bookings', () async {
        firestore.db['users/renter1'] = {
          'name': 'Renter User',
          'email': 'renter@tranyx.com',
          'tyxBalance': 10000.0,
        };
        firestore.db['rentals/v_paused_booking'] = {
          'id': 'v_paused_booking',
          'status': 'Not Accepting Bookings',
          'acceptingBookings': false,
          'priceDaily': 1500.0,
          'hostId': 'host1',
        };
        firestore.db['properties/p_paused_booking'] = {
          'id': 'p_paused_booking',
          'status': 'Not Accepting Bookings',
          'acceptingBookings': false,
          'priceMonthly': 25000.0,
          'hostId': 'host1',
        };

        // Vehicle request should fail
        expect(
          () => repo.createBookingRequest(
            rentalId: 'v_paused_booking',
            renteeId: 'renter1',
            renteeName: 'Renter User',
            renteePhotoUrl: null,
            durationType: 'daily',
            multiplier: 4,
            totalCost: 6000.0,
            hireWithDriver: false,
            rentalType: 'self_drive',
            deliveryAddress: null,
            startDate: DateTime(2026, 11, 1).millisecondsSinceEpoch,
            endDate: DateTime(2026, 11, 5).millisecondsSinceEpoch,
          ),
          throwsA(predicate((e) => e.toString().contains('not accepting new bookings'))),
        );

        // Property request should fail
        expect(
          () => repo.createPropertyBookingRequest(
            propertyId: 'p_paused_booking',
            renteeId: 'renter1',
            renteeName: 'Renter User',
            renteePhotoUrl: null,
            contractType: 'Standard',
            contractTerms: 'Terms',
            startDate: DateTime(2026, 11, 1).millisecondsSinceEpoch,
            endDate: DateTime(2026, 12, 1).millisecondsSinceEpoch,
            totalCost: 25000.0,
            durationType: 'monthly',
            multiplier: 1,
          ),
          throwsA(predicate((e) => e.toString().contains('not accepting new bookings'))),
        );
      });

      test('AC4: Deleting listing is BLOCKED when pending requests exist (Vehicles & Properties)', () async {
        firestore.db['rentals/v_has_pending'] = {
          'id': 'v_has_pending',
          'status': 'Available',
          'acceptingBookings': true,
        };
        firestore.db['rental_requests/req_pending_1'] = {
          'id': 'req_pending_1',
          'rentalId': 'v_has_pending',
          'status': 'Pending',
        };

        firestore.db['properties/p_has_pending'] = {
          'id': 'p_has_pending',
          'status': 'Available',
          'acceptingBookings': true,
        };
        firestore.db['property_requests/req_pending_2'] = {
          'id': 'req_pending_2',
          'propertyId': 'p_has_pending',
          'status': 'pending',
        };

        // Vehicle delete blocked
        expect(
          () => repo.deleteRental('v_has_pending'),
          throwsA(predicate((e) => e.toString().contains('Please accept or reject all pending requests'))),
        );
        expect(firestore.db['rentals/v_has_pending']!['status'], equals('Available'));

        // Property delete blocked
        expect(
          () => repo.deletePropertyRental('p_has_pending'),
          throwsA(predicate((e) => e.toString().contains('Please accept or reject all pending requests'))),
        );
        expect(firestore.db['properties/p_has_pending']!['status'], equals('Available'));
      });

      test('AC2, AC3, AC5, AC6, AC8: Deleting listing with confirmed bookings soft-deletes/archives listing, preserves bookings/contracts, and does not refund listing fee', () async {
        firestore.db['users/host_owner'] = {
          'name': 'Owner Host',
          'tyxBalance': 1000.0,
        };
        firestore.db['rentals/v_with_confirmed'] = {
          'id': 'v_with_confirmed',
          'hostId': 'host_owner',
          'status': 'Available',
          'acceptingBookings': true,
          'priceDaily': 2000.0,
        };
        firestore.db['transactions/tx_fee'] = {
          'rentalId': 'v_with_confirmed',
          'type': 'listing_fee',
          'amount': 30.0,
        };
        firestore.db['rental_requests/req_confirmed_1'] = {
          'id': 'req_confirmed_1',
          'rentalId': 'v_with_confirmed',
          'status': 'Approved',
          'startDate': DateTime(2026, 12, 1).millisecondsSinceEpoch,
          'endDate': DateTime(2026, 12, 5).millisecondsSinceEpoch,
        };

        // Delete vehicle with confirmed booking
        await repo.deleteRental('v_with_confirmed');

        // Listing is soft-deleted / archived
        final deletedVehicle = firestore.db['rentals/v_with_confirmed']!;
        expect(deletedVehicle['status'], equals('Archived'));
        expect(deletedVehicle['isDeleted'], isTrue);
        expect(deletedVehicle['acceptingBookings'], isFalse);

        // Listing fee is NOT refunded because confirmed bookings exist
        final host = firestore.db['users/host_owner']!;
        expect(host['tyxBalance'], equals(1000.0));

        // Confirmed requests are preserved and queryable
        final allRequests = await repo.getAllRequestsForVehicle('v_with_confirmed');
        expect(allRequests.length, equals(1));
        expect(allRequests.first['id'], equals('req_confirmed_1'));
      });

      test('AC8: Deleting clean listing with no bookings refunds listing fee and soft-deletes', () async {
        firestore.db['users/host_clean'] = {
          'name': 'Clean Host',
          'tyxBalance': 500.0,
        };
        firestore.db['rentals/v_clean'] = {
          'id': 'v_clean',
          'hostId': 'host_clean',
          'status': 'Available',
          'acceptingBookings': true,
          'priceDaily': 2000.0,
        };
        firestore.db['transactions/tx_clean_fee'] = {
          'rentalId': 'v_clean',
          'type': 'listing_fee',
          'amount': 30.0,
        };

        // Delete clean vehicle
        await repo.deleteRental('v_clean');

        final deletedVehicle = firestore.db['rentals/v_clean']!;
        expect(deletedVehicle['status'], equals('Archived'));
        expect(deletedVehicle['isDeleted'], isTrue);
        expect(deletedVehicle['acceptingBookings'], isFalse);

        // Listing fee IS refunded
        final host = firestore.db['users/host_clean']!;
        expect(host['tyxBalance'], equals(530.0));
      });
    });

    group('Multi-Booking Isolation & Status Synchronization Tests (AC1–AC12)', () {
      test('AC1–AC4, AC6–AC8, AC11: Vehicle multi-booking isolation, independent escrows, independent status, and Renter streams', () async {
        // Setup Host and 2 Renters
        firestore.db['users/host_v'] = {
          'name': 'Host V',
          'email': 'host_v@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 1000.0,
        };
        firestore.db['users/renter_a'] = {
          'name': 'Customer A',
          'email': 'renter_a@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 20000.0,
        };
        firestore.db['users/renter_b'] = {
          'name': 'Customer B',
          'email': 'renter_b@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 20000.0,
        };

        // Create Vehicle listing
        firestore.db['rentals/v_multi'] = {
          'id': 'v_multi',
          'hostId': 'host_v',
          'hostName': 'Host V',
          'brand': 'Toyota',
          'model': 'Fortuner',
          'year': 2023,
          'status': 'Available',
          'priceDaily': 3000.0,
          'acceptingBookings': true,
        };

        final startA = DateTime(2026, 11, 1).millisecondsSinceEpoch;
        final endA = DateTime(2026, 11, 5).millisecondsSinceEpoch;
        final startB = DateTime(2026, 11, 10).millisecondsSinceEpoch;
        final endB = DateTime(2026, 11, 15).millisecondsSinceEpoch;

        // 1. Two separate requests for the same vehicle
        firestore.db['rental_requests/b1'] = {
          'id': 'b1',
          'rentalId': 'v_multi',
          'hostId': 'host_v',
          'renteeId': 'renter_a',
          'renteeName': 'Customer A',
          'startDate': startA,
          'endDate': endA,
          'durationType': 'daily',
          'multiplier': 4,
          'totalCost': 12000.0,
          'bookingFee': 360.0,
          'status': 'Pending',
        };
        firestore.db['rental_escrows/b1'] = {
          'requestId': 'b1',
          'rentalId': 'v_multi',
          'renteeId': 'renter_a',
          'hostId': 'host_v',
          'amount': 12000.0,
          'status': 'Held',
        };

        firestore.db['rental_requests/b2'] = {
          'id': 'b2',
          'rentalId': 'v_multi',
          'hostId': 'host_v',
          'renteeId': 'renter_b',
          'renteeName': 'Customer B',
          'startDate': startB,
          'endDate': endB,
          'durationType': 'daily',
          'multiplier': 5,
          'totalCost': 15000.0,
          'bookingFee': 450.0,
          'status': 'Pending',
        };
        firestore.db['rental_escrows/b2'] = {
          'requestId': 'b2',
          'rentalId': 'v_multi',
          'renteeId': 'renter_b',
          'hostId': 'host_v',
          'amount': 15000.0,
          'status': 'Held',
        };

        // 2. Host approves Booking 1
        await repo.approveBookingRequest('b1', 'v_multi', true);
        expect(firestore.db['rental_requests/b1']?['status'], equals('Approved'));
        // AC2: Booking 2 remains Pending
        expect(firestore.db['rental_requests/b2']?['status'], equals('Pending'));
        // AC2: Canonical escrows for both requests are preserved
        expect(firestore.db['rental_escrows/b1']?['amount'], equals(12000.0));
        expect(firestore.db['rental_escrows/b2']?['amount'], equals(15000.0));

        // Customer A signs contract for Booking 1
        await repo.signVehicleContract('v_multi', 'sig_renter_a', requestId: 'b1');
        expect(firestore.db['rental_requests/b1']?['status'], equals('Booked'));

        // 3. Host subsequently approves Booking 2
        await repo.approveBookingRequest('b2', 'v_multi', true);
        expect(firestore.db['rental_requests/b2']?['status'], equals('Approved'));
        // AC1 & AC3: Booking 1 is STILL Booked (NOT overridden)
        expect(firestore.db['rental_requests/b1']?['status'], equals('Booked'));
        // AC2: Both canonical escrows remain distinct and intact
        expect(firestore.db['rental_escrows/b1']?['amount'], equals(12000.0));
        expect(firestore.db['rental_escrows/b2']?['amount'], equals(15000.0));

        // Customer B signs contract for Booking 2
        await repo.signVehicleContract('v_multi', 'sig_renter_b', requestId: 'b2');
        expect(firestore.db['rental_requests/b2']?['status'], equals('Booked'));
        expect(firestore.db['rental_requests/b1']?['status'], equals('Booked'));

        // 4. AC4: Verify Renter active streams return strictly their respective bookings
        final renterABookings = await repo.getRenterActiveBookingsStream('renter_a').first;
        expect(renterABookings.length, equals(1));
        expect(renterABookings.first['id'], equals('b1'));
        expect(renterABookings.first['renteeId'], equals('renter_a'));

        final renterBBookings = await repo.getRenterActiveBookingsStream('renter_b').first;
        expect(renterBBookings.length, equals(1));
        expect(renterBBookings.first['id'], equals('b2'));
        expect(renterBBookings.first['renteeId'], equals('renter_b'));

        // 5. AC5 & AC7: Host queries all requests for the listing
        final hostRequests = await repo.getAllRequestsForVehicle('v_multi');
        expect(hostRequests.length, equals(2));
        final req1Data = hostRequests.firstWhere((r) => r['id'] == 'b1');
        final req2Data = hostRequests.firstWhere((r) => r['id'] == 'b2');
        expect(req1Data['renteeName'], equals('Customer A'));
        expect(req2Data['renteeName'], equals('Customer B'));

        // 6. AC3: Host advances Booking 1 status through lifecycle without mutating Booking 2
        await repo.updateRentalStatus('v_multi', 'Ongoing', requestId: 'b1');
        expect(firestore.db['rental_requests/b1']?['status'], equals('Ongoing'));
        expect(firestore.db['rental_requests/b2']?['status'], equals('Booked'));

        await repo.updateRentalStatus('v_multi', 'Returning', requestId: 'b1');
        expect(firestore.db['rental_requests/b1']?['status'], equals('Returning'));
        expect(firestore.db['rental_requests/b2']?['status'], equals('Booked'));

        // 7. AC9 & AC11: Complete Booking 1; Booking 2 remains intact and becomes current
        final hostBalanceBefore = firestore.db['users/host_v']!['tyxBalance'] as double;
        await repo.completeRental('v_multi', requestId: 'b1');

        expect(firestore.db['rental_requests/b1']?['status'], equals('Completed'));
        expect(firestore.db['rental_requests/b2']?['status'], equals('Booked'));

        // Host received payout for Booking 1 (12000 - 3% fee = 11640)
        final hostBalanceAfter = firestore.db['users/host_v']!['tyxBalance'] as double;
        expect(hostBalanceAfter, equals(hostBalanceBefore + 11640.0));

        // Booking 2's escrow is completely preserved
        expect(firestore.db['rental_escrows/b2']?['amount'], equals(15000.0));
        expect(firestore.db['rental_escrows/b2']?['status'], equals('Held'));

        // Booking 2 is now promoted to current on the vehicle listing
        expect(firestore.db['rentals/v_multi']?['currentRequestId'], equals('b2'));
        expect(firestore.db['rentals/v_multi']?['renteeId'], equals('renter_b'));
        expect(firestore.db['rentals/v_multi']?['status'], equals('Booked'));

        // Renter B still sees Booking 2 as active
        final renterBStillActive = await repo.getRenterActiveBookingsStream('renter_b').first;
        expect(renterBStillActive.length, equals(1));
        expect(renterBStillActive.first['id'], equals('b2'));
      });

      test('AC10: Property multi-booking isolation, independent escrows, independent status, and Renter streams', () async {
        // Setup Host and 2 Renters
        firestore.db['users/host_p'] = {
          'name': 'Host P',
          'email': 'host_p@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 1000.0,
        };
        firestore.db['users/renter_p1'] = {
          'name': 'Tenant 1',
          'email': 'tenant1@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 20000.0,
        };
        firestore.db['users/renter_p2'] = {
          'name': 'Tenant 2',
          'email': 'tenant2@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 20000.0,
        };

        // Create Property listing
        firestore.db['properties/p_multi'] = {
          'id': 'p_multi',
          'hostId': 'host_p',
          'hostName': 'Host P',
          'title': 'Luxury Condo',
          'status': 'Available',
          'priceMonthly': 10000.0,
          'acceptingBookings': true,
        };

        final startP1 = DateTime(2026, 10, 1).millisecondsSinceEpoch;
        final endP1 = DateTime(2026, 10, 31).millisecondsSinceEpoch;
        final startP2 = DateTime(2026, 11, 1).millisecondsSinceEpoch;
        final endP2 = DateTime(2026, 11, 30).millisecondsSinceEpoch;

        // 1. Tenant 1 and Tenant 2 requests
        firestore.db['property_requests/pb1'] = {
          'id': 'pb1',
          'propertyId': 'p_multi',
          'hostId': 'host_p',
          'renteeId': 'renter_p1',
          'renteeName': 'Tenant 1',
          'startDate': startP1,
          'endDate': endP1,
          'durationType': 'monthly',
          'multiplier': 1,
          'totalCost': 10000.0,
          'baseRentAmount': 10000.0,
          'bookingFee': 300.0,
          'status': 'Pending',
        };
        firestore.db['property_escrows/pb1'] = {
          'requestId': 'pb1',
          'propertyId': 'p_multi',
          'renteeId': 'renter_p1',
          'hostId': 'host_p',
          'amount': 10000.0,
          'baseRentAmount': 10000.0,
          'status': 'Held',
        };

        firestore.db['property_requests/pb2'] = {
          'id': 'pb2',
          'propertyId': 'p_multi',
          'hostId': 'host_p',
          'renteeId': 'renter_p2',
          'renteeName': 'Tenant 2',
          'startDate': startP2,
          'endDate': endP2,
          'durationType': 'monthly',
          'multiplier': 1,
          'totalCost': 10000.0,
          'baseRentAmount': 10000.0,
          'bookingFee': 300.0,
          'status': 'Pending',
        };
        firestore.db['property_escrows/pb2'] = {
          'requestId': 'pb2',
          'propertyId': 'p_multi',
          'renteeId': 'renter_p2',
          'hostId': 'host_p',
          'amount': 10000.0,
          'baseRentAmount': 10000.0,
          'status': 'Held',
        };

        // 2. Host approves Tenant 1
        await repo.approvePropertyBookingRequest('pb1', 'p_multi', true);
        expect(firestore.db['property_requests/pb1']?['status'], equals('Approved'));
        expect(firestore.db['property_requests/pb2']?['status'], equals('Pending'));

        // Tenant 1 signs contract
        await repo.signPropertyContract('p_multi', 'sig_p1', requestId: 'pb1');
        expect(firestore.db['property_requests/pb1']?['status'], equals('Booked'));

        // 3. Host subsequently approves Tenant 2
        await repo.approvePropertyBookingRequest('pb2', 'p_multi', true);
        expect(firestore.db['property_requests/pb2']?['status'], equals('Approved'));
        expect(firestore.db['property_requests/pb1']?['status'], equals('Booked'));

        // Tenant 2 signs contract
        await repo.signPropertyContract('p_multi', 'sig_p2', requestId: 'pb2');
        expect(firestore.db['property_requests/pb2']?['status'], equals('Booked'));
        expect(firestore.db['property_requests/pb1']?['status'], equals('Booked'));

        // 4. Verify Renter active streams
        final p1Bookings = await repo.getPropertyRenterActiveBookingsStream('renter_p1').first;
        expect(p1Bookings.length, equals(1));
        expect(p1Bookings.first['id'], equals('pb1'));

        final p2Bookings = await repo.getPropertyRenterActiveBookingsStream('renter_p2').first;
        expect(p2Bookings.length, equals(1));
        expect(p2Bookings.first['id'], equals('pb2'));

        // 5. Host queries all property requests
        final allPropRequests = await repo.getAllRequestsForProperty('p_multi');
        expect(allPropRequests.length, equals(2));

        // 6. Complete Tenant 1 lease independently
        final hostBalanceBefore = firestore.db['users/host_p']!['tyxBalance'] as double;
        await repo.completePropertyRental('p_multi', requestId: 'pb1');

        expect(firestore.db['property_requests/pb1']?['status'], equals('Completed'));
        expect(firestore.db['property_requests/pb2']?['status'], equals('Booked'));

        // Host received Tenant 1 earnings (10000 - 7% fee = 9300)
        final hostBalanceAfter = firestore.db['users/host_p']!['tyxBalance'] as double;
        expect(hostBalanceAfter, equals(hostBalanceBefore + 9300.0));

        // Tenant 2's escrow remains intact (holding totalCustomerPaid = 10300.0)
        expect(firestore.db['property_escrows/pb2']?['amount'], equals(10300.0));
        expect(firestore.db['property_escrows/pb2']?['baseRentAmount'], equals(10000.0));
        expect(firestore.db['property_escrows/pb2']?['status'], equals('Held'));

        // Tenant 2 promoted to listing
        expect(firestore.db['properties/p_multi']?['currentRequestId'], equals('pb2'));
        expect(firestore.db['properties/p_multi']?['renteeId'], equals('renter_p2'));
      });
    });

    group('Renter Pending Requests Listing Identification & Linking (AC1–AC10)', () {
      late FakeFirebaseFirestore firestore;
      late TransitRepository repo;

      setUp(() {
        firestore = FakeFirebaseFirestore();
        repo = TransitRepository(firestore);

        firestore.db['settings/platform_fees'] = {
          'listingFeeRate': 0.015,
          'customerFeeRate': 0.03,
          'hostCommissionRate': 0.07,
          'propertyCustomerFeeRate': 0.03,
          'propertyHostCommissionRate': 0.07,
        };
      });

      test('AC1, AC2, AC6, AC7, AC11: Vehicle pending request creation snapshots listing details and links accurately', () async {
        firestore.db['users/renter_v'] = {
          'name': 'Renter V',
          'email': 'renter_v@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 5000.0,
        };
        firestore.db['users/host_v'] = {
          'name': 'Host V',
          'email': 'host_v@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 100.0,
        };
        firestore.db['rentals/v_test'] = {
          'id': 'v_test',
          'hostId': 'host_v',
          'hostName': 'Host V',
          'brand': 'Toyota',
          'model': 'Vios 2023',
          'type': 'car',
          'plateNumber': 'XYZ 888',
          'vehicleValue': 800000.0,
          'frontPhotoUrl': 'https://example.com/vios_front.jpg',
          'pickupAddress': '456 Ayala Ave, Makati',
          'pickupLat': 14.5547,
          'pickupLng': 121.0244,
          'priceDaily': 1500.0,
          'status': 'Available',
          'acceptingBookings': true,
          'isDeleted': false,
        };

        final startMs = DateTime(2026, 9, 15, 9, 0).millisecondsSinceEpoch;
        final endMs = DateTime(2026, 9, 17, 9, 0).millisecondsSinceEpoch;

        await repo.createBookingRequest(
          rentalId: 'v_test',
          renteeId: 'renter_v',
          renteeName: 'Renter V',
          renteePhotoUrl: 'https://example.com/renter_avatar.jpg',
          durationType: 'daily',
          multiplier: 2,
          totalCost: 3000.0, // 3000 base + 3% fee (90) = 3090 total deducted
          hireWithDriver: false,
          rentalType: 'self_drive',
          deliveryAddress: null,
          startDate: startMs,
          endDate: endMs,
        );

        // Find the created request in rental_requests
        final reqKey = firestore.db.keys.firstWhere((k) => k.startsWith('rental_requests/'));
        final reqDoc = firestore.db[reqKey]!;

        // AC1 & AC2: Identifying information is explicitly saved on the request document
        expect(reqDoc['rentalId'], equals('v_test'));
        expect(reqDoc['brand'], equals('Toyota'));
        expect(reqDoc['model'], equals('Vios 2023'));
        expect(reqDoc['frontPhotoUrl'], equals('https://example.com/vios_front.jpg'));
        expect(reqDoc['pickupAddress'], equals('456 Ayala Ave, Makati'));
        expect(reqDoc['pickupLat'], equals(14.5547));
        expect(reqDoc['pickupLng'], equals(121.0244));

        // AC6: Correct booking schedule dates
        expect(reqDoc['startDate'], equals(startMs));
        expect(reqDoc['endDate'], equals(endMs));

        // Escrow locked from renter balance
        expect(reqDoc['status'], equals('Pending'));
        expect(firestore.db['users/renter_v']!['tyxBalance'], equals(5000.0 - 3090.0));
      });

      test('AC1, AC2, AC6, AC7, AC10: Property pending request creation snapshots listing details and links accurately', () async {
        firestore.db['users/renter_p'] = {
          'name': 'Renter P',
          'email': 'renter_p@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 50000.0,
        };
        firestore.db['users/host_p'] = {
          'name': 'Host P',
          'email': 'host_p@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 500.0,
        };
        firestore.db['properties/p_test'] = {
          'id': 'p_test',
          'hostId': 'host_p',
          'hostName': 'Host P',
          'title': 'BGC High Street Studio Loft',
          'description': 'Modern studio in prime location',
          'type': 'condo',
          'category': 'residential',
          'photoUrls': ['https://example.com/bgc_loft.jpg', 'https://example.com/bgc_loft_bath.jpg'],
          'address': '28th Street, Bonifacio Global City, Taguig',
          'latitude': 14.5505,
          'longitude': 121.0509,
          'priceMonthly': 35000.0,
          'priceWeekly': 10000.0,
          'priceDaily': 2000.0,
          'depositMonths': 0,
          'status': 'Available',
          'acceptingBookings': true,
          'isDeleted': false,
          'contractType': 'tranyx',
          'contractTerms': 'Standard lease terms',
        };

        final startMs = DateTime(2026, 10, 1, 14, 0).millisecondsSinceEpoch;
        final endMs = DateTime(2026, 10, 5, 12, 0).millisecondsSinceEpoch;

        await repo.createPropertyBookingRequest(
          propertyId: 'p_test',
          renteeId: 'renter_p',
          renteeName: 'Renter P',
          renteePhotoUrl: 'https://example.com/renter_p.jpg',
          durationType: 'daily',
          multiplier: 4,
          totalCost: 8000.0, // 8000 base + 3% fee (240) = 8240 total deducted
          contractType: 'tranyx',
          contractTerms: 'Standard lease terms',
          startDate: startMs,
          endDate: endMs,
        );

        // Find the created request in property_requests
        final reqKey = firestore.db.keys.firstWhere((k) => k.startsWith('property_requests/'));
        final reqDoc = firestore.db[reqKey]!;

        // AC1 & AC2: Identifying information is explicitly saved on the request document
        expect(reqDoc['propertyId'], equals('p_test'));
        expect(reqDoc['title'], equals('BGC High Street Studio Loft'));
        expect(reqDoc['photoUrl'], equals('https://example.com/bgc_loft.jpg'));
        expect(reqDoc['photoUrls'], contains('https://example.com/bgc_loft.jpg'));
        expect(reqDoc['address'], equals('28th Street, Bonifacio Global City, Taguig'));
        expect(reqDoc['latitude'], equals(14.5505));
        expect(reqDoc['longitude'], equals(121.0509));

        // AC6: Correct booking schedule dates
        expect(reqDoc['startDate'], equals(startMs));
        expect(reqDoc['endDate'], equals(endMs));

        // Escrow locked from renter balance
        expect(reqDoc['status'], equals('Pending'));
        expect(firestore.db['users/renter_p']!['tyxBalance'], equals(50000.0 - 8240.0));
      });

      test('AC3, AC4, AC5: Multiple concurrent pending requests maintain distinct references without cross-contamination', () async {
        firestore.db['users/renter_multi'] = {
          'name': 'Multi Renter',
          'email': 'multi@tranyx.com',
          'accountType': 'nyxian',
          'tyxBalance': 50000.0,
        };
        firestore.db['users/host_1'] = {'name': 'Host 1', 'tyxBalance': 0.0};
        firestore.db['users/host_2'] = {'name': 'Host 2', 'tyxBalance': 0.0};

        // Two distinct vehicles
        firestore.db['rentals/v_sedan'] = {
          'id': 'v_sedan',
          'hostId': 'host_1',
          'brand': 'Mazda',
          'model': '3 Sport',
          'type': 'car',
          'frontPhotoUrl': 'https://example.com/mazda.jpg',
          'pickupAddress': 'Quezon City',
          'priceDaily': 2000.0,
          'status': 'Available',
          'acceptingBookings': true,
          'isDeleted': false,
        };
        firestore.db['rentals/v_suv'] = {
          'id': 'v_suv',
          'hostId': 'host_2',
          'brand': 'Mitsubishi',
          'model': 'Montero Sport',
          'type': 'suv',
          'frontPhotoUrl': 'https://example.com/montero.jpg',
          'pickupAddress': 'Pasig City',
          'priceDaily': 3500.0,
          'status': 'Available',
          'acceptingBookings': true,
          'isDeleted': false,
        };

        // Create Request 1 (base 2000.0)
        await repo.createBookingRequest(
          rentalId: 'v_sedan',
          renteeId: 'renter_multi',
          renteeName: 'Multi Renter',
          renteePhotoUrl: null,
          durationType: 'daily',
          multiplier: 1,
          totalCost: 2000.0,
          hireWithDriver: false,
          rentalType: 'self_drive',
          deliveryAddress: null,
          startDate: 1726000000000,
          endDate: 1726086400000,
        );

        // Create Request 2 (base 7000.0)
        await repo.createBookingRequest(
          rentalId: 'v_suv',
          renteeId: 'renter_multi',
          renteeName: 'Multi Renter',
          renteePhotoUrl: null,
          durationType: 'daily',
          multiplier: 2,
          totalCost: 7000.0,
          hireWithDriver: false,
          rentalType: 'self_drive',
          deliveryAddress: null,
          startDate: 1726200000000,
          endDate: 1726372800000,
        );

        final pendingRequests = await repo.getRenterPendingRequestsStream('renter_multi').first;
        expect(pendingRequests.length, equals(2));

        final reqSedan = pendingRequests.firstWhere((r) => r['rentalId'] == 'v_sedan');
        final reqSuv = pendingRequests.firstWhere((r) => r['rentalId'] == 'v_suv');

        expect(reqSedan['brand'], equals('Mazda'));
        expect(reqSedan['model'], equals('3 Sport'));
        expect(reqSedan['frontPhotoUrl'], equals('https://example.com/mazda.jpg'));
        expect(reqSedan['pickupAddress'], equals('Quezon City'));
        expect(reqSedan['totalCost'], equals(2000.0));

        expect(reqSuv['brand'], equals('Mitsubishi'));
        expect(reqSuv['model'], equals('Montero Sport'));
        expect(reqSuv['frontPhotoUrl'], equals('https://example.com/montero.jpg'));
        expect(reqSuv['pickupAddress'], equals('Pasig City'));
        expect(reqSuv['totalCost'], equals(7000.0));
      });

      test('AC8, AC9: Renter cancellation of vehicle pending request restores locked funds immediately', () async {
        firestore.db['users/renter_cancel_v'] = {
          'name': 'Canceller V',
          'tyxBalance': 10000.0,
        };
        firestore.db['rentals/v_cancel'] = {
          'id': 'v_cancel',
          'hostId': 'host_x',
          'brand': 'Ford',
          'model': 'Everest',
          'type': 'suv',
          'priceDaily': 3000.0,
          'status': 'Available',
          'acceptingBookings': true,
          'isDeleted': false,
        };

        await repo.createBookingRequest(
          rentalId: 'v_cancel',
          renteeId: 'renter_cancel_v',
          renteeName: 'Canceller V',
          renteePhotoUrl: null,
          durationType: 'daily',
          multiplier: 1,
          totalCost: 3000.0, // 3000 base + 90 fee = 3090
          hireWithDriver: false,
          rentalType: 'self_drive',
          deliveryAddress: null,
          startDate: 1726000000000,
          endDate: 1726086400000,
        );

        expect(firestore.db['users/renter_cancel_v']!['tyxBalance'], equals(10000.0 - 3090.0));

        final reqKey = firestore.db.keys.firstWhere((k) => k.startsWith('rental_requests/'));
        final reqId = firestore.db[reqKey]!['id'] as String;

        // Cancel
        await repo.cancelBookingRequest(reqId);

        // Funds refunded
        expect(firestore.db['users/renter_cancel_v']!['tyxBalance'], equals(10000.0));
        expect(firestore.db[reqKey]!['status'], equals('Cancelled'));
        expect(firestore.db['rental_escrows/$reqId'], isNull);
      });

      test('AC8, AC9: Renter cancellation of property pending request restores locked funds immediately', () async {
        firestore.db['users/renter_cancel_p'] = {
          'name': 'Canceller P',
          'tyxBalance': 15000.0,
        };
        firestore.db['properties/p_cancel'] = {
          'id': 'p_cancel',
          'hostId': 'host_y',
          'title': 'Makati Condo',
          'description': 'Cozy condo',
          'type': 'condo',
          'category': 'residential',
          'photoUrls': ['https://example.com/condo.jpg'],
          'address': 'Makati Ave',
          'latitude': 14.56,
          'longitude': 121.03,
          'priceMonthly': 25000.0,
          'priceDaily': 1500.0,
          'depositMonths': 0,
          'status': 'Available',
          'acceptingBookings': true,
          'isDeleted': false,
          'contractType': 'tranyx',
          'contractTerms': 'Terms',
        };

        await repo.createPropertyBookingRequest(
          propertyId: 'p_cancel',
          renteeId: 'renter_cancel_p',
          renteeName: 'Canceller P',
          renteePhotoUrl: null,
          durationType: 'daily',
          multiplier: 2,
          totalCost: 3000.0, // 3000 base + 90 fee = 3090
          contractType: 'tranyx',
          contractTerms: 'Terms',
          startDate: 1726000000000,
          endDate: 1726172800000,
        );

        expect(firestore.db['users/renter_cancel_p']!['tyxBalance'], equals(15000.0 - 3090.0));

        final reqKey = firestore.db.keys.firstWhere((k) => k.startsWith('property_requests/'));
        final reqId = firestore.db[reqKey]!['id'] as String;

        // Cancel property request via cancelPropertyBookingRequest
        await repo.cancelPropertyBookingRequest(reqId);

        // Funds refunded
        expect(firestore.db['users/renter_cancel_p']!['tyxBalance'], equals(15000.0));
        expect(firestore.db[reqKey]!['status'], equals('Cancelled'));
        expect(firestore.db['property_escrows/$reqId'], isNull);
      });
    });
  });
}
