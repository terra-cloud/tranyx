import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// Calls an HTTPS-callable Cloud Function over the documented callable protocol
/// (`POST {data}` with the Firebase ID token and an App Check token) and returns its `result` map.
///
/// `FUNCTIONS_BASE_URL` (dart-define) points at an emulator; otherwise the project's us-central1 URL.
/// Throws [CloudFunctionException]: status NETWORK / INTERNAL means the outcome is unknown and the
/// same request is safe to repeat (the server is idempotent per signature / key).
Future<Map<String, dynamic>> callCloudFunction(
  String name,
  Map<String, dynamic> data, {
  Duration timeout = const Duration(seconds: 70),
  http.Client? client,
  Future<String?> Function(bool forceRefresh)? idToken,
  Future<String?> Function()? appCheckToken,
  Map<String, String>? extraHeaders,
}) async {
  const base = String.fromEnvironment('FUNCTIONS_BASE_URL');
  final url = base.isNotEmpty ? '$base/$name' : 'https://us-central1-${Firebase.app().options.projectId}.cloudfunctions.net/$name';
  final c = client ?? http.Client();

  Future<http.Response> post({required bool forceRefresh}) async {
    final token = idToken != null ? await idToken(forceRefresh) : await FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh);
    if (token == null) throw const CloudFunctionException('UNAUTHENTICATED', 'Please sign in to continue.');
    String? appCheck;
    try {
      appCheck = appCheckToken != null ? await appCheckToken() : await FirebaseAppCheck.instance.getToken();
    } catch (e) {
      debugPrint('App Check token unavailable: $e');
    }
    return c
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            if (appCheck != null && appCheck.isNotEmpty) 'X-Firebase-AppCheck': appCheck,
            ...?extraHeaders,
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(timeout);
  }

  http.Response res;
  try {
    res = await post(forceRefresh: false);
    if (res.statusCode == 401) res = await post(forceRefresh: true);
  } on CloudFunctionException {
    rethrow;
  } on TimeoutException {
    throw const CloudFunctionException('NETWORK', 'The request timed out. Please retry.');
  } catch (_) {
    throw const CloudFunctionException('NETWORK', 'Network error. Please retry.');
  } finally {
    if (client == null) c.close();
  }

  Map<String, dynamic> body;
  try {
    body = jsonDecode(res.body) as Map<String, dynamic>;
  } catch (_) {
    throw CloudFunctionException('INTERNAL', 'Unexpected server response (${res.statusCode}).');
  }
  if (res.statusCode == 200 && body['result'] is Map) {
    return Map<String, dynamic>.from(body['result'] as Map);
  }
  final err = (body['error'] as Map?) ?? const {};
  throw CloudFunctionException(
    (err['status'] ?? 'INTERNAL').toString(),
    (err['message'] ?? 'The request could not be processed.').toString(),
  );
}
