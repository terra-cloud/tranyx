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

      await firestore.collection('users').doc('user123').update({'tyxBalance': 850.0});
      final updatedProfile = await repo.getUser('user123');
      expect(updatedProfile!.tyxBalance, equals(850.0));

      expect(firestore.collectionQueries, contains('users'));
    });

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

    });

    group('Date-based Availability & Marketplace Visibility Tests', () {
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

    });

    group('Multi-Booking Isolation & Status Synchronization Tests (AC1–AC12)', () {
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

    });

    group('Unsigned Cancellation, Revocation, and Active Lease Cancellation Parity Tests', () {
    });

    group('Vehicle & Property Listing Free Edits (updateRental & updatePropertyRental)', () {
      test('updateRental saves changes to photos, legal terms, and pricing while preserving immutable metadata and charging zero fees', () async {
        final originalCreatedAt = DateTime(2026, 1, 15, 10, 30).millisecondsSinceEpoch;
        firestore.db['users/host_edit'] = {
          'name': 'Original Host',
          'tyxBalance': 500.0,
        };
        firestore.db['rentals/vehicle_edit_1'] = {
          'id': 'vehicle_edit_1',
          'hostId': 'host_edit',
          'hostName': 'Original Host',
          'hostPhotoUrl': 'https://img.bb/host.jpg',
          'brand': 'Toyota',
          'model': 'Vios',
          'year': 2022,
          'type': 'car',
          'plateNumber': 'NBC 1234',
          'priceDaily': 2000.0,
          'interiorPhotoUrl': 'https://img.bb/orig_int.jpg',
          'frontPhotoUrl': 'https://img.bb/orig_front.jpg',
          'backPhotoUrl': 'https://img.bb/orig_back.jpg',
          'extraPhotos': <String>[],
          'contractType': 'tranyx',
          'contractTerms': 'Original Terms',
          'status': 'Available',
          'acceptingBookings': true,
          'listingFeePaid': 30.0,
          'isListingFeeWaived': false,
          'createdAt': originalCreatedAt,
        };

        final updatedRental = VehicleRental(
          id: 'vehicle_edit_1',
          hostId: 'host_edit',
          hostName: 'Attempted Changed Name',
          brand: 'Toyota',
          model: 'Vios GR-S',
          year: 2023,
          type: VehicleType.car,
          plateNumber: 'NBC 1234',
          vehicleValue: 950000.0,
          ltoCrNumber: 'CR-UPDATED',
          ltoOrNumber: 'OR-UPDATED',
          insuranceProvider: 'AXA Philippines',
          insurancePolicyNumber: 'POL-UPDATED',
          interiorPhotoUrl: 'https://img.bb/orig_int.jpg', // Retained existing photo
          frontPhotoUrl: 'https://img.bb/new_front.jpg', // Newly uploaded photo
          backPhotoUrl: 'https://img.bb/orig_back.jpg', // Retained existing photo
          contractType: 'custom',
          contractTerms: 'Updated Custom Legal Terms',
          price12h: 1500.0,
          priceDaily: 2500.0,
          priceWeekly: 15000.0,
          priceMonthly: 50000.0,
          extensionRatePerHour: 200.0,
          latePenaltyRatePerHour: 400.0,
          status: 'Available',
          pickupAddress: 'Makati CBD',
          pickupLat: 14.5547,
          pickupLng: 121.0244,
          createdAt: DateTime.now(),
        );

        final payload = updatedRental.toMap()
          ..['extraPhotos'] = ['https://img.bb/extra_1.jpg'];
        await repo.updateRental('vehicle_edit_1', payload);

        final saved = firestore.db['rentals/vehicle_edit_1']!;
        expect(saved['model'], equals('Vios GR-S'));
        expect(saved['year'], equals(2023));
        expect(saved['priceDaily'], equals(2500.0));
        expect(saved['interiorPhotoUrl'], equals('https://img.bb/orig_int.jpg'));
        expect(saved['frontPhotoUrl'], equals('https://img.bb/new_front.jpg'));
        expect(saved['backPhotoUrl'], equals('https://img.bb/orig_back.jpg'));
        expect(saved['extraPhotos'], equals(['https://img.bb/extra_1.jpg']));
        expect(saved['contractType'], equals('custom'));
        expect(saved['contractTerms'], equals('Updated Custom Legal Terms'));

        // Immutable fields preserved
        expect(saved['hostId'], equals('host_edit'));
        expect(saved['hostName'], equals('Original Host'));
        expect(saved['hostPhotoUrl'], equals('https://img.bb/host.jpg'));
        expect(saved['createdAt'], equals(originalCreatedAt));
        expect(saved['status'], equals('Available'));
        expect(saved['acceptingBookings'], isTrue);
        expect(saved['listingFeePaid'], equals(30.0));

        // Null keys stripped from update payload
        expect(saved.containsKey('renteeId'), isFalse);

        // Free edit: Host wallet balance unchanged
        expect(firestore.db['users/host_edit']!['tyxBalance'], equals(500.0));
      });

      test('updateRental allows editing when status is Not Accepting Bookings and preserves paused status', () async {
        firestore.db['rentals/vehicle_paused'] = {
          'id': 'vehicle_paused',
          'hostId': 'host_edit',
          'hostName': 'Original Host',
          'brand': 'Honda',
          'model': 'City',
          'status': 'Not Accepting Bookings',
          'acceptingBookings': false,
          'createdAt': 1700000000000,
        };

        final updatedRental = VehicleRental(
          id: 'vehicle_paused',
          hostId: 'host_edit',
          hostName: 'Original Host',
          brand: 'Honda',
          model: 'City RS',
          year: 2024,
          type: VehicleType.car,
          plateNumber: 'XYZ 999',
          vehicleValue: 1000000.0,
          ltoCrNumber: 'CR1',
          ltoOrNumber: 'OR1',
          insuranceProvider: 'Prudential',
          insurancePolicyNumber: 'P1',
          interiorPhotoUrl: 'https://img.bb/i.jpg',
          frontPhotoUrl: 'https://img.bb/f.jpg',
          backPhotoUrl: 'https://img.bb/b.jpg',
          contractType: 'tranyx',
          contractTerms: 'Terms',
          price12h: 1200.0,
          priceDaily: 2200.0,
          priceWeekly: 12000.0,
          priceMonthly: 40000.0,
          extensionRatePerHour: 150.0,
          latePenaltyRatePerHour: 300.0,
          status: 'Available',
          pickupAddress: 'BGC',
          pickupLat: 14.5,
          pickupLng: 121.0,
          createdAt: DateTime.now(),
        );

        await repo.updateRental('vehicle_paused', updatedRental.toMap());

        final saved = firestore.db['rentals/vehicle_paused']!;
        expect(saved['model'], equals('City RS'));
        expect(saved['status'], equals('Not Accepting Bookings'));
        expect(saved['acceptingBookings'], isFalse);
      });

      test('updateRental rejects editing when vehicle is actively Booked or Rented', () async {
        firestore.db['rentals/vehicle_booked'] = {
          'id': 'vehicle_booked',
          'hostId': 'host_edit',
          'hostName': 'Original Host',
          'status': 'Booked',
        };

        final updatedRental = VehicleRental(
          id: 'vehicle_booked',
          hostId: 'host_edit',
          hostName: 'Original Host',
          brand: 'Honda',
          model: 'City RS',
          year: 2024,
          type: VehicleType.car,
          plateNumber: 'XYZ 999',
          vehicleValue: 1000000.0,
          ltoCrNumber: 'CR1',
          ltoOrNumber: 'OR1',
          insuranceProvider: 'Prudential',
          insurancePolicyNumber: 'P1',
          interiorPhotoUrl: 'https://img.bb/i.jpg',
          frontPhotoUrl: 'https://img.bb/f.jpg',
          backPhotoUrl: 'https://img.bb/b.jpg',
          contractType: 'tranyx',
          contractTerms: 'Terms',
          price12h: 1200.0,
          priceDaily: 2200.0,
          priceWeekly: 12000.0,
          priceMonthly: 40000.0,
          extensionRatePerHour: 150.0,
          latePenaltyRatePerHour: 300.0,
          status: 'Booked',
          pickupAddress: 'BGC',
          pickupLat: 14.5,
          pickupLng: 121.0,
          createdAt: DateTime.now(),
        );

        expect(
          () => repo.updateRental('vehicle_booked', updatedRental.toMap()),
          throwsA(isA<Exception>()),
        );
      });

      test('updatePropertyRental saves changes to photos and legal terms while preserving immutable metadata', () async {
        final originalCreatedAt = DateTime(2026, 2, 1, 8, 0).millisecondsSinceEpoch;
        firestore.db['properties/prop_edit_1'] = {
          'id': 'prop_edit_1',
          'hostId': 'host_prop',
          'hostName': 'Property Host',
          'hostPhotoUrl': 'https://img.bb/host_p.jpg',
          'title': 'Old Title',
          'status': 'Available',
          'acceptingBookings': true,
          'createdAt': originalCreatedAt,
        };

        final updatedProp = PropertyRental(
          id: 'prop_edit_1',
          hostId: 'host_prop',
          hostName: 'Changed Host',
          title: 'Updated Luxury Loft',
          description: 'Renovated unit',
          type: PropertyType.condo,
          category: PropertyCategory.residential,
          priceMonthly: 45000.0,
          priceWeekly: 14000.0,
          priceDaily: 3000.0,
          depositMonths: 2,
          address: 'Rockwell, Makati',
          latitude: 14.5650,
          longitude: 121.0360,
          photoUrls: ['https://img.bb/existing.jpg', 'https://img.bb/new_photo.jpg'],
          amenities: ['WiFi', 'Gym', 'Pool'],
          status: 'Available',
          contractType: 'custom',
          contractTerms: 'Updated Lease Agreement',
          createdAt: DateTime.now(),
        );

        await repo.updatePropertyRental('prop_edit_1', updatedProp);

        final saved = firestore.db['properties/prop_edit_1']!;
        expect(saved['title'], equals('Updated Luxury Loft'));
        expect(saved['photoUrls'], equals(['https://img.bb/existing.jpg', 'https://img.bb/new_photo.jpg']));
        expect(saved['contractType'], equals('custom'));
        expect(saved['contractTerms'], equals('Updated Lease Agreement'));
        expect(saved['hostId'], equals('host_prop'));
        expect(saved['hostName'], equals('Property Host'));
        expect(saved['hostPhotoUrl'], equals('https://img.bb/host_p.jpg'));
        expect(saved['createdAt'], equals(originalCreatedAt));
        expect(saved.containsKey('renteeId'), isFalse);
      });
    });
  });
}

