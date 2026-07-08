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

        final deletedReqEscrow = await firestore
            .collection('rental_escrows')
            .doc('req123')
            .get();
        expect(deletedReqEscrow.exists, isFalse);

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

        // 1. Create Property Listing (Listing fee: 1.5% of monthly price = 150.0)
        final propertyId = await repo.createPropertyRental(property);
        expect(propertyId, isNotEmpty);

        final hostAfterListing = await repo.getUser('host123');
        expect(hostAfterListing!.tyxBalance, equals(1000.0 - 150.0));

        expect(firestore.collectionQueries, contains('properties'));
        expect(firestore.collectionQueries, contains('transactions'));

        // 2. Request Booking (totalCost = 10000.0, bookingFee = 3% = 300.0, required = 10300.0)
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
          'renteeId': 'renter123',
        };
        firestore.db['property_escrows/$propertyId'] = {
          'propertyId': propertyId,
          'renteeId': 'renter123',
          'hostId': 'host123',
          'amount': 10000.0,
          'status': 'Held',
        };

        // 4. Complete Property lease (Platform commission = 3% of 10000 = 300, payout = 9700)
        await repo.completePropertyRental(propertyId);

        // Verify host wallet has payout
        final hostFinal = await repo.getUser('host123');
        expect(hostFinal!.tyxBalance, equals((1000.0 - 150.0) + 9700.0));

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
  });
}
