import 'dart:math' show min;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';

class TransitRepository {
  final FirebaseFirestore _firestore;

  TransitRepository(this._firestore);

  // ─── Helper for User Balances ───────────────────────────────────────────
  Future<UserProfile?> getUser(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromMap(uid, doc.data()!);
  }

  Future<void> updateTyxBalance(String uid, double balance) async {
    await _firestore.collection('users').doc(uid).update({'tyxBalance': balance});
  }

  Future<void> createNotification({
    required String uid,
    required String title,
    required String message,
  }) async {
    final docId = 'notif_${DateTime.now().millisecondsSinceEpoch}_${uid.substring(0, min(5, uid.length))}';
    await _firestore.collection('notifications').doc(docId).set({
      'uid': uid,
      'title': title,
      'message': message,
      'isRead': false,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ─── Vehicle Rentals ───────────────────────────────────────────────────
  Future<String> createRental(VehicleRental rental) async {
    final host = await getUser(rental.hostId);
    if (host == null) throw Exception('Host profile not found.');

    final listingFee = 0.015 * rental.priceDaily;
    if (host.tyxBalance < listingFee) {
      throw Exception(
        'Insufficient balance. Listing fee requires ${listingFee.toStringAsFixed(2)} TYXBIT, but your balance is ${host.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Deduct listing fee
    await updateTyxBalance(rental.hostId, host.tyxBalance - listingFee);

    // Save transaction record
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': rental.hostId,
      'type': 'listing_fee',
      'amount': listingFee,
      'title': 'Vehicle Listing Fee',
      'desc': '1.5% posting fee for ${rental.brand} ${rental.model} (${rental.year})',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Save rental document
    final docRef = _firestore.collection('rentals').doc();
    final updatedRental = rental.toMap()..['id'] = docRef.id;
    await docRef.set(updatedRental);
    return docRef.id;
  }

  Future<String> createRentalFromMap(Map<String, dynamic> rentalMap) async {
    final hostId = rentalMap['hostId'] as String;
    final priceDaily = (rentalMap['priceDaily'] as num?)?.toDouble() ?? 0.0;
    final brand = rentalMap['brand'] as String? ?? '';
    final model = rentalMap['model'] as String? ?? '';
    final year = rentalMap['year']?.toString() ?? '';

    final host = await getUser(hostId);
    if (host == null) throw Exception('Host profile not found.');

    final listingFee = 0.015 * priceDaily;
    if (host.tyxBalance < listingFee) {
      throw Exception(
        'Insufficient balance. Listing fee requires ${listingFee.toStringAsFixed(2)} TYXBIT, but your balance is ${host.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Deduct listing fee
    await updateTyxBalance(hostId, host.tyxBalance - listingFee);

    // Save transaction record
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': hostId,
      'type': 'listing_fee',
      'amount': listingFee,
      'title': 'Vehicle Listing Fee',
      'desc': '1.5% posting fee for $brand $model ($year)',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Save rental document
    final docRef = _firestore.collection('rentals').doc();
    final updatedRental = Map<String, dynamic>.from(rentalMap)
      ..['id'] = docRef.id
      ..['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    await docRef.set(updatedRental);
    return docRef.id;
  }

  Future<void> deleteRental(String rentalId) async {
    final doc = await _firestore.collection('rentals').doc(rentalId).get();
    if (!doc.exists) throw Exception('Rental listing not found.');

    final data = doc.data()!;
    if (data['status'] != 'Available') {
      throw Exception('Cannot delete a vehicle listing that is currently booked or active.');
    }

    final rental = VehicleRental.fromMap(data, rentalId);

    // Reject all pending requests
    final requests = await _firestore
        .collection('rental_requests')
        .where('rentalId', isEqualTo: rentalId)
        .where('status', isEqualTo: 'Pending')
        .get();

    for (final r in requests.docs) {
      await rejectBookingRequest(r.id);
    }

    // Refund listing fee (1.5% of daily price) to host
    final host = await getUser(rental.hostId);
    final listingFee = 0.015 * rental.priceDaily;
    if (host != null && listingFee > 0.0) {
      await updateTyxBalance(rental.hostId, host.tyxBalance + listingFee);
      final txId = 'refund_veh_$rentalId';
      await _firestore.collection('transactions').doc(txId).set({
        'id': txId,
        'uid': rental.hostId,
        'type': 'refund',
        'category': 'refund',
        'amount': listingFee,
        'title': 'Vehicle Listing Fee Refund',
        'desc': '100% refund of listing fee for cancelled vehicle "${rental.year} ${rental.brand} ${rental.model}"',
        'method': 'Tranyx Wallet',
        'originRail': 'internal_balance',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'status': 'Completed',
      });
    }

    await _firestore.collection('rentals').doc(rentalId).delete();
  }

  Stream<List<VehicleRental>> getRealtimeRentals() {
    return _firestore
        .collection('rentals')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => VehicleRental.fromMap(doc.data(), doc.id)).toList());
  }

  Future<void> createBookingRequest({
    required String rentalId,
    required String renteeId,
    required String renteeName,
    required String? renteePhotoUrl,
    required String durationType,
    required int multiplier,
    String? licenseNumber,
    required double totalCost,
    required bool hireWithDriver,
    required String rentalType,
    required String? deliveryAddress,
    double? deliveryLat,
    double? deliveryLng,
    required int startDate,
    required int endDate,
    String? promoCode,
    double? discountAmount,
  }) async {
    final doc = await _firestore.collection('rentals').doc(rentalId).get();
    if (!doc.exists) throw Exception('Rental listing not found.');

    final rental = VehicleRental.fromMap(doc.data()!, rentalId);
    if (rental.status != 'Available') throw Exception('Vehicle is no longer available.');

    final rentee = await getUser(renteeId);
    if (rentee == null) throw Exception('Renter profile not found.');

    final discount = discountAmount ?? 0.0;
    final discountedTotalCost = (totalCost - discount).clamp(0.0, 999999.0);
    final bookingFee = discountedTotalCost * 0.03;
    final totalRequired = discountedTotalCost + bookingFee;

    if (rentee.tyxBalance < totalRequired) {
      throw Exception(
        'Insufficient balance. Required: ${totalRequired.toStringAsFixed(2)} TYXBIT (including 3% booking fee), but available: ${rentee.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Deduct balance
    await updateTyxBalance(renteeId, rentee.tyxBalance - totalRequired);

    // Transaction record
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': renteeId,
      'type': 'payment',
      'amount': totalRequired,
      'title': 'Vehicle Booking Request',
      'desc': 'Requested ${rental.brand} ${rental.model} for $multiplier $durationType(s)${promoCode != null ? ' (Promo $promoCode applied)' : ''}',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Save request document
    final requestId = 'req_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('rental_requests').doc(requestId).set({
      'id': requestId,
      'rentalId': rentalId,
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': renteePhotoUrl ?? '',
      'durationType': durationType,
      'multiplier': multiplier,
      'totalCost': totalCost,
      'bookingFee': bookingFee,
      'signatureName': '',
      'licenseNumber': licenseNumber,
      'hireWithDriver': hireWithDriver,
      'status': 'Pending',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'hostId': rental.hostId,
      'brand': rental.brand,
      'model': rental.model,
      'year': rental.year,
      'rentalType': rentalType,
      'deliveryAddress': deliveryAddress ?? '',
      'deliveryLat': deliveryLat,
      'deliveryLng': deliveryLng,
      'startDate': startDate,
      'endDate': endDate,
      'promoCode': ?promoCode,
      if (promoCode != null) 'discountAmount': discount,
    });

    // Save request escrow
    await _firestore.collection('rental_escrows').doc(requestId).set({
      'requestId': requestId,
      'rentalId': rentalId,
      'renteeId': renteeId,
      'hostId': rental.hostId,
      'amount': discountedTotalCost,
      'status': 'Held',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Increment promo usage
    if (promoCode != null && promoCode.trim().isNotEmpty) {
      await incrementPromoUsage(promoCode, renteeId);
    }

    // Notify host
    await createNotification(
      uid: rental.hostId,
      title: 'Booking Request Received',
      message: '$renteeName wants to book your ${rental.brand} ${rental.model}.',
    );
  }

  Future<void> approveBookingRequest(String requestId, String rentalId, bool allowChat) async {
    final reqDoc = await _firestore.collection('rental_requests').doc(requestId).get();
    if (!reqDoc.exists) throw Exception('Booking request not found.');
    
    final reqData = reqDoc.data()!;
    if (reqData['status'] != 'Pending') throw Exception('Request is already processed.');

    final rentalDoc = await _firestore.collection('rentals').doc(rentalId).get();
    if (!rentalDoc.exists) throw Exception('Rental listing not found.');

    final rental = VehicleRental.fromMap(rentalDoc.data()!, rentalId);
    if (rental.status != 'Available') throw Exception('Vehicle is no longer available (already booked).');

    final renteeId = reqData['renteeId'] as String;
    final renteeName = reqData['renteeName'] as String;
    final durationType = reqData['durationType'] as String;
    final multiplier = (reqData['multiplier'] as num).toInt();
    final totalCost = (reqData['totalCost'] as num).toDouble();
    final hireWithDriver = reqData['hireWithDriver'] as bool? ?? false;
    final rentalType = reqData['rentalType'] as String? ?? 'pickup';
    final deliveryAddress = reqData['deliveryAddress'] as String? ?? '';
    final startDate = (reqData['startDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final endDate = (reqData['endDate'] as num?)?.toInt() ?? DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;

    // Approve this request
    await _firestore.collection('rental_requests').doc(requestId).update({'status': 'Approved'});

    // Move escrow
    final reqEscrowDoc = await _firestore.collection('rental_escrows').doc(requestId).get();
    final reqBookingFee = (reqData['bookingFee'] as num? ?? totalCost * 0.03).toDouble();
    if (reqEscrowDoc.exists) {
      await _firestore.collection('rental_escrows').doc(rentalId).set({
        'rentalId': rentalId,
        'renteeId': renteeId,
        'hostId': rental.hostId,
        'amount': totalCost,
        'bookingFee': reqBookingFee,
        'totalPaid': totalCost + reqBookingFee,
        'status': 'Held',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      await _firestore.collection('rental_escrows').doc(requestId).delete();
    }

    // Update rental doc
    await _firestore.collection('rentals').doc(rentalId).update({
      'status': 'Awaiting Signature',
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': reqData['renteePhotoUrl'] ?? '',
      'rentalDurationType': durationType,
      'rentalMultiplier': multiplier,
      'startDate': startDate,
      'endDate': endDate,
      'totalCost': totalCost,
      'bookingFee': reqBookingFee,
      'renteeSignatureName': '',
      'signedAt': 0,
      'currentRequestId': requestId,
      'allowChat': allowChat,
      'hireWithDriver': hireWithDriver,
      'rentalType': rentalType,
      'deliveryAddress': deliveryAddress,
      'renteeLicenseNumber': reqData['licenseNumber'] ?? '',
    });

    // Reject other requests for same vehicle
    final otherRequests = await _firestore
        .collection('rental_requests')
        .where('rentalId', isEqualTo: rentalId)
        .where('status', isEqualTo: 'Pending')
        .get();

    for (final otherReq in otherRequests.docs) {
      if (otherReq.id == requestId) continue;
      await rejectBookingRequest(otherReq.id);
    }

    // Notify Renter
    await createNotification(
      uid: renteeId,
      title: 'Booking Approved',
      message: 'Your booking request for ${rental.brand} ${rental.model} was approved. Please sign the contract.',
    );
  }

  Future<void> rejectBookingRequest(String requestId) async {
    final doc = await _firestore.collection('rental_requests').doc(requestId).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    if (data['status'] != 'Pending') return;

    final renteeId = data['renteeId'] as String;
    final totalCost = (data['totalCost'] as num).toDouble();
    final bookingFee = (data['bookingFee'] as num? ?? totalCost * 0.03).toDouble();
    final refundAmount = totalCost + bookingFee;

    await _firestore.collection('rental_requests').doc(requestId).update({'status': 'Rejected'});

    final rentee = await getUser(renteeId);
    if (rentee != null) {
      await updateTyxBalance(renteeId, rentee.tyxBalance + refundAmount);

      final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
      await _firestore.collection('transactions').doc(txId).set({
        'uid': renteeId,
        'type': 'refund',
        'amount': refundAmount,
        'title': 'Booking Request Rejected',
        'desc': 'Refund for rejected request of ${data['brand']} ${data['model']}',
        'method': 'Tranyx Wallet',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    await _firestore.collection('rental_escrows').doc(requestId).delete();

    await createNotification(
      uid: renteeId,
      title: 'Booking Request Rejected',
      message: 'Your request to book ${data['brand']} ${data['model']} was rejected. Funds have been refunded.',
    );
  }

  Future<void> cancelBookingRequest(String requestId) async {
    final doc = await _firestore.collection('rental_requests').doc(requestId).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    if (data['status'] != 'Pending') return;

    final renteeId = data['renteeId'] as String;
    final totalCost = (data['totalCost'] as num).toDouble();
    final bookingFee = (data['bookingFee'] as num? ?? totalCost * 0.03).toDouble();
    final refundAmount = totalCost + bookingFee;

    await _firestore.collection('rental_requests').doc(requestId).update({'status': 'Cancelled'});

    final rentee = await getUser(renteeId);
    if (rentee != null) {
      await updateTyxBalance(renteeId, rentee.tyxBalance + refundAmount);

      final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
      await _firestore.collection('transactions').doc(txId).set({
        'uid': renteeId,
        'type': 'refund',
        'amount': refundAmount,
        'title': 'Booking Request Cancelled',
        'desc': 'Refund for cancelled request of ${data['brand']} ${data['model']}',
        'method': 'Tranyx Wallet',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    await _firestore.collection('rental_escrows').doc(requestId).delete();
  }

  Future<void> signVehicleContract(String rentalId, String signatureDataUrl, {String? signatureHash}) async {
    final doc = await _firestore.collection('rentals').doc(rentalId).get();
    if (!doc.exists) throw Exception('Rental listing not found.');

    final data = doc.data()!;
    final now = DateTime.now();

    await _firestore.collection('rentals').doc(rentalId).update({
      'status': 'Booked',
      'renteeSignatureName': signatureDataUrl,
      'signedAt': now.millisecondsSinceEpoch,
      'signatureHash': signatureHash ?? '',
    });

    final hostId = data['hostId'] as String;
    final renteeName = data['renteeName'] as String? ?? 'Renter';
    final brand = data['brand'] ?? '';
    final model = data['model'] ?? '';

    await createNotification(
      uid: hostId,
      title: 'Contract Signed',
      message: '$renteeName has signed the contract for your vehicle $brand $model. Booking is now active and ready for handover.',
    );
  }

  Future<void> updateRentalStatus(String rentalId, String status) async {
    await _firestore.collection('rentals').doc(rentalId).update({'status': status});

    final doc = await _firestore.collection('rentals').doc(rentalId).get();
    if (doc.exists) {
      final rental = VehicleRental.fromMap(doc.data()!, rentalId);
      if (rental.renteeId != null) {
        await createNotification(
          uid: rental.renteeId!,
          title: 'Rental Status Update',
          message: 'Your rental for ${rental.brand} ${rental.model} is now: $status.',
        );
      }
      await createNotification(
        uid: rental.hostId,
        title: 'Rental Status Update',
        message: 'Your vehicle ${rental.brand} ${rental.model} is now: $status.',
      );
    }
  }

  Future<void> updateRentalTracking(String rentalId, double lat, double lng) async {
    await _firestore.collection('rentals').doc(rentalId).update({
      'trackingLat': lat,
      'trackingLng': lng,
    });
  }

  Future<void> completeRental(String rentalId) async {
    final doc = await _firestore.collection('rentals').doc(rentalId).get();
    if (!doc.exists) throw Exception('Rental listing not found.');

    final rental = VehicleRental.fromMap(doc.data()!, rentalId);
    final host = await getUser(rental.hostId);
    if (host == null) throw Exception('Host profile not found.');

    final escrowDoc = await _firestore.collection('rental_escrows').doc(rentalId).get();
    if (!escrowDoc.exists) throw Exception('Escrow transaction not found.');
    if (escrowDoc.data()!['status'] != 'Held') throw Exception('Escrow is not in Held status.');

    final cost = rental.totalCost ?? 0.0;
    final commission = cost * 0.03;
    final hostPayout = cost - commission;

    await updateTyxBalance(rental.hostId, host.tyxBalance + hostPayout);

    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': rental.hostId,
      'type': 'payment',
      'amount': hostPayout,
      'baseAmount': cost,
      'commissionFee': commission,
      'commissionLabel': 'Platform Commission (3%)',
      'title': 'Rental Earnings Payout',
      'desc': 'Payout for rental ${rental.brand} ${rental.model} (3% platform commission of ${commission.toStringAsFixed(2)} TYXBIT deducted)',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    await _firestore.collection('rental_escrows').doc(rentalId).update({
      'status': 'Released',
      'releasedAt': DateTime.now().millisecondsSinceEpoch,
    });

    final historyId = 'rh_${DateTime.now().microsecondsSinceEpoch}';
    final historyDoc = {
      ...doc.data()!,
      'status': 'Completed',
      'completedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _firestore.collection('rental_history').doc(historyId).set(historyDoc);

    await awardPointsIfEligible(rental.hostId, 'host_complete_transaction');
    if (rental.renteeId != null && rental.renteeId!.isNotEmpty) {
      await awardPointsIfEligible(rental.renteeId!, 'client_complete_transaction');
    }

    await _firestore.collection('rentals').doc(rentalId).update({
      'status': 'Available',
      'renteeId': '',
      'renteeName': '',
      'renteePhotoUrl': '',
      'rentalDurationType': '',
      'rentalMultiplier': 0,
      'startDate': 0,
      'endDate': 0,
      'totalCost': 0.0,
      'renteeSignatureName': '',
      'renteeLicenseNumber': '',
      'signedAt': 0,
      'trackingLat': 0.0,
      'trackingLng': 0.0,
    });

    await createNotification(
      uid: rental.hostId,
      title: 'Rental Completed & Paid',
      message: 'Rental for ${rental.brand} completed. Payout of ${hostPayout.toStringAsFixed(2)} TYXBIT credited to your wallet.',
    );

    if (rental.renteeId != null && rental.renteeId!.isNotEmpty) {
      await createNotification(
        uid: rental.renteeId!,
        title: 'Rental Completed',
        message: 'Your rental for ${rental.brand} has been successfully completed. Thank you!',
      );
    }
  }

  Future<PlatformFeeConfig> getPlatformFeeConfig() async {
    try {
      final doc = await _firestore.collection('settings').doc('platform_fees').get();
      if (doc.exists && doc.data() != null) {
        return PlatformFeeConfig.fromMap(doc.data()!);
      }
    } catch (_) {}
    return const PlatformFeeConfig();
  }

  // ─── Property Rentals ──────────────────────────────────────────────────
  Future<String> createPropertyRental(PropertyRental property) async {
    final host = await getUser(property.hostId);
    if (host == null) throw Exception('Host profile not found.');

    // 0% Free property listing (₱0.00 upfront fee)
    final docRef = _firestore.collection('properties').doc();
    final updatedPropMap = property.toMap()
      ..['id'] = docRef.id
      ..['isListingFeeWaived'] = true
      ..['status'] = 'Available';
    await docRef.set(updatedPropMap);
    await awardPointsIfEligible(property.hostId, 'post_property');
    return docRef.id;
  }

  Future<void> deletePropertyRental(String propertyId) async {
    final doc = await _firestore.collection('properties').doc(propertyId).get();
    if (!doc.exists) throw Exception('Property listing not found.');

    final property = PropertyRental.fromMap(doc.data()!, propertyId);
    if (property.status != 'Available') {
      throw Exception('Cannot delete a property listing that is currently booked or active.');
    }

    final pending = await _firestore
        .collection('property_requests')
        .where('propertyId', isEqualTo: propertyId)
        .where('status', isEqualTo: 'Pending')
        .get();

    for (final r in pending.docs) {
      await rejectPropertyBookingRequest(r.id);
    }

    // Only refund listing fee if a fee was actually paid (listingFee > 0 and not waived)
    final host = await getUser(property.hostId);
    final listingFee = property.isListingFeeWaived == true ? 0.0 : (0.015 * property.priceMonthly);
    if (host != null && listingFee > 0.0) {
      await updateTyxBalance(property.hostId, host.tyxBalance + listingFee);
      final txId = 'refund_prop_$propertyId';
      await _firestore.collection('transactions').doc(txId).set({
        'id': txId,
        'uid': property.hostId,
        'type': 'refund',
        'category': 'refund',
        'amount': listingFee,
        'title': 'Property Listing Fee Refund',
        'desc': '100% refund of listing fee for cancelled property "${property.title}"',
        'method': 'Tranyx Wallet',
        'originRail': 'internal_balance',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'status': 'Completed',
      });
    }

    await _firestore.collection('properties').doc(propertyId).delete();
  }

  Future<void> updatePropertyRental(String propertyId, PropertyRental updatedProperty) async {
    final doc = await _firestore.collection('properties').doc(propertyId).get();
    if (!doc.exists) throw Exception('Property listing not found.');

    final existing = PropertyRental.fromMap(doc.data()!, propertyId);
    if (existing.status != 'Available' || (existing.renteeId != null && existing.renteeId!.isNotEmpty)) {
      throw Exception('Cannot edit a property listing that is currently booked or active.');
    }

    final pending = await _firestore
        .collection('property_requests')
        .where('propertyId', isEqualTo: propertyId)
        .where('status', isEqualTo: 'Pending')
        .get();

    if (pending.docs.isNotEmpty) {
      throw Exception('Cannot edit property listing while pending booking requests exist. Please review or reject pending requests first.');
    }

    final updatedMap = updatedProperty.toMap()
      ..['id'] = propertyId
      ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _firestore.collection('properties').doc(propertyId).update(updatedMap);
  }

  Future<void> updateRental(String rentalId, Map<String, dynamic> updatedData) async {
    final doc = await _firestore.collection('rentals').doc(rentalId).get();
    if (!doc.exists) throw Exception('Rental listing not found.');

    final existing = doc.data()!;
    if (existing['status'] != 'Available' || (existing['renteeId'] != null && (existing['renteeId'] as String).isNotEmpty)) {
      throw Exception('Cannot edit a vehicle listing that is currently booked or active.');
    }

    final copy = Map<String, dynamic>.from(updatedData)
      ..['id'] = rentalId
      ..['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    await _firestore.collection('rentals').doc(rentalId).update(copy);
  }

  Stream<List<PropertyRental>> getRealtimeProperties() {
    return _firestore
        .collection('properties')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => PropertyRental.fromMap(doc.data(), doc.id)).toList());
  }

  Future<void> createPropertyBookingRequest({
    required String propertyId,
    required String renteeId,
    required String renteeName,
    required String? renteePhotoUrl,
    required String durationType,
    required int multiplier,
    required double totalCost,
    double? baseRentAmount,
    double? securityDepositAmount,
    double? customerPlatformFeeRate,
    double? hostCommissionRate,
    required String contractType,
    required String contractTerms,
    required int startDate,
    required int endDate,
    String? licenseNumber,
    String? promoCode,
    double? discountAmount,
  }) async {
    final doc = await _firestore.collection('properties').doc(propertyId).get();
    if (!doc.exists) throw Exception('Property listing not found.');

    final property = PropertyRental.fromMap(doc.data()!, propertyId);
    if (property.status != 'Available') throw Exception('Property is no longer available.');

    final rentee = await getUser(renteeId);
    if (rentee == null) throw Exception('Renter profile not found.');

    final feeConfig = await getPlatformFeeConfig();
    final custFeeRate = customerPlatformFeeRate ?? feeConfig.propertyCustomerFeeRate;
    final hostCommRate = hostCommissionRate ?? feeConfig.propertyHostCommissionRate;

    // Calculate duration in days
    int totalDays = multiplier;
    if (durationType.toLowerCase() == 'daily') {
      totalDays = multiplier * 1;
    } else if (durationType.toLowerCase() == 'weekly') {
      totalDays = multiplier * 7;
    } else if (durationType.toLowerCase() == 'monthly') {
      totalDays = multiplier * 30;
    }

    final pricingModel = PropertyPricingModel.fromPropertyMap(property.toMap());
    final financials = pricingModel.calculate(
      totalDays: totalDays,
      customerPlatformFeeRate: custFeeRate,
      hostCommissionRate: hostCommRate,
    );

    final finalBaseRent = baseRentAmount ?? financials.baseRent;
    final finalDeposit = securityDepositAmount ?? financials.securityDeposit;
    final discount = discountAmount ?? 0.0;
    final originalCustFee = financials.customerPlatformFee;
    final finalCustFee = (originalCustFee - discount).clamp(0.0, 999999.0);
    final totalCustomerPaid = finalBaseRent + finalCustFee + finalDeposit;

    if (rentee.tyxBalance < totalCustomerPaid) {
      throw Exception(
        'Insufficient balance. Required: ₱${totalCustomerPaid.toStringAsFixed(2)} (Rent ₱${finalBaseRent.toStringAsFixed(2)} + ${PlatformFeeConfig.formatPercent(custFeeRate)} fee ₱${finalCustFee.toStringAsFixed(2)}${finalDeposit > 0 ? " + Deposit ₱${finalDeposit.toStringAsFixed(2)}" : ""}), but available: ₱${rentee.tyxBalance.toStringAsFixed(2)}.',
      );
    }

    await updateTyxBalance(renteeId, rentee.tyxBalance - totalCustomerPaid);

    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': renteeId,
      'type': 'payment',
      'amount': totalCustomerPaid,
      'baseRentAmount': finalBaseRent,
      'securityDepositAmount': finalDeposit,
      'customerPlatformFeeRate': custFeeRate,
      'customerPlatformFeeAmount': finalCustFee,
      'hostCommissionRate': hostCommRate,
      'totalCustomerPaid': totalCustomerPaid,
      'title': 'Property Booking Request',
      'desc': 'Requested property "${property.title}" for $multiplier $durationType(s)${promoCode != null ? ' (Promo $promoCode applied)' : ''}',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    final requestId = 'req_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('property_requests').doc(requestId).set({
      'id': requestId,
      'propertyId': propertyId,
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': renteePhotoUrl ?? '',
      'durationType': durationType,
      'multiplier': multiplier,
      'totalCost': totalCost,
      'baseRentAmount': finalBaseRent,
      'securityDepositAmount': finalDeposit,
      'customerPlatformFeeRate': custFeeRate,
      'customerPlatformFeeAmount': finalCustFee,
      'hostCommissionRate': hostCommRate,
      'totalCustomerPaid': totalCustomerPaid,
      'bookingFee': finalCustFee,
      'signatureName': '',
      'status': 'Pending',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'hostId': property.hostId,
      'title': property.title,
      'propertyType': property.type.name,
      'category': property.category.name,
      'contractType': contractType,
      'contractTerms': contractTerms,
      'startDate': startDate,
      'endDate': endDate,
      'licenseNumber': licenseNumber ?? '',
      'promoCode': promoCode,
      if (promoCode != null) 'discountAmount': discount,
    });

    await _firestore.collection('property_escrows').doc(requestId).set({
      'requestId': requestId,
      'propertyId': propertyId,
      'renteeId': renteeId,
      'hostId': property.hostId,
      'amount': totalCustomerPaid,
      'baseRentAmount': finalBaseRent,
      'securityDepositAmount': finalDeposit,
      'customerPlatformFeeRate': custFeeRate,
      'customerPlatformFeeAmount': finalCustFee,
      'hostCommissionRate': hostCommRate,
      'totalCustomerPaid': totalCustomerPaid,
      'status': 'Held',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Increment promo usage
    if (promoCode != null && promoCode.trim().isNotEmpty) {
      await incrementPromoUsage(promoCode, renteeId);
    }

    await createNotification(
      uid: property.hostId,
      title: 'Booking Request Received',
      message: '$renteeName wants to rent your property: "${property.title}".',
    );

    await awardPointsIfEligible(renteeId, 'rent_property');
  }

  Future<void> approvePropertyBookingRequest(String requestId, String propertyId, bool allowChat) async {
    final reqDoc = await _firestore.collection('property_requests').doc(requestId).get();
    if (!reqDoc.exists) throw Exception('Booking request not found.');

    final reqData = reqDoc.data()!;
    if (reqData['status'] != 'Pending') throw Exception('Request is already processed.');

    final propDoc = await _firestore.collection('properties').doc(propertyId).get();
    if (!propDoc.exists) throw Exception('Property listing not found.');

    final property = PropertyRental.fromMap(propDoc.data()!, propertyId);
    if (property.status != 'Available') throw Exception('Property is no longer available (already rented).');

    final renteeId = reqData['renteeId'] as String;
    final renteeName = reqData['renteeName'] as String;
    final durationType = reqData['durationType'] as String;
    final multiplier = (reqData['multiplier'] as num).toInt();
    final totalCost = (reqData['totalCost'] as num).toDouble();
    final baseRentAmount = (reqData['baseRentAmount'] as num?)?.toDouble() ?? totalCost;
    final securityDepositAmount = (reqData['securityDepositAmount'] as num?)?.toDouble() ?? 0.0;
    final customerPlatformFeeRate = (reqData['customerPlatformFeeRate'] as num?)?.toDouble() ?? 0.03;
    final customerPlatformFeeAmount = (reqData['customerPlatformFeeAmount'] as num?)?.toDouble() ?? (reqData['bookingFee'] as num?)?.toDouble() ?? (baseRentAmount * 0.03);
    final hostCommissionRate = (reqData['hostCommissionRate'] as num?)?.toDouble() ?? 0.07;
    final totalCustomerPaid = (reqData['totalCustomerPaid'] as num?)?.toDouble() ?? (baseRentAmount + customerPlatformFeeAmount + securityDepositAmount);
    final startDate = (reqData['startDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final endDate = (reqData['endDate'] as num?)?.toInt() ?? DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;

    await _firestore.collection('property_requests').doc(requestId).update({'status': 'Approved'});

    final reqEscrowDoc = await _firestore.collection('property_escrows').doc(requestId).get();
    if (reqEscrowDoc.exists) {
      await _firestore.collection('property_escrows').doc(propertyId).set({
        'propertyId': propertyId,
        'renteeId': renteeId,
        'hostId': property.hostId,
        'amount': totalCustomerPaid,
        'baseRentAmount': baseRentAmount,
        'securityDepositAmount': securityDepositAmount,
        'customerPlatformFeeRate': customerPlatformFeeRate,
        'customerPlatformFeeAmount': customerPlatformFeeAmount,
        'hostCommissionRate': hostCommissionRate,
        'totalPaid': totalCustomerPaid,
        'totalCustomerPaid': totalCustomerPaid,
        'bookingFee': customerPlatformFeeAmount,
        'status': 'Held',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      await _firestore.collection('property_escrows').doc(requestId).delete();
    }

    await _firestore.collection('properties').doc(propertyId).update({
      'status': 'Awaiting Signature',
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': reqData['renteePhotoUrl'] ?? '',
      'rentalDurationType': durationType,
      'rentalMultiplier': multiplier,
      'startDate': startDate,
      'endDate': endDate,
      'totalCost': totalCost,
      'baseRentAmount': baseRentAmount,
      'securityDepositAmount': securityDepositAmount,
      'customerPlatformFeeRate': customerPlatformFeeRate,
      'customerPlatformFeeAmount': customerPlatformFeeAmount,
      'hostCommissionRate': hostCommissionRate,
      'totalCustomerPaid': totalCustomerPaid,
      'bookingFee': customerPlatformFeeAmount,
      'renteeSignatureName': '',
      'signedAt': 0,
      'currentRequestId': requestId,
      'allowChat': allowChat,
      'licenseNumber': reqData['licenseNumber'] ?? '',
    });

    final allRequests = await _firestore
        .collection('property_requests')
        .where('propertyId', isEqualTo: propertyId)
        .where('status', isEqualTo: 'Pending')
        .get();

    for (final otherReq in allRequests.docs) {
      if (otherReq.id == requestId) continue;
      await rejectPropertyBookingRequest(otherReq.id);
    }
  }

  Future<void> rejectPropertyBookingRequest(String requestId) async {
    final doc = await _firestore.collection('property_requests').doc(requestId).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    if (data['status'] != 'Pending') return;

    final renteeId = data['renteeId'] as String;
    final totalCost = (data['totalCost'] as num).toDouble();
    final bookingFee = (data['bookingFee'] as num? ?? totalCost * 0.03).toDouble();
    final refundAmount = totalCost + bookingFee;

    await _firestore.collection('property_requests').doc(requestId).update({'status': 'Rejected'});

    final rentee = await getUser(renteeId);
    if (rentee != null) {
      await updateTyxBalance(renteeId, rentee.tyxBalance + refundAmount);

      final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
      await _firestore.collection('transactions').doc(txId).set({
        'uid': renteeId,
        'type': 'refund',
        'amount': refundAmount,
        'title': 'Property Booking Refund',
        'desc': 'Refund for rejected request of property "${data['title']}"',
        'method': 'Tranyx Wallet',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    await _firestore.collection('property_escrows').doc(requestId).delete();

    await createNotification(
      uid: renteeId,
      title: 'Booking Request Rejected',
      message: 'Your request to rent "${data['title']}" was rejected. Funds have been refunded.',
    );
  }

  Future<void> cancelPropertyBookingRequest(String requestId) async {
    final doc = await _firestore.collection('property_requests').doc(requestId).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    if (data['status'] != 'Pending') return;

    final renteeId = data['renteeId'] as String;
    final hostId = data['hostId'] as String;
    final totalCost = (data['totalCost'] as num).toDouble();
    final bookingFee = (data['bookingFee'] as num? ?? totalCost * 0.03).toDouble();
    final refundAmount = totalCost + bookingFee;

    await _firestore.collection('property_requests').doc(requestId).update({'status': 'Cancelled'});

    // Revert promo usage
    final promoCode = data['promoCode'] as String?;
    if (promoCode != null && promoCode.trim().isNotEmpty) {
      await decrementPromoUsage(promoCode, renteeId);
    }

    final rentee = await getUser(renteeId);
    if (rentee != null) {
      await updateTyxBalance(renteeId, rentee.tyxBalance + refundAmount);

      final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
      await _firestore.collection('transactions').doc(txId).set({
        'id': txId,
        'uid': renteeId,
        'type': 'refund',
        'category': 'refund',
        'amount': refundAmount,
        'title': 'Property Booking Cancelled',
        'desc': 'Refund for cancelled request of property "${data['title']}"',
        'method': 'Tranyx Wallet',
        'originRail': 'internal_balance',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'status': 'Completed',
      });
    }

    await _firestore.collection('property_escrows').doc(requestId).delete();

    await createNotification(
      uid: hostId,
      title: 'Property Booking Request Cancelled',
      message: '${data['renteeName'] ?? "Renter"} has cancelled their booking request for your property "${data['title']}".',
    );
  }

  Future<void> signPropertyContract(String propertyId, String signatureDataUrl, {String? signatureHash}) async {
    final doc = await _firestore.collection('properties').doc(propertyId).get();
    if (!doc.exists) throw Exception('Property listing not found.');

    final now = DateTime.now();
    await _firestore.collection('properties').doc(propertyId).update({
      'status': 'Booked',
      'renteeSignatureName': signatureDataUrl,
      'signedAt': now.millisecondsSinceEpoch,
      'signatureHash': signatureHash ?? '',
    });

    final data = doc.data()!;
    final hostId = data['hostId'] as String;
    final renteeName = data['renteeName'] as String? ?? 'Renter';
    final title = data['title'] ?? '';

    await createNotification(
      uid: hostId,
      title: 'Lease Agreement Signed',
      message: '$renteeName has signed the Lease Agreement for "$title". The lease is now active.',
    );
  }

  Future<void> updatePropertyStatus(String propertyId, String status) async {
    await _firestore.collection('properties').doc(propertyId).update({'status': status});

    final doc = await _firestore.collection('properties').doc(propertyId).get();
    if (doc.exists) {
      final property = PropertyRental.fromMap(doc.data()!, propertyId);
      if (property.renteeId != null) {
        await createNotification(
          uid: property.renteeId!,
          title: 'Lease Status Update',
          message: 'Your lease for "${property.title}" is now: $status.',
        );
      }
      await createNotification(
        uid: property.hostId,
        title: 'Lease Status Update',
        message: 'Your property "${property.title}" lease is now: $status.',
      );
    }
  }

  Future<void> completePropertyRental(String propertyId) async {
    final doc = await _firestore.collection('properties').doc(propertyId).get();
    if (!doc.exists) throw Exception('Property listing not found.');

    final property = PropertyRental.fromMap(doc.data()!, propertyId);
    final host = await getUser(property.hostId);
    if (host == null) throw Exception('Host profile not found.');

    final escrowDoc = await _firestore.collection('property_escrows').doc(propertyId).get();
    if (!escrowDoc.exists) throw Exception('Escrow transaction not found.');
    final escrowData = escrowDoc.data()!;
    if (escrowData['status'] != 'Held') throw Exception('Escrow is not in Held status.');

    final feeConfig = await getPlatformFeeConfig();
    final hostCommRate = (escrowData['hostCommissionRate'] as num?)?.toDouble() ??
        (doc.data()!['hostCommissionRate'] as num?)?.toDouble() ??
        feeConfig.propertyHostCommissionRate;

    final baseRent = (escrowData['baseRentAmount'] as num?)?.toDouble() ??
        (doc.data()!['baseRentAmount'] as num?)?.toDouble() ??
        property.totalCost ??
        0.0;

    final securityDeposit = (escrowData['securityDepositAmount'] as num?)?.toDouble() ??
        (doc.data()!['securityDepositAmount'] as num?)?.toDouble() ??
        0.0;

    final hostCommission = double.parse((baseRent * hostCommRate).toStringAsFixed(2));
    final hostPayout = double.parse((baseRent - hostCommission).toStringAsFixed(2));

    await updateTyxBalance(property.hostId, host.tyxBalance + hostPayout);

    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': property.hostId,
      'type': 'payment',
      'amount': hostPayout,
      'baseRentAmount': baseRent,
      'securityDepositAmount': securityDeposit,
      'hostCommissionRate': hostCommRate,
      'commissionFee': hostCommission,
      'commissionLabel': 'Host Success Commission (${PlatformFeeConfig.formatPercent(hostCommRate)})',
      'title': 'Property Rental Payout',
      'desc': 'Earnings payout for "${property.title}" (${PlatformFeeConfig.formatPercent(hostCommRate)} host commission of ₱${hostCommission.toStringAsFixed(2)} deducted from ₱${baseRent.toStringAsFixed(2)} base rent)',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    await _firestore.collection('property_escrows').doc(propertyId).update({
      'status': 'Released',
      'releasedAt': DateTime.now().millisecondsSinceEpoch,
      'hostCommissionRate': hostCommRate,
      'hostCommissionAmount': hostCommission,
      'hostPayoutAmount': hostPayout,
      'securityDepositRefunded': securityDeposit,
    });

    // Refund security deposit to rentee upon lease completion
    if (property.renteeId != null && property.renteeId!.isNotEmpty && securityDeposit > 0.0) {
      final rentee = await getUser(property.renteeId!);
      if (rentee != null) {
        await updateTyxBalance(property.renteeId!, rentee.tyxBalance + securityDeposit);
        final depTxId = 'dep_ref_${DateTime.now().microsecondsSinceEpoch}';
        await _firestore.collection('transactions').doc(depTxId).set({
          'uid': property.renteeId!,
          'type': 'refund',
          'category': 'refund',
          'amount': securityDeposit,
          'title': 'Security Deposit Refund',
          'desc': '100% refund of security deposit for completed lease "${property.title}"',
          'method': 'Tranyx Wallet',
          'originRail': 'internal_balance',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'status': 'Completed',
        });
      }
    }

    final historyId = 'ph_${DateTime.now().microsecondsSinceEpoch}';
    final historyDoc = {
      ...doc.data()!,
      'status': 'Completed',
      'completedAt': DateTime.now().millisecondsSinceEpoch,
      'hostCommissionRate': hostCommRate,
      'hostCommissionAmount': hostCommission,
      'hostPayoutAmount': hostPayout,
      'securityDepositRefunded': securityDeposit,
    };
    await _firestore.collection('property_history').doc(historyId).set(historyDoc);

    await awardPointsIfEligible(property.hostId, 'host_complete_transaction');
    if (property.renteeId != null && property.renteeId!.isNotEmpty) {
      await awardPointsIfEligible(property.renteeId!, 'client_complete_transaction');
    }

    await _firestore.collection('properties').doc(propertyId).update({
      'status': 'Completed',
    });

    await createNotification(
      uid: property.hostId,
      title: 'Lease Completed & Paid',
      message: 'Lease for "${property.title}" has been completed. Payout of ₱${hostPayout.toStringAsFixed(2)} credited to your wallet (after ${PlatformFeeConfig.formatPercent(hostCommRate)} host commission).',
    );

    if (property.renteeId != null && property.renteeId!.isNotEmpty) {
      await createNotification(
        uid: property.renteeId!,
        title: 'Lease Term Completed',
        message: 'Your lease for "${property.title}" has successfully ended. Thank you!',
      );
    }
  }

  // ─── Pending Requests Queries ──────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getRenterPendingRequestsStream(String renteeId) {
    return _firestore
        .collection('rental_requests')
        .where('renteeId', isEqualTo: renteeId)
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()..['id'] = doc.id).toList());
  }

  Stream<List<Map<String, dynamic>>> getPropertyRenterPendingRequestsStream(String renteeId) {
    return _firestore
        .collection('property_requests')
        .where('renteeId', isEqualTo: renteeId)
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()..['id'] = doc.id).toList());
  }

  Stream<List<Map<String, dynamic>>> getHostPendingRequestsStream(String hostId) {
    return _firestore
        .collection('rental_requests')
        .where('hostId', isEqualTo: hostId)
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()..['id'] = doc.id).toList());
  }

  Stream<List<Map<String, dynamic>>> getPropertyHostPendingRequestsStream(String hostId) {
    return _firestore
        .collection('property_requests')
        .where('hostId', isEqualTo: hostId)
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()..['id'] = doc.id).toList());
  }

  // ─── History queries ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getMyRentalHistory(String uid) async {
    final list = <Map<String, dynamic>>[];

    // Vehicle history as host
    final rh1 = await _firestore.collection('rental_history').where('hostId', isEqualTo: uid).get();
    for (final doc in rh1.docs) {
      list.add(doc.data()..['id'] = doc.id..['rentalKind'] = 'vehicle');
    }

    // Vehicle history as rentee
    final rh2 = await _firestore.collection('rental_history').where('renteeId', isEqualTo: uid).get();
    for (final doc in rh2.docs) {
      if (list.any((e) => e['id'] == doc.id && e['rentalKind'] == 'vehicle')) continue;
      list.add(doc.data()..['id'] = doc.id..['rentalKind'] = 'vehicle');
    }

    // Property history as host
    final ph1 = await _firestore.collection('property_history').where('hostId', isEqualTo: uid).get();
    for (final doc in ph1.docs) {
      list.add(doc.data()..['id'] = doc.id..['rentalKind'] = 'property');
    }

    // Property history as rentee
    final ph2 = await _firestore.collection('property_history').where('renteeId', isEqualTo: uid).get();
    for (final doc in ph2.docs) {
      if (list.any((e) => e['id'] == doc.id && e['rentalKind'] == 'property')) continue;
      list.add(doc.data()..['id'] = doc.id..['rentalKind'] = 'property');
    }

    list.sort((a, b) {
      final tA = a['completedAt'] ?? a['createdAt'] ?? 0;
      final tB = b['completedAt'] ?? b['createdAt'] ?? 0;
      return tB.compareTo(tA);
    });

    return list;
  }

  Future<void> submitRentalRating({
    required String targetUid,
    required String callerUid,
    required String role,
    required double stars,
    required String rentalId,
  }) async {
    // Save to actual rental history doc that it's rated
    // Wait, the web firebase service does:
    // final ratedFieldKey = '${role}RatedBy_$callerUid';
    // Let's verify how it writes to history or user rating
    // Let's perform a write to transactions or user profiles to increase rating
    final docRef = _firestore.collection('users').doc(targetUid);
    await _firestore.runTransaction((transaction) async {
      final userSnap = await transaction.get(docRef);
      if (!userSnap.exists) return;

      final data = userSnap.data()!;
      final double existingRating;
      final int ratingCount;

      if (role == 'renter') {
        existingRating = (data['renterRating'] as num?)?.toDouble() ?? 5.0;
        ratingCount = (data['renterRatingCount'] as num?)?.toInt() ?? 1;
        final newRating = (existingRating * ratingCount + stars) / (ratingCount + 1);
        transaction.update(docRef, {
          'renterRating': newRating,
          'renterRatingCount': ratingCount + 1,
        });
      } else {
        existingRating = (data['hostRating'] as num?)?.toDouble() ?? 5.0;
        ratingCount = (data['hostRatingCount'] as num?)?.toInt() ?? 1;
        final newRating = (existingRating * ratingCount + stars) / (ratingCount + 1);
        transaction.update(docRef, {
          'hostRating': newRating,
          'hostRatingCount': ratingCount + 1,
        });
      }
    });

    // Mark the history doc as rated
    final ratedFieldKey = '${role}RatedBy_$callerUid';
    // We try to write to both rental_history and property_history just in case
    final rhDoc = await _firestore.collection('rental_history').doc(rentalId).get();
    if (rhDoc.exists) {
      await _firestore.collection('rental_history').doc(rentalId).update({ratedFieldKey: true});
    } else {
      final phDoc = await _firestore.collection('property_history').doc(rentalId).get();
      if (phDoc.exists) {
        await _firestore.collection('property_history').doc(rentalId).update({ratedFieldKey: true});
      }
    }
  }

  // ─── KYC Verification ──────────────────────────────────────────────────
  Future<void> saveKycSubmission(String uid, Map<String, dynamic> data) async {
    await _firestore.collection('kyc_submissions').doc(uid).set({
      ...data,
      'submittedAt': DateTime.now().millisecondsSinceEpoch,
    }, SetOptions(merge: true));

    // Update user profile status
    await _firestore.collection('users').doc(uid).update({
      'verificationLevel': 1,
    });
  }

  // ─── Rewards & Quest system ──────────────────────────────────────────────
  Future<bool> awardPointsIfEligible(String uid, String questId) async {
    try {
      final quest = RewardQuest.quests.firstWhere((q) => q.id == questId);
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return false;

      final userData = userDoc.data()!;
      final currentPoints = userData['terraPoints'] as int? ?? 0;
      final earnedRewards = List<String>.from(userData['earnedRewards'] as List? ?? []);

      if (quest.limit == 'Once' && earnedRewards.contains(questId)) {
        return false; // Already completed
      }

      // Update User Doc
      final newRewards = List<String>.from(earnedRewards)..add(questId);
      await _firestore.collection('users').doc(uid).update({
        'terraPoints': currentPoints + quest.points,
        'earnedRewards': newRewards,
      });

      // Log to points_history
      final historyId = '${uid}_${questId}_${DateTime.now().millisecondsSinceEpoch}';
      await _firestore.collection('points_history').doc(historyId).set({
        'uid': uid,
        'questId': questId,
        'points': quest.points,
        'title': quest.title,
        'category': quest.category,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      print('[Rewards] Awarded ${quest.points} TP to $uid for quest "$questId"');
      return true;
    } catch (e, stack) {
      print('[Rewards] Error awarding points: $e');
      print(stack);
      rethrow;
    }
  }

  Stream<List<Map<String, dynamic>>> getUserPointsHistory(String uid) {
    return _firestore
        .collection('points_history')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()..['id'] = doc.id).toList());
  }

  Future<bool> checkAndAwardOnboardingQuests(String uid) async {
    bool newlyAwarded = false;
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return false;

      final userMap = userDoc.data()!;
      final earnedRewards = List<String>.from(userMap['earnedRewards'] as List? ?? []);

      // 1. Register Account
      if (!earnedRewards.contains('register_account')) {
        final success = await awardPointsIfEligible(uid, 'register_account');
        if (success) newlyAwarded = true;
      }

      // 2. Verify Account (Email + Phone verification completion)
      if (userMap['emailVerified'] == true && userMap['phoneVerified'] == true && !earnedRewards.contains('verify_account')) {
        final success = await awardPointsIfEligible(uid, 'verify_account');
        if (success) newlyAwarded = true;
      }

      // 3. Complete Profile Trust (idVerified == true)
      if (userMap['idVerified'] == true && !earnedRewards.contains('complete_profile_trust')) {
        final success = await awardPointsIfEligible(uid, 'complete_profile_trust');
        if (success) newlyAwarded = true;
      }

      // 4. Add Skills & Bio (skills is not empty/null or bio/headline is present)
      final skillsList = userMap['skills'] as List?;
      final hasHeadline = userMap['headline'] != null && (userMap['headline'] as String).isNotEmpty;
      if (((skillsList != null && skillsList.isNotEmpty) || hasHeadline) && !earnedRewards.contains('add_skills_bio')) {
        final success = await awardPointsIfEligible(uid, 'add_skills_bio');
        if (success) newlyAwarded = true;
      }

      // 5. Connect Any Solana Wallet (walletPublicKey is not null/empty)
      if (userMap['walletPublicKey'] != null && (userMap['walletPublicKey'] as String).isNotEmpty && !earnedRewards.contains('connect_solana_wallet')) {
        final success = await awardPointsIfEligible(uid, 'connect_solana_wallet');
        if (success) newlyAwarded = true;
      }

      // 6. Subscribe to Hybrid PRO (isPremium == true)
      if (userMap['isPremium'] == true && !earnedRewards.contains('subscribe_hybrid_pro')) {
        final success = await awardPointsIfEligible(uid, 'subscribe_hybrid_pro');
        if (success) newlyAwarded = true;
      }
    } catch (e) {
      print('checkAndAwardOnboardingQuests error: $e');
    }
    return newlyAwarded;
  }

  // ─── Transaction Log ───────────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getUserTransactions(String uid) {
    return _firestore
        .collection('transactions')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()..['id'] = doc.id).toList());
  }

  Future<void> depositFunds(String uid, double amount, String method, String desc) async {
    // Get user
    final user = await getUser(uid);
    if (user == null) return;

    // Credit balance
    await updateTyxBalance(uid, user.tyxBalance + amount);

    // Save transaction
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': uid,
      'type': 'deposit',
      'amount': amount,
      'title': 'Funds Deposited',
      'desc': desc,
      'method': method,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    await awardPointsIfEligible(uid, 'deposit_any_amount');
  }

  Future<List<Map<String, dynamic>>> getPendingRequestsForVehicle(String rentalId) async {
    final snap = await _firestore
        .collection('rental_requests')
        .where('rentalId', isEqualTo: rentalId)
        .where('status', isEqualTo: 'Pending')
        .get();
    return snap.docs.map((doc) => doc.data()..['id'] = doc.id).toList();
  }

  Future<List<Map<String, dynamic>>> getPropertyPendingRequestsForProperty(String propertyId) async {
    final snap = await _firestore
        .collection('property_requests')
        .where('propertyId', isEqualTo: propertyId)
        .where('status', isEqualTo: 'Pending')
        .get();
    return snap.docs.map((doc) => doc.data()..['id'] = doc.id).toList();
  }

  Future<void> updateVehicleGpsTracker(String rentalId, String gpsId) async {
    await _firestore.collection('rentals').doc(rentalId).update({
      'gpsTrackerId': gpsId,
    });
  }

  Future<void> createExtensionRequest({
    required String rentalId,
    required String renteeId,
    required int extendHours,
    required double fee,
  }) async {
    final rentee = await getUser(renteeId);
    if (rentee == null) throw Exception('Renter profile not found.');

    if (rentee.tyxBalance < fee) {
      throw Exception(
        'Insufficient balance. Required: ${fee.toStringAsFixed(2)} TYXBIT, but available: ${rentee.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Deduct balance
    await updateTyxBalance(renteeId, rentee.tyxBalance - fee);

    // Save transaction
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': renteeId,
      'type': 'payment',
      'amount': fee,
      'title': 'Rental Extension Request',
      'desc': 'Requested extension of $extendHours hour(s) for vehicle rental.',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Save extension request document
    final extensionId = 'ext_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('rental_extensions').doc(extensionId).set({
      'id': extensionId,
      'rentalId': rentalId,
      'renteeId': renteeId,
      'extendHours': extendHours,
      'fee': fee,
      'status': 'Pending',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Save extension escrow document
    await _firestore.collection('rental_extension_escrows').doc(extensionId).set({
      'extensionId': extensionId,
      'rentalId': rentalId,
      'renteeId': renteeId,
      'amount': fee,
      'status': 'Held',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Notify Host
    final rentalDoc = await _firestore.collection('rentals').doc(rentalId).get();
    if (rentalDoc.exists) {
      final rentalData = rentalDoc.data()!;
      final hostId = rentalData['hostId'] as String?;
      final brand = rentalData['brand'] ?? '';
      final model = rentalData['model'] ?? '';
      if (hostId != null) {
        await createNotification(
          uid: hostId,
          title: 'Extension Request Received',
          message: 'Renter requested a $extendHours-hour extension for $brand $model.',
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> getPendingExtensionsForVehicle(String rentalId) async {
    final snap = await _firestore
        .collection('rental_extensions')
        .where('rentalId', isEqualTo: rentalId)
        .where('status', isEqualTo: 'Pending')
        .get();
    return snap.docs.map((doc) => doc.data()..['id'] = doc.id).toList();
  }

  Future<void> approveExtension(String extensionId) async {
    final extDoc = await _firestore.collection('rental_extensions').doc(extensionId).get();
    if (!extDoc.exists) throw Exception('Extension request not found.');
    final extData = extDoc.data()!;
    if (extData['status'] != 'Pending') throw Exception('Extension already processed.');

    final rentalId = extData['rentalId'] as String;
    final extendHours = (extData['extendHours'] as num).toInt();
    final fee = (extData['fee'] as num).toDouble();

    final rentalDoc = await _firestore.collection('rentals').doc(rentalId).get();
    if (!rentalDoc.exists) throw Exception('Rental listing not found.');
    final rentalData = rentalDoc.data()!;

    // 1. Mark request approved
    await _firestore.collection('rental_extensions').doc(extensionId).update({'status': 'Approved'});

    // 2. Merge extension escrow into main rental escrow
    final extEscrowDoc = await _firestore.collection('rental_extension_escrows').doc(extensionId).get();
    if (extEscrowDoc.exists) {
      final escrowDoc = await _firestore.collection('rental_escrows').doc(rentalId).get();
      if (escrowDoc.exists) {
        final escrowData = escrowDoc.data()!;
        final currentAmount = (escrowData['amount'] as num? ?? 0.0).toDouble();
        await _firestore.collection('rental_escrows').doc(rentalId).update({
          'amount': currentAmount + fee,
        });
      }
      await _firestore.collection('rental_extension_escrows').doc(extensionId).delete();
    }

    // 3. Update rental endDate and totalCost
    final currentEndMs = rentalData['endDate'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final currentCost = (rentalData['totalCost'] as num? ?? 0.0).toDouble();
    final newEndDate = DateTime.fromMillisecondsSinceEpoch(currentEndMs).add(Duration(hours: extendHours));

    await _firestore.collection('rentals').doc(rentalId).update({
      'endDate': newEndDate.millisecondsSinceEpoch,
      'totalCost': currentCost + fee,
    });
  }

  Future<void> rejectExtension(String extensionId) async {
    final extDoc = await _firestore.collection('rental_extensions').doc(extensionId).get();
    if (!extDoc.exists) return;
    final extData = extDoc.data()!;
    if (extData['status'] != 'Pending') return;

    final renteeId = extData['renteeId'] as String;
    final fee = (extData['fee'] as num).toDouble();

    // 1. Mark request rejected
    await _firestore.collection('rental_extensions').doc(extensionId).update({'status': 'Rejected'});

    // 2. Refund rentee
    final rentee = await getUser(renteeId);
    if (rentee != null) {
      await updateTyxBalance(renteeId, rentee.tyxBalance + fee);

      final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
      await _firestore.collection('transactions').doc(txId).set({
        'uid': renteeId,
        'type': 'refund',
        'amount': fee,
        'title': 'Rental Extension Refund',
        'desc': 'Refund for rejected rental extension request.',
        'method': 'Tranyx Wallet',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }

    // 3. Delete extension escrow
    await _firestore.collection('rental_extension_escrows').doc(extensionId).delete();
  }

  Stream<List<Map<String, dynamic>>> getEscrowHoldbacks(String uid) {
    return _firestore
        .collection('escrow_holdbacks')
        .where('nyxianId', isEqualTo: uid)
        .where('status', isEqualTo: 'held')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()..['id'] = doc.id).toList());
  }

  Future<Promo?> getPromo(String code) async {
    final doc = await _firestore.collection('promos').doc(code.trim().toUpperCase()).get();
    if (!doc.exists) return null;
    return Promo.fromMap(doc.data()!, doc.id);
  }

  Future<List<Promo>> getAllActivePromos() async {
    final query = await _firestore
        .collection('promos')
        .where('isActive', isEqualTo: true)
        .get();
    return query.docs.map((doc) => Promo.fromMap(doc.data(), doc.id)).toList();
  }

  Future<void> incrementPromoUsage(String code, String userId) async {
    final docRef = _firestore.collection('promos').doc(code.trim().toUpperCase());
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      final usedBy = List<String>.from(snapshot.data()?['usedBy'] ?? []);
      if (!usedBy.contains(userId)) {
        usedBy.add(userId);
      }
      final usedCount = (snapshot.data()?['usedCount'] as num? ?? 0).toInt() + 1;
      transaction.update(docRef, {
        'usedBy': usedBy,
        'usedCount': usedCount,
      });
    });
  }

  Future<void> decrementPromoUsage(String code, String userId) async {
    final docRef = _firestore.collection('promos').doc(code.trim().toUpperCase());
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      final usedBy = List<String>.from(snapshot.data()?['usedBy'] ?? []);
      usedBy.remove(userId);
      final usedCount = ((snapshot.data()?['usedCount'] as num? ?? 1).toInt() - 1).clamp(0, 999999);
      transaction.update(docRef, {
        'usedBy': usedBy,
        'usedCount': usedCount,
      });
    });
  }

  Future<void> seedAutoZeroFeePromoIfMissing() async {
    try {
      final docRef = _firestore.collection('promos').doc('ZEROFEES1000');
      final doc = await docRef.get();
      if (!doc.exists) {
        final now = DateTime.now();
        final zeroFeePromo = Promo(
          code: 'ZEROFEES1000',
          name: 'Auto Zero Platform Fees - First 1,000 Users',
          description: 'Automatic 100% platform fee and transaction fee waiver for the first 1,000 users.',
          discountType: 'percentage',
          discountValue: 100.0,
          applicableFee: 'all_fees',
          applicableTo: 'both',
          eligibleModules: ['jobs', 'services', 'rentals', 'vehicle_rentals', 'property_rentals', 'all'],
          maxUsers: 1000,
          maxUsesPerUser: 1,
          usedCount: 0,
          isSingleUsePerUser: true,
          isAutoApply: true,
          isActive: true,
          createdAt: now,
          startDate: now,
          endDate: now.add(const Duration(days: 365)),
          createdBy: 'system_admin',
        );
        await docRef.set(zeroFeePromo.toMap());
      }
    } catch (e) {
      debugPrint('seedAutoZeroFeePromoIfMissing error: $e');
    }
  }

  Future<void> savePromo(Promo promo, {String? adminUid}) async {
    final cleanCode = promo.code.trim().toUpperCase();
    final docRef = _firestore.collection('promos').doc(cleanCode);
    final previousDoc = await docRef.get();
    await docRef.set(promo.toMap());

    // Audit trail
    final auditId = 'audit_${cleanCode}_${DateTime.now().millisecondsSinceEpoch}';
    await _firestore.collection('promo_audit_logs').doc(auditId).set({
      'promoCode': cleanCode,
      'action': !previousDoc.exists ? 'create' : 'update',
      'performedBy': adminUid ?? 'admin',
      'previousState': previousDoc.data(),
      'newState': promo.toMap(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> redeemPromoToProfile(String userId, Promo promo) async {
    final userRef = _firestore.collection('users').doc(userId);
    await userRef.update({
      'activePromoCode': promo.code,
      'activePromoDiscountType': promo.discountType,
      'activePromoDiscountValue': promo.discountValue,
    });
  }

  Future<void> disablePromoForUser(String userId, String promoCode) async {
    final userRef = _firestore.collection('users').doc(userId);
    await userRef.update({
      'activePromoCode': null,
      'activePromoDiscountType': null,
      'activePromoDiscountValue': null,
      'disabledPromos': FieldValue.arrayUnion([promoCode]),
    });
  }

  Stream<List<NewsPost>> getActiveNewsPostsStream() {
    return _firestore
        .collection('news_posts')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          final now = DateTime.now();
          return snap.docs
              .map((doc) => NewsPost.fromMap(doc.data(), doc.id))
              .where((post) => post.isActive && (post.publishAt == null || !post.publishAt!.isAfter(now)))
              .toList();
        });
  }

  Future<void> updatePremiumStatus({
    required String uid,
    required bool isPremium,
    required DateTime? premiumUntil,
  }) async {
    await _firestore.collection('users').doc(uid).update({
      'isPremium': isPremium,
      'premiumUntil': premiumUntil?.millisecondsSinceEpoch,
      'accountType': isPremium ? 'hybrid' : 'nyxian',
    });
  }

  Future<void> checkAndExpireSubscription(String uid) async {
    try {
      final user = await getUser(uid);
      if (user != null && user.isPremium) {
        if (user.premiumUntil != null && user.premiumUntil!.isBefore(DateTime.now())) {
          await updatePremiumStatus(
            uid: uid,
            isPremium: false,
            premiumUntil: null,
          );
          await createNotification(
            uid: uid,
            title: 'Subscription Expired',
            message: 'Your Premium Hybrid subscription has expired. Renew now to continue enjoying PRO features!',
          );
        }
      }
    } catch (e) {
      // ignore
    }
  }

  // ─── Manual P2P Deposit Rail (GCash / Maya) & Agent Management ───────
  Future<P2pAgent> fetchActiveP2pAgent({String? agentId}) async {
    try {
      if (agentId != null && agentId.isNotEmpty) {
        final doc = await _firestore.collection('p2p_agents').doc(agentId).get();
        if (doc.exists && doc.data() != null) {
          return P2pAgent.fromMap(doc.data()!, docId: agentId);
        }
      }
      final snap = await _firestore
          .collection('p2p_agents')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return P2pAgent.fromMap(snap.docs.first.data(), docId: snap.docs.first.id);
      }
    } catch (e) {
      // Fallback to default
    }
    return P2pAgent.defaultAgent();
  }

  Future<void> updateP2pAgentProfile(P2pAgent agent) async {
    await _firestore
        .collection('p2p_agents')
        .doc(agent.agentId)
        .set(agent.toMap(), SetOptions(merge: true));
  }

  /// Step 1 (User): Request P2P Top-up (informs agents to send QR code)
  Future<String> requestP2pTopup({
    required String uid,
    required String userName,
    required String userEmail,
    required double amount,
    required String paymentMethod,
  }) async {
    final cleanMethod = paymentMethod.trim();
    final now = DateTime.now().millisecondsSinceEpoch;

    final docRef = _firestore.collection('deposit_requests').doc();
    final depositReq = DepositRequest(
      id: docRef.id,
      uid: uid,
      userName: userName,
      userEmail: userEmail,
      amount: amount,
      paymentMethod: cleanMethod,
      status: 'WAITING_FOR_AGENT',
      createdAt: now,
    );

    await docRef.set(depositReq.toMap());

    // Record in ledger
    final txId = 'p2p_dep_${docRef.id}';
    await _firestore.collection('transactions').doc(txId).set({
      'id': txId,
      'uid': uid,
      'depositRequestId': docRef.id,
      'title': '$cleanMethod P2P Top-Up Request',
      'desc': 'Awaiting Payment Agent QR Code',
      'amount': amount,
      'originRail': 'manual_p2p',
      'method': cleanMethod,
      'type': 'deposit',
      'status': 'WAITING_FOR_AGENT',
      'createdAt': now,
    });

    return docRef.id;
  }

  /// Step 2 (Agent): Agent accepts order and sends their payment QR code & number
  Future<void> agentAcceptAndSendQr({
    required String depositRequestId,
    required String agentId,
    required String agentName,
    required String agentAccountName,
    required String agentAccountNumber,
    required String agentQrUrl,
  }) async {
    final reqDocRef = _firestore.collection('deposit_requests').doc(depositRequestId);
    final reqSnapshot = await reqDocRef.get();
    if (!reqSnapshot.exists) throw Exception('Deposit request not found.');

    final reqData = reqSnapshot.data()!;
    final currentStatus = (reqData['status'] as String? ?? '').toUpperCase();
    final currentAgentId = reqData['agentId'] as String?;
    if (currentStatus != 'WAITING_FOR_AGENT' || (currentAgentId != null && currentAgentId.isNotEmpty && currentAgentId != agentId)) {
      final claimant = reqData['agentName'] ?? 'another agent';
      throw Exception('This deposit order has already been claimed by $claimant.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanAgentName = _cleanDisplayName(agentName, fallback: 'TRANYX Agent');
    final cleanAccountName = agentAccountName.trim().isNotEmpty ? agentAccountName.trim() : cleanAgentName;

    await reqDocRef.update({
      'status': 'AWAITING_PAYMENT',
      'agentId': agentId,
      'agentName': cleanAgentName,
      'agentAccountName': cleanAccountName,
      'agentAccountNumber': agentAccountNumber,
      'agentQrUrl': agentQrUrl,
      'qrSentAt': now,
    });

    final txDocRef = _firestore.collection('transactions').doc('p2p_dep_$depositRequestId');
    await txDocRef.set({
      'status': 'AWAITING_PAYMENT',
      'desc': 'Agent $cleanAgentName sent QR Code. Awaiting payment.',
      'agentId': agentId,
      'agentName': cleanAgentName,
    }, SetOptions(merge: true));
  }

  /// Step 3 (User): User submits payment reference and proof receipt
  Future<void> submitDepositProof({
    required String depositRequestId,
    required String referenceNumber,
    required String proofImageUrl,
  }) async {
    final cleanRef = referenceNumber.trim();
    if (cleanRef.isEmpty) throw Exception('Reference number is required.');
    if (proofImageUrl.isEmpty) throw Exception('Payment screenshot / proof is required.');

    final reqDocRef = _firestore.collection('deposit_requests').doc(depositRequestId);
    final reqSnapshot = await reqDocRef.get();
    if (!reqSnapshot.exists) throw Exception('Deposit request not found.');

    final now = DateTime.now().millisecondsSinceEpoch;

    await reqDocRef.update({
      'status': 'PENDING_VERIFICATION',
      'referenceNumber': cleanRef,
      'proofImageUrl': proofImageUrl,
      'proofSubmittedAt': now,
    });

    final txDocRef = _firestore.collection('transactions').doc('p2p_dep_$depositRequestId');
    await txDocRef.set({
      'status': 'PENDING_VERIFICATION',
      'referenceNumber': cleanRef,
      'proofImageUrl': proofImageUrl,
      'desc': 'Payment proof submitted. Awaiting agent verification.',
    }, SetOptions(merge: true));
  }

  Future<String> submitManualDepositRequest({
    required String uid,
    required String userName,
    required String userEmail,
    required double amount,
    required String paymentMethod,
    required String referenceNumber,
    required String proofImageUrl,
    String? agentId,
    String? agentName,
    String? agentQrUrl,
  }) async {
    final cleanRef = referenceNumber.trim();
    final cleanMethod = paymentMethod.trim();
    final now = DateTime.now().millisecondsSinceEpoch;

    final docRef = _firestore.collection('deposit_requests').doc();
    final depositReq = DepositRequest(
      id: docRef.id,
      uid: uid,
      userName: userName,
      userEmail: userEmail,
      amount: amount,
      paymentMethod: cleanMethod,
      referenceNumber: cleanRef,
      proofImageUrl: proofImageUrl,
      status: 'PENDING_VERIFICATION',
      agentId: agentId,
      agentName: agentName,
      agentQrUrl: agentQrUrl,
      createdAt: now,
      proofSubmittedAt: now,
    );

    await docRef.set(depositReq.toMap());

    // Write to user transactions ledger
    final txId = 'p2p_dep_${docRef.id}';
    await _firestore.collection('transactions').doc(txId).set({
      'id': txId,
      'uid': uid,
      'depositRequestId': docRef.id,
      'title': '$cleanMethod P2P Top-Up',
      'desc': 'Manual $cleanMethod Transfer (Ref: $cleanRef)',
      'amount': amount,
      'originRail': 'manual_p2p',
      'method': cleanMethod,
      'type': 'deposit',
      'status': 'PENDING_VERIFICATION',
      'referenceNumber': cleanRef,
      'proofImageUrl': proofImageUrl,
      'createdAt': now,
    });

    return docRef.id;
  }

  Future<void> approveDepositRequest({
    required String depositRequestId,
    required String adminUid,
  }) async {
    await _firestore.runTransaction((transaction) async {
      final reqDocRef = _firestore.collection('deposit_requests').doc(depositRequestId);
      final reqSnapshot = await transaction.get(reqDocRef);

      if (!reqSnapshot.exists) {
        throw Exception('Deposit request not found.');
      }

      final reqData = reqSnapshot.data()!;
      final currentStatus = reqData['status'] as String? ?? '';
      if (currentStatus != 'PENDING_VERIFICATION') {
        throw Exception('Deposit request is not pending verification (Current: $currentStatus).');
      }

      final paymentMethod = (reqData['paymentMethod'] ?? 'GCash').toString();
      final referenceNumber = (reqData['referenceNumber'] ?? '').toString().trim();
      final uid = reqData['uid'] as String;
      final amount = (reqData['amount'] as num).toDouble();

      // Duplicate reference check across approved requests
      final refLockDocRef = _firestore
          .collection('deposit_references')
          .doc('${paymentMethod.toLowerCase()}_$referenceNumber');
      final refLockSnapshot = await transaction.get(refLockDocRef);

      if (refLockSnapshot.exists) {
        throw Exception('Reference number has already been claimed/approved');
      }

      final userDocRef = _firestore.collection('users').doc(uid);
      final userSnapshot = await transaction.get(userDocRef);

      final currentBalance = (userSnapshot.data()?['tyxBalance'] as num?)?.toDouble() ?? 0.0;
      final newBalance = currentBalance + amount;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1. Mark request as APPROVED
      transaction.update(reqDocRef, {
        'status': 'APPROVED',
        'adminUid': adminUid,
        'verifiedAt': now,
      });

      // 2. Lock reference number permanently
      transaction.set(refLockDocRef, {
        'depositRequestId': depositRequestId,
        'referenceNumber': referenceNumber,
        'paymentMethod': paymentMethod,
        'uid': uid,
        'amount': amount,
        'adminUid': adminUid,
        'approvedAt': now,
      });

      // 3. Increment user balance
      transaction.update(userDocRef, {
        'tyxBalance': newBalance,
      });

      final cleanAgent = cleanAgentDisplayName(adminUid, fallback: 'TRANYX Agent');
      final descText = referenceNumber.isNotEmpty
          ? 'Reference #$referenceNumber approved by $cleanAgent'
          : 'P2P Transfer approved by $cleanAgent';

      // 4. Update transaction record
      final txDocRef = _firestore.collection('transactions').doc('p2p_dep_$depositRequestId');
      transaction.set(
        txDocRef,
        {
          'id': 'p2p_dep_$depositRequestId',
          'uid': uid,
          'depositRequestId': depositRequestId,
          'title': '$paymentMethod P2P Top-Up',
          'desc': descText,
          'amount': amount,
          'originRail': 'manual_p2p',
          'method': paymentMethod,
          'type': 'deposit',
          'status': 'Completed',
          'referenceNumber': referenceNumber,
          'proofImageUrl': reqData['proofImageUrl'],
          'agentName': cleanAgent,
          'createdAt': reqData['createdAt'] ?? now,
          'verifiedAt': now,
          'adminUid': adminUid,
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> rejectDepositRequest({
    required String depositRequestId,
    required String adminUid,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) throw Exception('Rejection reason is required.');

    final reqDocRef = _firestore.collection('deposit_requests').doc(depositRequestId);
    final reqSnap = await reqDocRef.get();
    if (!reqSnap.exists) throw Exception('Deposit request not found.');

    final now = DateTime.now().millisecondsSinceEpoch;

    await _firestore.runTransaction((transaction) async {
      transaction.update(reqDocRef, {
        'status': 'REJECTED',
        'adminUid': adminUid,
        'rejectionReason': cleanReason,
        'verifiedAt': now,
      });

      final txDocRef = _firestore.collection('transactions').doc('p2p_dep_$depositRequestId');
      transaction.set(
        txDocRef,
        {
          'status': 'REJECTED',
          'rejectionReason': cleanReason,
          'verifiedAt': now,
          'adminUid': adminUid,
        },
        SetOptions(merge: true),
      );
    });
  }

  Stream<List<DepositRequest>> getPendingDepositRequestsStream() {
    return _firestore
        .collection('deposit_requests')
        .where('status', isEqualTo: 'PENDING_VERIFICATION')
        .snapshots()
        .map((snap) => snap.docs.map((d) => DepositRequest.fromMap(d.data(), docId: d.id)).toList());
  }

  Stream<List<DepositRequest>> getUserDepositRequestsStream(String uid) {
    return _firestore
        .collection('deposit_requests')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => DepositRequest.fromMap(d.data(), docId: d.id)).toList());
  }

  // ──────────────────────────────────────────────────────────────────────────
  // P2P WITHDRAWAL SYSTEM (GCash / Maya)
  // ──────────────────────────────────────────────────────────────────────────

  Future<String> requestP2pWithdrawal({
    required String uid,
    required String userName,
    required String userEmail,
    required double amount,
    required String paymentMethod,
    required String userAccountName,
    required String userAccountNumber,
    String userQrUrl = '',
  }) async {
    final cleanMethod = paymentMethod.trim();
    final cleanAccountName = userAccountName.trim();
    final cleanAccountNumber = userAccountNumber.trim();

    if (cleanAccountName.isEmpty) throw Exception('Recipient Account Name is required.');
    if (cleanAccountNumber.isEmpty) throw Exception('Recipient Account / Mobile Number is required.');
    if (amount < 100) throw Exception('Minimum withdrawal amount is ₱ 100.00.');

    final userDocRef = _firestore.collection('users').doc(uid);
    final userSnap = await userDocRef.get();
    final currentBalance = (userSnap.data()?['tyxBalance'] as num?)?.toDouble() ?? 0.0;
    if (amount > currentBalance) {
      throw Exception('Requested withdrawal amount exceeds your available balance.');
    }

    final newBalance = currentBalance - amount;
    await userDocRef.set({'tyxBalance': newBalance}, SetOptions(merge: true));

    final now = DateTime.now().millisecondsSinceEpoch;
    final docRef = _firestore.collection('withdrawal_requests').doc();

    final withdrawalReq = WithdrawalRequest(
      id: docRef.id,
      uid: uid,
      userName: userName,
      userEmail: userEmail,
      amount: amount,
      paymentMethod: cleanMethod,
      userAccountName: cleanAccountName,
      userAccountNumber: cleanAccountNumber,
      userQrUrl: userQrUrl,
      status: 'WAITING_FOR_AGENT',
      createdAt: now,
    );

    await docRef.set(withdrawalReq.toMap());

    final txId = 'p2p_with_${docRef.id}';
    await _firestore.collection('transactions').doc(txId).set({
      'id': txId,
      'uid': uid,
      'withdrawalRequestId': docRef.id,
      'title': '$cleanMethod P2P Cashout Request',
      'desc': 'Awaiting Payment Agent fulfillment to $cleanAccountNumber ($cleanAccountName)',
      'amount': -amount,
      'originRail': 'manual_p2p',
      'method': cleanMethod,
      'type': 'withdraw',
      'status': 'WAITING_FOR_AGENT',
      'userAccountName': cleanAccountName,
      'userAccountNumber': cleanAccountNumber,
      if (userQrUrl.isNotEmpty) 'userQrUrl': userQrUrl,
      'createdAt': now,
    });

    return docRef.id;
  }

  Future<void> cancelP2pWithdrawalRequest(String withdrawalRequestId, {String? reason}) async {
    final docRef = _firestore.collection('withdrawal_requests').doc(withdrawalRequestId);
    final snap = await docRef.get();
    if (!snap.exists) return;
    final data = snap.data()!;
    final status = (data['status'] as String? ?? '').toUpperCase();
    if (status == 'APPROVED' || status == 'CANCELLED') return;

    final uid = data['uid'] as String;
    final amount = (data['amount'] as num).toDouble();
    final now = DateTime.now().millisecondsSinceEpoch;

    final userDocRef = _firestore.collection('users').doc(uid);
    final userSnap = await userDocRef.get();
    final currentBalance = (userSnap.data()?['tyxBalance'] as num?)?.toDouble() ?? 0.0;
    final restoredBalance = currentBalance + amount;
    await userDocRef.set({'tyxBalance': restoredBalance}, SetOptions(merge: true));

    await docRef.set({
      'status': 'CANCELLED',
      'rejectionReason': ?reason,
      'verifiedAt': now,
    }, SetOptions(merge: true));

    final txDocRef = _firestore.collection('transactions').doc('p2p_with_$withdrawalRequestId');
    await txDocRef.set({
      'status': 'CANCELLED',
      'desc': 'Cashout cancelled. ₱${amount.toStringAsFixed(2)} refunded to wallet.',
      'verifiedAt': now,
    }, SetOptions(merge: true));
  }

  Future<void> confirmP2pWithdrawalCompleted({
    required String withdrawalRequestId,
    required String confirmedByUid,
  }) async {
    final docRef = _firestore.collection('withdrawal_requests').doc(withdrawalRequestId);
    final snap = await docRef.get();
    if (!snap.exists) throw Exception('Withdrawal request not found.');
    final data = snap.data()!;

    final paymentMethod = (data['paymentMethod'] ?? 'GCash').toString();
    final referenceNumber = (data['referenceNumber'] ?? '').toString().trim();
    final now = DateTime.now().millisecondsSinceEpoch;

    await docRef.set({
      'status': 'APPROVED',
      'adminUid': confirmedByUid,
      'verifiedAt': now,
    }, SetOptions(merge: true));

    final txDocRef = _firestore.collection('transactions').doc('p2p_with_$withdrawalRequestId');
    await txDocRef.set({
      'status': 'COMPLETED',
      'desc': referenceNumber.isNotEmpty
          ? 'Cashout completed via $paymentMethod (Ref: #$referenceNumber)'
          : 'Cashout completed via $paymentMethod',
      'verifiedAt': now,
      'adminUid': confirmedByUid,
    }, SetOptions(merge: true));
  }

  Stream<List<WithdrawalRequest>> getPendingWithdrawalRequestsStream() {
    return _firestore
        .collection('withdrawal_requests')
        .where('status', isEqualTo: 'WAITING_FOR_AGENT')
        .snapshots()
        .map((snap) => snap.docs.map((d) => WithdrawalRequest.fromMap(d.data(), docId: d.id)).toList());
  }

  Stream<List<WithdrawalRequest>> getUserWithdrawalRequestsStream(String uid) {
    return _firestore
        .collection('withdrawal_requests')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => WithdrawalRequest.fromMap(d.data(), docId: d.id)).toList());
  }

  static String _cleanDisplayName(String? raw, {String fallback = 'TRANYX Agent'}) {
    return cleanAgentDisplayName(raw, fallback: fallback);
  }
}

final transitRepositoryProvider = Provider<TransitRepository>((ref) {
  return TransitRepository(ref.watch(firestoreProvider));
});

final activeNewsPostsProvider = StreamProvider<List<NewsPost>>((ref) {
  return ref.watch(transitRepositoryProvider).getActiveNewsPostsStream();
});

// Streams
final realtimeRentalsProvider = StreamProvider<List<VehicleRental>>((ref) {
  return ref.watch(transitRepositoryProvider).getRealtimeRentals();
});

final realtimePropertiesProvider = StreamProvider<List<PropertyRental>>((ref) {
  return ref.watch(transitRepositoryProvider).getRealtimeProperties();
});

final renterPendingRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return Stream.value([]);
  return ref.watch(transitRepositoryProvider).getRenterPendingRequestsStream(user.uid);
});

final propertyRenterPendingRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return Stream.value([]);
  return ref.watch(transitRepositoryProvider).getPropertyRenterPendingRequestsStream(user.uid);
});

final hostPendingRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return Stream.value([]);
  return ref.watch(transitRepositoryProvider).getHostPendingRequestsStream(user.uid);
});

final propertyHostPendingRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return Stream.value([]);
  return ref.watch(transitRepositoryProvider).getPropertyHostPendingRequestsStream(user.uid);
});

final userTransactionsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return Stream.value([]);
  return ref.watch(transitRepositoryProvider).getUserTransactions(user.uid);
});

final escrowHoldbacksProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return Stream.value([]);
  return ref.watch(transitRepositoryProvider).getEscrowHoldbacks(user.uid);
});

final activeP2pAgentProvider = FutureProvider<P2pAgent>((ref) async {
  return ref.watch(transitRepositoryProvider).fetchActiveP2pAgent();
});

final pendingDepositRequestsProvider = StreamProvider<List<DepositRequest>>((ref) {
  return ref.watch(transitRepositoryProvider).getPendingDepositRequestsStream();
});

final pendingWithdrawalRequestsProvider = StreamProvider<List<WithdrawalRequest>>((ref) {
  return ref.watch(transitRepositoryProvider).getPendingWithdrawalRequestsStream();
});


