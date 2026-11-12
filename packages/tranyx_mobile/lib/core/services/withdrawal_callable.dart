import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// Calls the `requestWithdrawal` Cloud Function (KAN-146).
///
/// The server re-checks auth, balance, limits; computes fee, rate and crypto amount; debits the
/// balance; writes the request/ledger records; and (Solana) signs the transfer with the treasury
/// key held in Secret Manager. The app sends only idempotencyKey, method, amount, coin and payout
/// destination details. Throws [WithdrawalException].
Future<Map<String, dynamic>> callRequestWithdrawal(Map<String, dynamic> data) async {
  const base = String.fromEnvironment('FUNCTIONS_BASE_URL');
  final projectId = Firebase.app().options.projectId;
  final url = base.isNotEmpty
      ? '$base/requestWithdrawal'
      : 'https://us-central1-$projectId.cloudfunctions.net/requestWithdrawal';

  Future<http.Response> post({required bool forceRefresh}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const WithdrawalException('UNAUTHENTICATED', 'Please sign in to withdraw.');
    }
    final idToken = await user.getIdToken(forceRefresh);
    String? appCheck;
    try {
      appCheck = await FirebaseAppCheck.instance.getToken();
    } catch (e) {
      debugPrint('App Check token unavailable: $e');
    }
    return http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
            if (appCheck != null && appCheck.isNotEmpty) 'X-Firebase-AppCheck': appCheck,
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 130));
  }

  http.Response res;
  try {
    res = await post(forceRefresh: false);
    if (res.statusCode == 401) res = await post(forceRefresh: true);
  } on WithdrawalException {
    rethrow;
  } on TimeoutException {
    throw const WithdrawalException('NETWORK', 'The request timed out. Please retry; you will not be charged twice.');
  } catch (_) {
    throw const WithdrawalException('NETWORK', 'Network error. Please retry; you will not be charged twice.');
  }

  Map<String, dynamic> body;
  try {
    body = jsonDecode(res.body) as Map<String, dynamic>;
  } catch (_) {
    throw WithdrawalException('INTERNAL', 'Unexpected server response (${res.statusCode}).');
  }
  if (res.statusCode == 200 && body['result'] is Map) {
    return Map<String, dynamic>.from(body['result'] as Map);
  }
  final err = (body['error'] as Map?) ?? const {};
  throw WithdrawalException(
    (err['status'] ?? 'INTERNAL').toString(),
    (err['message'] ?? 'Withdrawal could not be processed.').toString(),
  );
}
