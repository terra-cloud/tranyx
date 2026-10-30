import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/services/cloud_function_client.dart';

/// Calls a server-side money callable (`bookingRequest`, `bookingAction`, `rentalExtension`,
/// `listingFee`, `jobAction`, `subscribeWithBalance`, `updateP2pWithdrawal`).
///
/// Wallet balances and escrow documents are Admin-SDK only: the server recomputes every amount
/// from authoritative docs, so the app only sends intent (ids, plan, action) plus an idempotency
/// key. Re-send the same [idempotencyKey] when retrying an indeterminate failure.
/// Throws [CloudFunctionException].
Future<Map<String, dynamic>> callMoney(
  String name,
  Map<String, dynamic> data, {
  String? idempotencyKey,
}) {
  return callCloudFunction(name, {'idempotencyKey': idempotencyKey ?? newIdempotencyKey(), ...data});
}
