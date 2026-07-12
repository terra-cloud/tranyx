import 'dart:convert';
import 'dart:math' show min;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
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

    // Reject all pending requests
    final requests = await _firestore
        .collection('rental_requests')
        .where('rentalId', isEqualTo: rentalId)
        .where('status', isEqualTo: 'Pending')
        .get();

    for (final r in requests.docs) {
      await rejectBookingRequest(r.id);
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
    required String licenseNumber,
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
      'desc': 'Requested ${rental.brand} ${rental.model} for $multiplier $durationType(s)' +
          (promoCode != null ? ' (Promo $promoCode applied)' : ''),
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
      if (promoCode != null) 'promoCode': promoCode,
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

  // ─── Property Rentals ──────────────────────────────────────────────────
  Future<String> createPropertyRental(PropertyRental property) async {
    final host = await getUser(property.hostId);
    if (host == null) throw Exception('Host profile not found.');

    final listingFee = 0.015 * property.priceMonthly;
    if (host.tyxBalance < listingFee) {
      throw Exception(
        'Insufficient balance. Listing fee requires ${listingFee.toStringAsFixed(2)} TYXBIT, but your balance is ${host.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    await updateTyxBalance(property.hostId, host.tyxBalance - listingFee);

    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': property.hostId,
      'type': 'listing_fee',
      'amount': listingFee,
      'title': 'Property Listing Fee',
      'desc': '1.5% posting fee for property: ${property.title}',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    final docRef = _firestore.collection('properties').doc();
    final updatedProp = property.toMap()..['id'] = docRef.id;
    await docRef.set(updatedProp);
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

    await _firestore.collection('properties').doc(propertyId).delete();
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

    final discount = discountAmount ?? 0.0;
    final discountedTotalCost = (totalCost - discount).clamp(0.0, 999999.0);
    final bookingFee = discountedTotalCost * 0.03;
    final totalRequired = discountedTotalCost + bookingFee;

    if (rentee.tyxBalance < totalRequired) {
      throw Exception(
        'Insufficient balance. Required: ${totalRequired.toStringAsFixed(2)} TYXBIT (including 3% booking fee), but available: ${rentee.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    await updateTyxBalance(renteeId, rentee.tyxBalance - totalRequired);

    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': renteeId,
      'type': 'payment',
      'amount': totalRequired,
      'title': 'Property Booking Request',
      'desc': 'Requested property "${property.title}" for $multiplier $durationType(s)' +
          (promoCode != null ? ' (Promo $promoCode applied)' : ''),
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
      'bookingFee': bookingFee,
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
      if (promoCode != null) 'promoCode': promoCode,
      if (promoCode != null) 'discountAmount': discount,
    });

    await _firestore.collection('property_escrows').doc(requestId).set({
      'requestId': requestId,
      'propertyId': propertyId,
      'renteeId': renteeId,
      'hostId': property.hostId,
      'amount': discountedTotalCost,
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
    final startDate = (reqData['startDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final endDate = (reqData['endDate'] as num?)?.toInt() ?? DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;

    await _firestore.collection('property_requests').doc(requestId).update({'status': 'Approved'});

    final reqEscrowDoc = await _firestore.collection('property_escrows').doc(requestId).get();
    final reqBookingFee = (reqData['bookingFee'] as num? ?? totalCost * 0.03).toDouble();
    if (reqEscrowDoc.exists) {
      await _firestore.collection('property_escrows').doc(propertyId).set({
        'propertyId': propertyId,
        'renteeId': renteeId,
        'hostId': property.hostId,
        'amount': totalCost,
        'bookingFee': reqBookingFee,
        'totalPaid': totalCost + reqBookingFee,
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
      'bookingFee': reqBookingFee,
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
    if (escrowDoc.data()!['status'] != 'Held') throw Exception('Escrow is not in Held status.');

    final cost = property.totalCost ?? 0.0;
    final commission = cost * 0.03;
    final hostPayout = cost - commission;

    await updateTyxBalance(property.hostId, host.tyxBalance + hostPayout);

    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await _firestore.collection('transactions').doc(txId).set({
      'uid': property.hostId,
      'type': 'payment',
      'amount': hostPayout,
      'baseAmount': cost,
      'commissionFee': commission,
      'commissionLabel': 'Platform Commission (3%)',
      'title': 'Property Rental Payout',
      'desc': 'Earnings payout for "${property.title}" (3% platform commission of ${commission.toStringAsFixed(2)} TYXBIT deducted)',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    await _firestore.collection('property_escrows').doc(propertyId).update({
      'status': 'Released',
      'releasedAt': DateTime.now().millisecondsSinceEpoch,
    });

    final historyId = 'ph_${DateTime.now().microsecondsSinceEpoch}';
    final historyDoc = {
      ...doc.data()!,
      'status': 'Completed',
      'completedAt': DateTime.now().millisecondsSinceEpoch,
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
      message: 'Lease for "${property.title}" has been completed. Payout of ${hostPayout.toStringAsFixed(2)} TYXBIT credited to your wallet.',
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

  Future<Map<String, dynamic>> createXenditInvoice({
    required String uid,
    required double amount,
    required String userName,
  }) async {
    const apiKey = 'xnd_development_6en2scIVPSVNYySuAtoeoHL7NTZ0xl5tMfMsHbkJT3e2HnI7fyFxkC1LkDD3A';
    final basicAuth = base64Encode(utf8.encode('$apiKey:'));
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final response = await http.post(
      Uri.parse('https://api.xendit.co/v2/invoices'),
      headers: {
        'Authorization': 'Basic $basicAuth',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'external_id': 'topup_${uid}_$timestamp',
        'amount': amount.round(),
        'payer_email': userName.isNotEmpty
            ? '${userName.replaceAll(' ', '').toLowerCase()}@example.com'
            : 'user@example.com',
        'description': 'Tyxbit Top-up for $userName',
        'success_redirect_url': 'tranyx://payment-success?uid=$uid',
        'failure_redirect_url': 'tranyx://payment-failure?uid=$uid',
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return {
        'id': data['id'] as String,
        'invoice_url': data['invoice_url'] as String,
      };
    } else {
      throw Exception('Xendit Invoice Creation Failed: ${response.statusCode}');
    }
  }

  Future<bool> verifyXenditPayment({
    required String uid,
    required String invoiceId,
    required double amount,
  }) async {
    const apiKey = 'xnd_development_6en2scIVPSVNYySuAtoeoHL7NTZ0xl5tMfMsHbkJT3e2HnI7fyFxkC1LkDD3A';
    final basicAuth = base64Encode(utf8.encode('$apiKey:'));

    final checkRes = await http.get(
      Uri.parse('https://api.xendit.co/v2/invoices/$invoiceId'),
      headers: {'Authorization': 'Basic $basicAuth'},
    );

    if (checkRes.statusCode == 200) {
      final checkData = jsonDecode(checkRes.body);
      final status = checkData['status'];
      if (status == 'PAID' || status == 'SETTLED') {
        // Credit balance
        final user = await getUser(uid);
        if (user != null) {
          final newBal = user.tyxBalance + amount;
          await updateTyxBalance(uid, newBal);

          // Save transaction
          final txId = 'deposit_$invoiceId';
          await _firestore.collection('transactions').doc(txId).set({
            'uid': uid,
            'type': 'deposit',
            'amount': amount,
            'title': 'Wallet Top-Up',
            'desc': 'Fiat deposit via Xendit',
            'method': 'Xendit',
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });

          await awardPointsIfEligible(uid, 'deposit_any_amount');
          return true;
        }
      }
    }
    return false;
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

