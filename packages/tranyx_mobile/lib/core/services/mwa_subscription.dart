import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tranyx_mobile/core/services/mwa_payment.dart';

/// Activates Hybrid PRO for [uid] after a verified on-chain payment, exactly
/// like the existing Solana wallet subscription flow (same user fields, same
/// `sub_sol_<signature>` record), but idempotent per signature: the record and
/// the activation are one Firestore transaction, so a retry or double tap can
/// never re-extend or double-record. Returns false if [signature] was already
/// processed.
Future<bool> activateSubscriptionOnce({
  required FirebaseFirestore firestore,
  required String uid,
  required String signature,
  required String plan, // 'yearly' | 'monthly'
  required double phpAmount,
  required double cryptoAmount,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final yearly = plan == 'yearly';
  final premiumUntil = at.add(Duration(days: yearly ? 365 : 30));
  return commitOnceByMarker(
    firestore: firestore,
    uid: uid,
    markerId: 'sub_sol_$signature',
    markerData: {
      'uid': uid,
      'type': 'subscription',
      'amount': phpAmount,
      'title': 'Hybrid PRO Subscription (${yearly ? 'Yearly' : 'Monthly'})',
      'desc':
          'Subscribed via Solana Mobile Wallet (${cryptoAmount.toStringAsFixed(4)} SOL)',
      'method': 'Solana Mobile Wallet',
      'solanaTxSignature': signature,
      'createdAt': at.millisecondsSinceEpoch,
    },
    userUpdate: {
      'isPremium': true,
      'premiumUntil': premiumUntil.millisecondsSinceEpoch,
      'accountType': 'hybrid',
    },
  );
}
