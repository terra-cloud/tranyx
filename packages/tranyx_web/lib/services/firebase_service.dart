// Firebase REST API service — only imported by @client components (browser-only)
// Uses package:http and package:web for web-safe networking and storage.
// Run jaspr with: --dart-define=ENV=dev   (or uat / prod)

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'package:shared/shared.dart';

// ── Environment Configuration ────────────────────────────────────────────────
class FirebaseConfig {
  final String apiKey;
  final String authDomain;
  final String projectId;
  final String storageBucket;
  final String messagingSenderId;
  final String appId;
  final String? measurementId;

  const FirebaseConfig({
    required this.apiKey,
    required this.authDomain,
    required this.projectId,
    required this.storageBucket,
    required this.messagingSenderId,
    required this.appId,
    this.measurementId,
  });

  factory FirebaseConfig.fromShared(SharedFirebaseOptions options, {String? authDomainOverride}) {
    return FirebaseConfig(
      apiKey: options.apiKey,
      authDomain: authDomainOverride ?? '${options.projectId}.firebaseapp.com',
      projectId: options.projectId,
      storageBucket: options.storageBucket,
      messagingSenderId: options.messagingSenderId,
      appId: options.appId,
    );
  }
}

/// Reads dart-define ENV (dev | uat | prod) and returns the matching Firebase config.
/// Default: dev
FirebaseConfig _getEnvironmentConfig() {
  // Pass with: jaspr serve --dart-define=ENV=dev
  const env = String.fromEnvironment('ENV', defaultValue: 'dev');

  SharedFirebaseOptions options;
  if (env == 'prod') {
    options = DefaultFirebaseConfig.prodWeb;
  } else if (env == 'uat') {
    options = DefaultFirebaseConfig.uatWeb;
  } else {
    options = DefaultFirebaseConfig.devWeb;
  }

  return FirebaseConfig.fromShared(options);
}

final currentFirebaseConfig = _getEnvironmentConfig();

// ── Endpoints ───────────────────────────────────────────────────────────────
const _authBase = 'https://identitytoolkit.googleapis.com/v1/accounts';
String get _firestoreBase =>
    'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents';

// ── Generic HTTP helpers ──────────────────────────────────────────────────────
class SecureFirebaseHttpClient {
  final http.Client _client;
  final Duration requestTimeout;

  // Constructor Dependency Injection (Safe against runtime mutation)
  SecureFirebaseHttpClient({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? mockClient ?? http.Client();

  // Test-only setter using annotation
  @visibleForTesting
  static http.Client? mockClient;

  Future<Map<String, dynamic>> secureRequest(
    String url,
    Future<http.Response> Function(http.Client client) requestBuilder,
  ) async {
    // 1. Enforce HTTPS Protocol check
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') {
      throw SecurityException('Insecure connection scheme prohibited. HTTPS required.');
    }

    try {
      final response = await requestBuilder(_client).timeout(requestTimeout);
      return _parseResponse(response);
    } on http.ClientException catch (e) {
      throw FirebaseException('Network error: ${e.message}');
    }
  }

  Map<String, dynamic> _parseResponse(http.Response response) {
    final bodyText = response.body.trim();
    dynamic decodedJson;

    // 2. Safe JSON Decoding without exposing raw HTML/non-JSON bodies
    if (bodyText.isNotEmpty) {
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        try {
          decodedJson = jsonDecode(bodyText);
        } catch (e) {
          throw FirebaseException('Failed to parse server response securely.');
        }
      } else {
        // Non-JSON response (e.g., HTML Gateway error)
        throw FirebaseException('Invalid response format received from server.', response.statusCode);
      }
    } else {
      decodedJson = <String, dynamic>{};
    }

    if (response.statusCode >= 400) {
      final err = (decodedJson is Map) ? (decodedJson['error'] as Map? ?? {}) : {};
      throw FirebaseException(err['message'] as String? ?? 'Request failed', response.statusCode);
    }

    if (decodedJson is! Map<String, dynamic>) {
      throw FirebaseException('Malformed server response.', response.statusCode);
    }

    return decodedJson;
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}

final _secureClient = SecureFirebaseHttpClient();

http.Client get _client => _secureClient._client;

Future<http.Response> _rawRequestWithRetry(
  String url,
  String? initialToken,
  Future<String?> Function()? onTokenRefresh,
  Future<http.Response> Function(String? token) requestBuilder,
) async {
  var token = initialToken;
  final uri = Uri.parse(url);
  if (uri.scheme != 'https') {
    throw SecurityException('Insecure connection scheme prohibited. HTTPS required.');
  }
  var req = await requestBuilder(token).timeout(_secureClient.requestTimeout);

  if ((req.statusCode == 401 || req.statusCode == 403) && onTokenRefresh != null) {
    try {
      final newToken = await onTokenRefresh();
      if (newToken != null) {
        token = newToken;
        req = await requestBuilder(token).timeout(_secureClient.requestTimeout);
      }
    } catch (_) {
      // Ignore refresh errors and let the original status code propagate
    }
  }
  return req;
}

void _handleGlobalSessionExpiration(FirebaseException e) {
  final lowerMsg = e.message.toLowerCase();
  if (e.statusCode == 401 || lowerMsg.contains('not logged in') || lowerMsg.contains('id-token-expired')) {
    final cb = onSessionExpiredGlobal;
    if (cb != null) cb();
  }
}

Future<Map<String, dynamic>> _requestWithRetry(
  String url,
  String? initialToken,
  Future<String?> Function()? onTokenRefresh,
  Future<http.Response> Function(String? token) requestBuilder,
) async {
  var token = initialToken;
  
  Future<Map<String, dynamic>> makeRequest() async {
    return await _secureClient.secureRequest(url, (client) => requestBuilder(token));
  }

  try {
    return await makeRequest();
  } on FirebaseException catch (e) {
    if ((e.statusCode == 401 || e.statusCode == 403) && onTokenRefresh != null) {
      try {
        final newToken = await onTokenRefresh();
        if (newToken != null) {
          token = newToken;
          try {
            return await makeRequest();
          } on FirebaseException catch (retryErr) {
            _handleGlobalSessionExpiration(retryErr);
            rethrow;
          }
        }
      } catch (_) {
        // Ignore refresh errors
      }
    }
    _handleGlobalSessionExpiration(e);
    rethrow;
  }
}

Future<Map<String, dynamic>> _post(
  String url,
  Map<String, dynamic> body, {
  String? idToken,
  Future<String?> Function()? onTokenRefresh,
}) async {
  return _requestWithRetry(url, idToken, onTokenRefresh, (token) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return _client.post(Uri.parse(url), headers: headers, body: jsonEncode(body));
  });
}

Future<Map<String, dynamic>> _get(String url, {String? idToken, Future<String?> Function()? onTokenRefresh}) async {
  return _requestWithRetry(url, idToken, onTokenRefresh, (token) {
    final headers = <String, String>{};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return _client.get(Uri.parse(url), headers: headers);
  });
}

Future<Map<String, dynamic>> _patch(
  String url,
  Map<String, dynamic> body, [
  String? idToken,
  Future<String?> Function()? onTokenRefresh,
]) async {
  return _requestWithRetry(url, idToken, onTokenRefresh, (token) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return _client.patch(Uri.parse(url), headers: headers, body: jsonEncode(body));
  });
}

// ── Auth service ──────────────────────────────────────────────────────────────
// Global callback to notify app of expired sessions / unauthorized requests
void Function()? onSessionExpiredGlobal;

class FirebaseException implements Exception {
  final String message;
  final int? statusCode;
  FirebaseException(this.message, [this.statusCode]) {
    final lowerMsg = message.toLowerCase();
    if (statusCode == 401 || lowerMsg.contains('not logged in') || lowerMsg.contains('id-token-expired')) {
      final cb = onSessionExpiredGlobal;
      if (cb != null) cb();
    }
  }
  @override
  String toString() => message;
}

class AuthResult {
  final String uid;
  final String idToken;
  final String? refreshToken;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  AuthResult({
    required this.uid,
    required this.idToken,
    this.refreshToken,
    this.email,
    this.displayName,
    this.photoUrl,
  });
}

class SecureTokenRefreshManager {
  final Future<String> Function(String) refreshIdTokenCallback;
  Future<String>? _activeRefreshFuture;

  SecureTokenRefreshManager(this.refreshIdTokenCallback);

  Future<String> refresh(String refreshToken) {
    if (_activeRefreshFuture != null) {
      return _activeRefreshFuture!;
    }

    // Set a strict timeout guard to prevent permanent deadlocks
    _activeRefreshFuture = refreshIdTokenCallback(refreshToken)
        .timeout(const Duration(seconds: 10))
        .catchError((Object error) {
          // Reset future so subsequent attempts can retry
          _activeRefreshFuture = null;
          throw error;
        })
        .whenComplete(() {
          _activeRefreshFuture = null; // Clean up active state
        });

    return _activeRefreshFuture!;
  }
}

class FirebaseAuthService {
  late final SecureTokenRefreshManager _refreshManager = SecureTokenRefreshManager((token) async {
    final url = 'https://securetoken.googleapis.com/v1/token?key=${currentFirebaseConfig.apiKey}';
    final res = await _post(url, {
      'grant_type': 'refresh_token',
      'refresh_token': token,
    });
    return res['id_token'] as String;
  });

  Future<AuthResult> signIn(String email, String password) async {
    final res = await _post(
      '$_authBase:signInWithPassword?key=${currentFirebaseConfig.apiKey}',
      {'email': email, 'password': password, 'returnSecureToken': true},
    );
    return AuthResult(
      uid: res['localId'] as String,
      idToken: res['idToken'] as String,
      refreshToken: res['refreshToken'] as String?,
      email: res['email'] as String?,
      displayName: res['displayName'] as String?,
    );
  }

  Future<AuthResult> register(String email, String password) async {
    final res = await _post(
      '$_authBase:signUp?key=${currentFirebaseConfig.apiKey}',
      {'email': email, 'password': password, 'returnSecureToken': true},
    );
    return AuthResult(
      uid: res['localId'] as String,
      idToken: res['idToken'] as String,
      refreshToken: res['refreshToken'] as String?,
      email: res['email'] as String?,
    );
  }

  Future<AuthResult> signInWithGoogle(String googleIdToken) async {
    final res = await _post(
      '$_authBase:signInWithIdp?key=${currentFirebaseConfig.apiKey}',
      {
        'postBody': 'id_token=$googleIdToken&providerId=google.com',
        'requestUri': 'http://localhost',
        'returnIdpCredential': true,
        'returnSecureToken': true,
      },
    );
    return AuthResult(
      uid: res['localId'] as String,
      idToken: res['idToken'] as String,
      refreshToken: res['refreshToken'] as String?,
      email: res['email'] as String?,
      displayName: res['displayName'] as String?,
      photoUrl: res['photoUrl'] as String?,
    );
  }

  Future<void> updateDisplayName(String idToken, String displayName) async {
    await _post(
      '$_authBase:update?key=${currentFirebaseConfig.apiKey}',
      {'idToken': idToken, 'displayName': displayName, 'returnSecureToken': false},
    );
  }

  Future<void> resetPassword(String email) async {
    await _post(
      '$_authBase:sendOobCode?key=${currentFirebaseConfig.apiKey}',
      {'requestType': 'PASSWORD_RESET', 'email': email},
    );
  }

  Future<String> refreshIdToken(String refreshToken) async {
    return _refreshManager.refresh(refreshToken);
  }

  /// Lookup a user by idToken to get uid/email/displayName
  Future<Map<String, dynamic>> getUserData(String idToken) async {
    final res = await _post(
      '$_authBase:lookup?key=${currentFirebaseConfig.apiKey}',
      {'idToken': idToken},
    );
    final users = res['users'] as List?;
    if (users == null || users.isEmpty) throw FirebaseException('User not found');
    return users.first as Map<String, dynamic>;
  }

  /// Send an email verification link to the user
  Future<void> sendEmailVerification(String idToken) async {
    await _post(
      '$_authBase:sendOobCode?key=${currentFirebaseConfig.apiKey}',
      {
        'requestType': 'VERIFY_EMAIL',
        'idToken': idToken,
      },
    );
  }

  /// Sends a SMS verification OTP code to the given phone number
  Future<String> sendSmsVerificationCode(String phoneNumber) async {
    final res = await _post(
      '$_authBase:sendVerificationCode?key=${currentFirebaseConfig.apiKey}',
      {
        'phoneNumber': phoneNumber,
      },
    );
    return res['sessionInfo'] as String? ?? '';
  }

  /// Verifies the SMS OTP code sent to the phone number
  Future<Map<String, dynamic>> verifySmsCode(String sessionInfo, String code) async {
    return await _post(
      '$_authBase:signInWithPhoneNumber?key=${currentFirebaseConfig.apiKey}',
      {
        'sessionInfo': sessionInfo,
        'code': code,
      },
    );
  }
}

// ── Firestore value encoding / decoding ───────────────────────────────────────
Map<String, dynamic> _toFirestoreFields(Map<String, dynamic> data) {
  Map<String, dynamic> encodeValue(dynamic v) {
    if (v == null) return {'nullValue': null};
    if (v is bool) return {'booleanValue': v};
    if (v is int) return {'integerValue': v.toString()};
    if (v is double) return {'doubleValue': v};
    if (v is String) return {'stringValue': v};
    if (v is List) {
      return {
        'arrayValue': {
          'values': v.map(encodeValue).toList(),
        },
      };
    }
    if (v is Map) {
      return {
        'mapValue': {
          'fields': {
            for (final e in v.entries) e.key: encodeValue(e.value),
          },
        },
      };
    }
    return {'stringValue': v.toString()};
  }

  return {
    'fields': {
      for (final e in data.entries)
        if (e.value != null) e.key: encodeValue(e.value),
    },
  };
}

Map<String, dynamic> _fromFirestoreDoc(Map<String, dynamic> doc) {
  dynamic decodeValue(Map<String, dynamic> val) {
    if (val.containsKey('nullValue')) return null;
    if (val.containsKey('booleanValue')) return val['booleanValue'] as bool;
    if (val.containsKey('integerValue')) return int.parse(val['integerValue'].toString());
    if (val.containsKey('doubleValue')) return (val['doubleValue'] as num).toDouble();
    if (val.containsKey('stringValue')) return val['stringValue'] as String;
    if (val.containsKey('arrayValue')) {
      final arr = val['arrayValue'] as Map;
      final vals = arr['values'] as List? ?? [];
      return vals.map((v) => decodeValue(v as Map<String, dynamic>)).toList();
    }
    if (val.containsKey('mapValue')) {
      final fields = (val['mapValue'] as Map)['fields'] as Map? ?? {};
      return {
        for (final e in fields.entries) e.key: decodeValue(e.value as Map<String, dynamic>),
      };
    }
    return null;
  }

  final fields = doc['fields'] as Map<String, dynamic>? ?? {};
  return {
    for (final e in fields.entries) e.key: decodeValue(e.value as Map<String, dynamic>),
  };
}

/// Extract document ID from a Firestore document name path.
String _docId(Map<String, dynamic> doc) {
  final name = doc['name'] as String? ?? '';
  return name.split('/').last;
}

// ── Firestore service ─────────────────────────────────────────────────────────
class FirestoreService {
  String? idToken;
  final Future<String?> Function()? onTokenRefresh;

  FirestoreService([
    this.idToken,
    this.onTokenRefresh,
  ]);

  Future<String?> _refreshToken() async {
    if (onTokenRefresh != null) {
      final newToken = await onTokenRefresh!();
      if (newToken != null) {
        idToken = newToken;
        return newToken;
      }
    }
    return null;
  }

  // ── Utility ────────────────────────────────────────────────
  Future<void> setDocument(String path, Map<String, dynamic> data) async {
    if (data.isEmpty) return;
    final url = '$_firestoreBase/$path';
    final body = _toFirestoreFields(data);
    final queryString = data.keys.map((k) => 'updateMask.fieldPaths=$k').join('&');
    await _patch(
      '$url?$queryString',
      body,
      idToken,
      _refreshToken,
    );
  }

  Future<void> createOrUpdate(String path, Map<String, dynamic> data) async {
    final url = '$_firestoreBase/$path';
    final body = _toFirestoreFields(data);
    await _patch(url, body, idToken, _refreshToken);
  }

  Future<void> deleteDocument(String path) async {
    final url = '$_firestoreBase/$path';
    await _requestWithRetry(url, idToken, _refreshToken, (token) {
      final headers = <String, String>{};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      return _client.delete(Uri.parse(url), headers: headers);
    });
  }

  Future<Map<String, dynamic>?> getDocument(String path) async {
    try {
      final url = '$_firestoreBase/$path';
      final res = await _get(url, idToken: idToken, onTokenRefresh: _refreshToken);
      if (res.isEmpty || !res.containsKey('fields')) return null;
      return _fromFirestoreDoc(res);
    } on FirebaseException {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getEscrow(String jobId) async {
    return await getDocument('escrow/$jobId');
  }

  // ── Users ──────────────────────────────────────────────────
  Future<UserProfile?> getUser(String uid) async {
    final data = await getDocument('users/$uid');
    if (data == null) return null;
    return UserProfile.fromMap(uid, data);
  }

  Future<List<Map<String, dynamic>>> getReviews(String uid) async {
    final url = '$_firestoreBase/users/$uid/reviews';
    try {
      final data = await _get(url, idToken: idToken, onTokenRefresh: _refreshToken);
      final docs = data['documents'] as List? ?? [];
      final result = docs.map((d) {
        final doc = d as Map<String, dynamic>;
        final id = _docId(doc);
        return {..._fromFirestoreDoc(doc), 'id': id};
      }).toList();
      result.sort((a, b) => (b['timestamp'] as int? ?? 0).compareTo(a['timestamp'] as int? ?? 0));
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveUser(UserProfile profile) async {
    await createOrUpdate('users/${profile.uid}', profile.toMap());
  }

  // ── KYC Submissions ────────────────────────────────────────
  Future<Map<String, dynamic>?> getKycSubmission(String uid) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'kyc_submissions'},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'uid'},
            'op': 'EQUAL',
            'value': {'stringValue': uid},
          },
        },
        'limit': 1,
      },
    });

    try {
      final req = await _rawRequestWithRetry(url, idToken, _refreshToken, (token) {
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        return _client.post(Uri.parse(url), headers: headers, body: body);
      });

      if (req.statusCode >= 400) return null;

      final List<dynamic> results = jsonDecode(req.body);
      for (final res in results) {
        if (res is Map<String, dynamic> && res.containsKey('document')) {
          final doc = res['document'] as Map<String, dynamic>;
          return _fromFirestoreDoc(doc);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveKycSubmission(String uid, Map<String, dynamic> data) async {
    await createOrUpdate('kyc_submissions/$uid', data);
  }

  Future<List<Map<String, dynamic>>> getEscrowHoldbacks(String uid, {required bool isNyxian}) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'escrow_holdbacks'},
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': isNyxian ? 'nyxianId' : 'employerId'},
                  'op': 'EQUAL',
                  'value': {'stringValue': uid},
                },
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'status'},
                  'op': 'EQUAL',
                  'value': {'stringValue': 'held'},
                },
              },
            ],
          },
        },
      },
    });

    try {
      final req = await _rawRequestWithRetry(url, idToken, _refreshToken, (token) {
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        return _client.post(Uri.parse(url), headers: headers, body: body);
      });

      if (req.statusCode >= 400) {
        return [];
      }

      final List<dynamic> results = jsonDecode(req.body);
      final holdbacks = <Map<String, dynamic>>[];
      for (final res in results) {
        if (res is Map<String, dynamic> && res.containsKey('document')) {
          final doc = res['document'] as Map<String, dynamic>;
          final id = _docId(doc);
          holdbacks.add({..._fromFirestoreDoc(doc), 'id': id});
        }
      }
      return holdbacks;
    } catch (_) {
      return [];
    }
  }

  // ── Wallet Links ───────────────────────────────────────────
  /// Stores a mapping from walletPublicKey -> uid in walletLinks collection.
  Future<void> linkWalletToUser(String uid, String walletPublicKey, {String? refreshToken}) async {
    final existingLink = await getWalletLink(walletPublicKey);
    if (existingLink != null) {
      final existingUid = existingLink['uid'] as String?;
      if (existingUid != null && existingUid != uid) {
        throw Exception('This wallet is already linked to another account. Each wallet can only be connected to one account.');
      }
    }

    final data = <String, dynamic>{
      'uid': uid,
      'linkedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (refreshToken != null) {
      data['refreshToken'] = refreshToken;
    }
    await createOrUpdate('walletLinks/$walletPublicKey', data);
    // Also store walletPublicKey on the user document for reference
    await setDocument('users/$uid', {'walletPublicKey': walletPublicKey});
  }

  /// Looks up the Firebase wallet link data for a given Phantom wallet public key.
  /// Returns null if no account is linked.
  Future<Map<String, dynamic>?> getWalletLink(String walletPublicKey) async {
    return await getDocument('walletLinks/$walletPublicKey');
  }

  @Deprecated('Use getWalletLink instead')
  Future<String?> getUidByWalletKey(String walletPublicKey) async {
    final doc = await getDocument('walletLinks/$walletPublicKey');
    return doc?['uid'] as String?;
  }

  // ── Jobs ───────────────────────────────────────────────────

  /// Create a new job; returns the Firestore document ID.
  Future<String> createJob(Map<String, dynamic> jobData) async {
    final url = '$_firestoreBase/jobs';
    final result = await _post(
      url,
      _toFirestoreFields(jobData),
      idToken: idToken,
      onTokenRefresh: _refreshToken,
    );
    final docId = _docId(result);
    await setDocument('jobs/$docId', {'id': docId});

    final creatorId = jobData['creatorId'] as String?;
    if (creatorId != null) {
      await awardPointsIfEligible(creatorId, 'post_first_service');
    }

    return docId;
  }

  /// Fetch all jobs created by [uid].
  Future<List<Map<String, dynamic>>> getMyJobs(String uid) async {
    return _queryJobs([
      {
        'fieldFilter': {
          'field': {'fieldPath': 'creatorId'},
          'op': 'EQUAL',
          'value': {'stringValue': uid},
        },
      },
    ]);
  }

  /// Fetch all transactions for [uid].
  Future<List<Map<String, dynamic>>> getMyTransactions(String uid) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'transactions'},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'uid'},
            'op': 'EQUAL',
            'value': {'stringValue': uid},
          },
        },
      },
    });

    try {
      final req = await _rawRequestWithRetry(url, idToken, _refreshToken, (token) {
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        return _client.post(Uri.parse(url), headers: headers, body: body);
      });

      if (req.statusCode >= 400) {
        return [];
      }

      final List<dynamic> results = jsonDecode(req.body);
      final transactions = <Map<String, dynamic>>[];
      for (final res in results) {
        if (res is Map<String, dynamic> && res.containsKey('document')) {
          final doc = res['document'] as Map<String, dynamic>;
          final id = _docId(doc);
          transactions.add({..._fromFirestoreDoc(doc), 'id': id});
        }
      }
      return transactions;
    } catch (_) {
      return [];
    }
  }

  /// Fetch notifications for [uid].
  Future<List<Map<String, dynamic>>> getNotifications(String uid) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'notifications'},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'uid'},
            'op': 'EQUAL',
            'value': {'stringValue': uid},
          },
        },
      },
    });

    try {
      final req = await _rawRequestWithRetry(url, idToken, _refreshToken, (token) {
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        return _client.post(Uri.parse(url), headers: headers, body: body);
      });

      if (req.statusCode >= 400) {
        return [];
      }

      final List<dynamic> results = jsonDecode(req.body);
      final notifications = <Map<String, dynamic>>[];
      for (final res in results) {
        if (res is Map<String, dynamic> && res.containsKey('document')) {
          final doc = res['document'] as Map<String, dynamic>;
          final id = _docId(doc);
          notifications.add({..._fromFirestoreDoc(doc), 'id': id});
        }
      }
      return notifications;
    } catch (_) {
      return [];
    }
  }

  Future<void> createNotification({
    required String uid,
    required String title,
    required String message,
  }) async {
    final docId = 'notif_${DateTime.now().millisecondsSinceEpoch}_${uid.substring(0, min(5, uid.length))}';
    await createOrUpdate('notifications/$docId', {
      'uid': uid,
      'title': title,
      'message': message,
      'isRead': false,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Fetch all jobs where the user is the accepted applicant.
  Future<List<Map<String, dynamic>>> getAcceptedJobs(String uid) async {
    return _queryJobs([
      {
        'fieldFilter': {
          'field': {'fieldPath': 'acceptedApplicantId'},
          'op': 'EQUAL',
          'value': {'stringValue': uid},
        },
      },
    ]);
  }

  /// Fetch all jobs where the user has applied.
  Future<List<Map<String, dynamic>>> getAppliedJobs(String uid) async {
    return _queryJobs([
      {
        'fieldFilter': {
          'field': {'fieldPath': 'applicantUids'},
          'op': 'ARRAY_CONTAINS',
          'value': {'stringValue': uid},
        },
      },
    ], orderByCreatedAt: false);
  }

  /// Fetch available jobs for the given viewer type.
  /// Nyxians see Employer postings; Employers see Nyxian postings.
  Future<List<Map<String, dynamic>>> getAvailableJobs(AccountType viewerType) async {
    final creatorTypeToFetch = viewerType == AccountType.nyxian ? AccountType.employer : AccountType.nyxian;

    return _queryJobs([
      {
        'fieldFilter': {
          'field': {'fieldPath': 'creatorType'},
          'op': 'EQUAL',
          'value': {'stringValue': creatorTypeToFetch.name},
        },
      },
      {
        'fieldFilter': {
          'field': {'fieldPath': 'status'},
          'op': 'EQUAL',
          'value': {'stringValue': 'Open'},
        },
      },
    ]);
  }

  Future<void> updateJobStatus(String jobId, String status) async {
    await setDocument('jobs/$jobId', {'status': status});
  }

  Future<void> updateTyxBalance(String uid, double balance) async {
    await setDocument('users/$uid', {'tyxBalance': balance});
  }

  Future<List<Map<String, dynamic>>> _queryJobs(List<Map<String, dynamic>> filters, {bool orderByCreatedAt = true}) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    
    final Map<String, dynamic> structuredQuery = {
      'from': [
        {'collectionId': 'jobs'},
      ],
      'where': filters.length == 1
          ? filters.first
          : {
              'compositeFilter': {
                'op': 'AND',
                'filters': filters,
              },
            },
      'limit': 50,
    };

    if (orderByCreatedAt) {
      structuredQuery['orderBy'] = [
        {
          'field': {'fieldPath': 'createdAt'},
          'direction': 'DESCENDING',
        },
      ];
    }

    final body = jsonEncode({
      'structuredQuery': structuredQuery,
    });

    try {
      final req = await _rawRequestWithRetry(url, idToken, _refreshToken, (token) {
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        return _client.post(Uri.parse(url), headers: headers, body: body);
      });

      if (req.statusCode >= 400) {
        print('FIRESTORE QUERY ERROR: ${req.statusCode} - ${req.body}');
        return [];
      }

      final results = jsonDecode(req.body) as List;
      final list = results.where((r) => (r as Map).containsKey('document')).map((r) {
        final doc = (r as Map<String, dynamic>)['document'] as Map<String, dynamic>;
        final id = _docId(doc);
        return {..._fromFirestoreDoc(doc), 'id': id};
      }).toList();

      if (!orderByCreatedAt) {
        list.sort((a, b) => (b['createdAt'] as int? ?? 0).compareTo(a['createdAt'] as int? ?? 0));
      }
      return list;
    } catch (e) {
      print('FIRESTORE QUERY ERROR: $e');
      return [];
    }
  }

  // ── Applications ───────────────────────────────────────────

  Future<void> applyToJob({
    required String jobId,
    required String applicantUid,
    required String applicantName,
    String? applicantPhotoUrl,
    required String coverNote,
    required double proposalRate,
    required bool isCounterOffer,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final appData = {
      'jobId': jobId,
      'applicantUid': applicantUid,
      'applicantName': applicantName,
      'applicantPhotoUrl': applicantPhotoUrl,
      'coverNote': coverNote,
      'proposalRate': proposalRate,
      'isCounterOffer': isCounterOffer,
      'createdAt': now,
    };
    // Write application sub-document
    await createOrUpdate('jobs/$jobId/applications/$applicantUid', appData);
    await awardPointsIfEligible(applicantUid, 'apply_first_job');
    // Update job applicantCount and applicantUids (best-effort, no transactions in REST)
    final jobDoc = await getDocument('jobs/$jobId');
    if (jobDoc != null) {
      final uids = List<String>.from(jobDoc['applicantUids'] as List? ?? []);
      if (!uids.contains(applicantUid)) {
        uids.add(applicantUid);
        final count = (jobDoc['applicantCount'] as int? ?? 0) + 1;
        await createOrUpdate('jobs/$jobId', {
          ...jobDoc,
          'applicantUids': uids,
          'applicantCount': count,
        });
      }

      // Notify the employer/creator about the new job application
      final creatorId = jobDoc['creatorId'] as String?;
      final jobTitle = jobDoc['title'] as String? ?? 'Your Posting';
      if (creatorId != null && creatorId != applicantUid) {
        await createNotification(
          uid: creatorId,
          title: 'New Job Application',
          message: '$applicantName has applied to your posting "$jobTitle".',
        );
      }
    }
  }

  /// Update vehicle GPS Tracker ID
  Future<void> updateVehicleGpsTracker(String rentalId, String gpsTrackerId) async {
    await setDocument('rentals/$rentalId', {'gpsTrackerId': gpsTrackerId});
  }

  Future<List<Map<String, dynamic>>> getApplications(String jobId) async {
    final url = '$_firestoreBase/jobs/$jobId/applications';
    try {
      final data = await _get(url, idToken: idToken, onTokenRefresh: _refreshToken);
      final docs = data['documents'] as List? ?? [];
      return docs.map((d) {
        final doc = d as Map<String, dynamic>;
        final id = _docId(doc);
        return {..._fromFirestoreDoc(doc), 'id': id};
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Chat Messages ──────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getChatMessages(String jobId) async {
    final url = '$_firestoreBase/jobs/$jobId/messages';
    try {
      final data = await _get(url, idToken: idToken, onTokenRefresh: _refreshToken);
      final docs = data['documents'] as List? ?? [];
      final messages = docs.map((d) {
        final doc = d as Map<String, dynamic>;
        final id = _docId(doc);
        return {..._fromFirestoreDoc(doc), 'id': id};
      }).toList();

      // Sort by timestamp ascending
      messages.sort((a, b) => (a['timestamp'] as int? ?? 0).compareTo(b['timestamp'] as int? ?? 0));
      return messages;
    } catch (_) {
      return [];
    }
  }

  Future<void> sendChatMessage({
    required String jobId,
    required String messageId,
    required String senderId,
    required String senderName,
    String? senderPhotoUrl,
    required String text,
    String? imageUrl,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final messageData = {
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': ?senderPhotoUrl,
      'text': text,
      'imageUrl': ?imageUrl,
      'timestamp': now,
    };

    final url = '$_firestoreBase/jobs/$jobId/messages/$messageId';
    final body = _toFirestoreFields(messageData);
    await _patch(url, body, idToken, _refreshToken);
  }

  // ── Agent Support Chat ─────────────────────────────────────
  
  Future<List<Map<String, dynamic>>> getAgentSupportChatMessages(String uid) async {
    final url = '$_firestoreBase/support_chats/$uid/messages';
    try {
      final data = await _get(url, idToken: idToken, onTokenRefresh: _refreshToken);
      final docs = data['documents'] as List? ?? [];
      final messages = docs.map((d) {
        final doc = d as Map<String, dynamic>;
        final id = _docId(doc);
        return {..._fromFirestoreDoc(doc), 'id': id};
      }).toList();

      // Sort by createdAt ascending
      messages.sort((a, b) => (a['createdAt'] as int? ?? 0).compareTo(b['createdAt'] as int? ?? 0));
      return messages;
    } catch (_) {
      return [];
    }
  }

  Future<void> sendAgentSupportChatMessage({
    required String uid,
    required String messageId,
    required String senderId,
    required String senderName,
    required String content,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final messageData = {
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'createdAt': now,
    };

    final url = '$_firestoreBase/support_chats/$uid/messages/$messageId';
    final body = _toFirestoreFields(messageData);
    await _patch(url, body, idToken, _refreshToken);

    // Also update parent chat document
    await createOrUpdate('support_chats/$uid', {
      'lastMessage': content,
      'updatedAt': now,
      'userIds': [uid],
    });
  }

  Future<void> initiateAgentSupportChat({
    required String uid,
    required String messageId,
    required String senderId,
    required String senderName,
    required String content,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Set parent chat
    await createOrUpdate('support_chats/$uid', {
      'lastMessage': content,
      'updatedAt': now,
      'userIds': [uid],
    });
    // Add first message
    await sendAgentSupportChatMessage(
      uid: uid,
      messageId: messageId,
      senderId: senderId,
      senderName: senderName,
      content: content,
    );
  }

  // ── Questions ──────────────────────────────────────────────

  Future<String> addQuestion({
    required String jobId,
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
    required String questionText,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final questionData = {
      'jobId': jobId,
      'authorId': authorId,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'questionText': questionText,
      'answerText': null,
      'createdAt': now,
    };
    final url = '$_firestoreBase/jobs/$jobId/questions';
    final result = await _post(
      url,
      _toFirestoreFields(questionData),
      idToken: idToken,
      onTokenRefresh: _refreshToken,
    );
    return _docId(result);
  }

  Future<void> answerQuestion({
    required String jobId,
    required String questionId,
    required String answer,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final doc = await getDocument('jobs/$jobId/questions/$questionId');
    if (doc != null) {
      await createOrUpdate('jobs/$jobId/questions/$questionId', {
        ...doc,
        'answerText': answer,
        'answeredAt': now,
      });
    }
  }

  Future<void> deleteQuestion(String jobId, String questionId) async {
    final url = '$_firestoreBase/jobs/$jobId/questions/$questionId';
    await _requestWithRetry(url, idToken, _refreshToken, (token) {
      final headers = <String, String>{};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      return _client.delete(Uri.parse(url), headers: headers);
    });
  }

  Future<void> toggleQuestionLike(String jobId, String questionId, String uid, bool isLiked) async {
    final doc = await getDocument('jobs/$jobId/questions/$questionId');
    if (doc != null) {
      final likes = List<String>.from(doc['likedByUids'] as List? ?? []);
      if (isLiked && !likes.contains(uid)) likes.add(uid);
      if (!isLiked && likes.contains(uid)) likes.remove(uid);
      await createOrUpdate('jobs/$jobId/questions/$questionId', {
        ...doc,
        'likedByUids': likes,
      });
    }
  }

  Future<void> reportJob(String jobId, String employerId, String reporterUid, String reason) async {
    // 1. Update job document with report
    final jobDoc = await getDocument('jobs/$jobId');
    if (jobDoc != null) {
      final reportedBy = List<String>.from(jobDoc['reportedByUids'] as List? ?? []);
      if (reportedBy.contains(reporterUid)) return; // Already reported
      reportedBy.add(reporterUid);

      final reports = List<Map<String, dynamic>>.from(jobDoc['reports'] as List? ?? []);
      reports.add({'uid': reporterUid, 'reason': reason, 'timestamp': DateTime.now().millisecondsSinceEpoch});

      final reportCount = (jobDoc['reportCount'] as int? ?? 0) + 1;
      await createOrUpdate('jobs/$jobId', {
        ...jobDoc,
        'reportedByUids': reportedBy,
        'reports': reports,
        'reportCount': reportCount,
      });
    }

    // 2. Deduct from employer profile
    final empDoc = await getDocument('users/$employerId');
    if (empDoc != null) {
      final currentRating = (empDoc['rating'] as num?)?.toDouble() ?? 0.0;
      final newRating = (currentRating - 0.5).clamp(1.0, 5.0);
      await createOrUpdate('users/$employerId', {
        ...empDoc,
        'rating': newRating,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getQuestions(String jobId) async {
    final url = '$_firestoreBase/jobs/$jobId/questions';
    try {
      final data = await _get(url, idToken: idToken, onTokenRefresh: _refreshToken);
      final docs = data['documents'] as List? ?? [];
      final result = docs.map((d) {
        final doc = d as Map<String, dynamic>;
        final id = _docId(doc);
        return {..._fromFirestoreDoc(doc), 'id': id};
      }).toList();
      result.sort((a, b) => (a['createdAt'] as int? ?? 0).compareTo(b['createdAt'] as int? ?? 0));
      return result;
    } catch (_) {
      return [];
    }
  }

  // ── Vehicle Rentals ──────────────────────────────────────────

  /// Create a new vehicle rental posting, deducting 1.5% listing fee
  Future<String> createRental(VehicleRental rental) async {
    final host = await getUser(rental.hostId);
    if (host == null) {
      throw Exception('Host profile not found.');
    }
    final listingFee = 0.015 * rental.priceDaily;
    if (host.tyxBalance < listingFee) {
      throw Exception(
        'Insufficient balance. Listing fee requires ${listingFee.toStringAsFixed(2)} TYXBIT, but your balance is ${host.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Deduct fee
    final newBalance = host.tyxBalance - listingFee;
    await updateTyxBalance(rental.hostId, newBalance);

    // Save transaction record
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    final txData = {
      'uid': rental.hostId,
      'type': 'listing_fee',
      'amount': listingFee,
      'title': 'Vehicle Listing Fee',
      'desc': '1.5% posting fee for ${rental.brand} ${rental.model} (${rental.year})',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('transactions/$txId', txData);

    // Post rental document
    final url = '$_firestoreBase/rentals';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final req = await _client.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(_toFirestoreFields(rental.toMap())),
    );

    if (req.statusCode >= 400) {
      final data = jsonDecode(req.body) as Map<String, dynamic>;
      final err = data['error'] as Map? ?? {};
      throw FirebaseException(err['message'] as String? ?? 'Create rental failed', req.statusCode);
    }

    final result = jsonDecode(req.body) as Map<String, dynamic>;
    final docId = _docId(result);
    await setDocument('rentals/$docId', {'id': docId});
    return docId;
  }

  /// Creates a vehicle rental from a pre-built map (allows extra fields like gpsTrackerId).
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

    final newBalance = host.tyxBalance - listingFee;
    await updateTyxBalance(hostId, newBalance);

    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    await setDocument('transactions/$txId', {
      'uid': hostId,
      'type': 'listing_fee',
      'amount': listingFee,
      'title': 'Vehicle Listing Fee',
      'desc': '1.5% posting fee for $brand $model ($year)',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    final url = '$_firestoreBase/rentals';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final req = await _client.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(_toFirestoreFields(rentalMap)),
    );

    if (req.statusCode >= 400) {
      final data = jsonDecode(req.body) as Map<String, dynamic>;
      final err = data['error'] as Map? ?? {};
      throw FirebaseException(err['message'] as String? ?? 'Create rental failed', req.statusCode);
    }

    final result = jsonDecode(req.body) as Map<String, dynamic>;
    final docId = _docId(result);
    await setDocument('rentals/$docId', {'id': docId});
    return docId;
  }

  /// Delete rental posting and refund listing fee
  Future<void> deleteRental(String rentalId) async {
    final rentalDoc = await getDocument('rentals/$rentalId');
    if (rentalDoc == null) throw Exception('Rental listing not found.');

    final rental = VehicleRental.fromMap(rentalDoc, rentalId);

    // Safety check: Cannot delete booked or ongoing rentals
    if (rental.status != 'Available') {
      throw Exception('Cannot delete a vehicle listing that is currently booked or active.');
    }

    // Fetch all pending requests for this vehicle and reject/refund them
    final pendingRequests = await getPendingRequestsForVehicle(rentalId);
    for (final req in pendingRequests) {
      final requestId = req['id'] as String;
      try {
        await rejectBookingRequest(requestId);
      } catch (e) {
        print('Error rejecting request $requestId during vehicle deletion: $e');
      }
    }

    await deleteDocument('rentals/$rentalId');
  }

  /// Fetch all rentals
  Future<List<VehicleRental>> getRentals() async {
    final url = '$_firestoreBase/rentals';
    final headers = <String, String>{};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final req = await _client.get(Uri.parse(url), headers: headers);
    if (req.statusCode >= 400) return [];

    final data = jsonDecode(req.body) as Map<String, dynamic>;
    final docs = data['documents'] as List? ?? [];
    return docs.map((d) {
      final doc = d as Map<String, dynamic>;
      final id = _docId(doc);
      return VehicleRental.fromMap(_fromFirestoreDoc(doc), id);
    }).toList();
  }

  /// Fetch specific rental
  Future<VehicleRental?> getRental(String rentalId) async {
    final doc = await getDocument('rentals/$rentalId');
    if (doc == null) return null;
    return VehicleRental.fromMap(doc, rentalId);
  }

  /// Book a vehicle rental (includes escrow payment with 3% renter booking fee)
  Future<void> bookRental({
    required String rentalId,
    required String renteeId,
    required String renteeName,
    required String? renteePhotoUrl,
    required String durationType,
    required int multiplier,
    required String signatureName,
    required String licenseNumber,
    required double totalCost,
  }) async {
    final rentalDoc = await getDocument('rentals/$rentalId');
    if (rentalDoc == null) throw Exception('Rental listing not found.');
    final rental = VehicleRental.fromMap(rentalDoc, rentalId);

    if (rental.status != 'Available') {
      throw Exception('Vehicle is no longer available for booking.');
    }

    final rentee = await getUser(renteeId);
    if (rentee == null) throw Exception('Renter profile not found.');

    final bookingFee = totalCost * 0.03;
    final totalRequired = totalCost + bookingFee;

    if (rentee.tyxBalance < totalRequired) {
      throw Exception(
        'Insufficient balance. Required: ${totalRequired.toStringAsFixed(2)} TYXBIT (including 3% booking fee), but available: ${rentee.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Deduct from renter
    final newRenterBalance = rentee.tyxBalance - totalRequired;
    await updateTyxBalance(renteeId, newRenterBalance);

    // Save transaction record for renter
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    final txData = {
      'uid': renteeId,
      'type': 'payment',
      'amount': totalRequired,
      'title': 'Vehicle Booking',
      'desc': 'Booked ${rental.brand} ${rental.model} for $multiplier $durationType(s)',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('transactions/$txId', txData);

    // Put funds in Escrow
    final escrowDoc = {
      'rentalId': rentalId,
      'renteeId': renteeId,
      'hostId': rental.hostId,
      'amount': totalCost,
      'status': 'Held',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('rental_escrows/$rentalId', escrowDoc);

    // Update rental document with booking details
    final now = DateTime.now();
    Duration duration;
    if (durationType == '12h') {
      duration = Duration(hours: 12 * multiplier);
    } else if (durationType == 'weekly') {
      duration = Duration(days: 7 * multiplier);
    } else if (durationType == 'monthly') {
      duration = Duration(days: 30 * multiplier);
    } else {
      // daily
      duration = Duration(days: multiplier);
    }
    final endDate = now.add(duration);

    final updatedData = {
      'status': 'Booked',
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': renteePhotoUrl,
      'rentalDurationType': durationType,
      'rentalMultiplier': multiplier,
      'startDate': now.millisecondsSinceEpoch,
      'endDate': endDate.millisecondsSinceEpoch,
      'totalCost': totalCost,
      'renteeSignatureName': signatureName,
      'renteeLicenseNumber': licenseNumber,
      'signedAt': now.millisecondsSinceEpoch,
      'trackingLat': rental.pickupLat,
      'trackingLng': rental.pickupLng,
    };

    await setDocument('rentals/$rentalId', updatedData);

    // Create notifications for both parties
    await createNotification(
      uid: rental.hostId,
      title: 'Vehicle Booked',
      message: 'Your vehicle ${rental.brand} ${rental.model} has been booked by $renteeName.',
    );
    await createNotification(
      uid: renteeId,
      title: 'Rental Booking Successful',
      message: 'You have booked ${rental.brand} ${rental.model}. Please sign terms and coordinate pickup.',
    );
  }

  /// Update rental status
  Future<void> updateRentalStatus(String rentalId, String status) async {
    await setDocument('rentals/$rentalId', {'status': status});

    final rentalDoc = await getDocument('rentals/$rentalId');
    if (rentalDoc != null) {
      final rental = VehicleRental.fromMap(rentalDoc, rentalId);
      // Notify rentee if status changes
      if (rental.renteeId != null) {
        await createNotification(
          uid: rental.renteeId!,
          title: 'Rental Status Update',
          message: 'Your rental for ${rental.brand} is now: $status.',
        );
      }
      await createNotification(
        uid: rental.hostId,
        title: 'Rental Status Update',
        message: 'Your rental for ${rental.brand} is now: $status.',
      );
    }
  }

  /// Update rental tracking location
  Future<void> updateRentalTracking(String rentalId, double lat, double lng) async {
    await setDocument('rentals/$rentalId', {
      'trackingLat': lat,
      'trackingLng': lng,
    });
  }

  /// Complete rental (releases escrow to host, minus 3% platform commission, saves to history, resets listing to Available)
  Future<void> completeRental(String rentalId) async {
    final rentalDoc = await getDocument('rentals/$rentalId');
    if (rentalDoc == null) throw Exception('Rental listing not found.');
    final rental = VehicleRental.fromMap(rentalDoc, rentalId);

    final host = await getUser(rental.hostId);
    if (host == null) throw Exception('Host profile not found.');

    // Verify payment is held in escrow before releasing
    final escrowDoc = await getDocument('rental_escrows/$rentalId');
    if (escrowDoc == null) {
      throw Exception('Escrow transaction not found. Payout aborted to ensure secure transaction.');
    }
    if (escrowDoc['status'] != 'Held') {
      throw Exception('Escrow is not in Held status. Current status: ${escrowDoc['status']}. Payout aborted.');
    }

    final cost = rental.totalCost ?? 0.0;
    final commission = cost * 0.03;
    final hostPayout = cost - commission;

    // Release payout to host
    final newHostBalance = host.tyxBalance + hostPayout;
    await updateTyxBalance(rental.hostId, newHostBalance);

    // Save transaction for host
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    final txData = {
      'uid': rental.hostId,
      'type': 'payment',
      'amount': hostPayout,
      'baseAmount': cost,
      'commissionFee': commission,
      'commissionLabel': 'Platform Commission (3%)',
      'title': 'Rental Earnings Payout',
      'desc':
          'Payout for rental ${rental.brand} ${rental.model} (3% platform commission of ${commission.toStringAsFixed(2)} TYXBIT deducted)',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('transactions/$txId', txData);

    // Update escrow status
    await setDocument('rental_escrows/$rentalId', {
      'status': 'Released',
      'releasedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Save transaction and rental details to history
    final historyId = 'rh_${DateTime.now().microsecondsSinceEpoch}';
    final historyDoc = {
      ...rentalDoc,
      'status': 'Completed',
      'completedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('rental_history/$historyId', historyDoc);

    // Reset the rental listing document status back to Available and clear rentee fields
    await setDocument('rentals/$rentalId', {
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

    // Notifications
    await createNotification(
      uid: rental.hostId,
      title: 'Rental Completed & Paid',
      message:
          'Rental for ${rental.brand} completed. Payout of ${hostPayout.toStringAsFixed(2)} TYXBIT credited to your wallet.',
    );
    if (rental.renteeId != null && rental.renteeId!.isNotEmpty) {
      await createNotification(
        uid: rental.renteeId!,
        title: 'Rental Completed',
        message: 'Your rental for ${rental.brand} has been successfully completed. Thank you!',
      );
    }
  }

  /// Submit a vehicle rental booking request (debits rentee and puts in request-specific escrow)
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
    final rentalDoc = await getDocument('rentals/$rentalId');
    if (rentalDoc == null) throw Exception('Rental listing not found.');
    final rental = VehicleRental.fromMap(rentalDoc, rentalId);

    if (rental.status != 'Available') {
      throw Exception('Vehicle is no longer available.');
    }

    final rentee = await getUser(renteeId);
    if (rentee == null) throw Exception('Renter profile not found.');

    final discount = discountAmount ?? 0.0;
    final discountedCost = (totalCost - discount).clamp(0.0, 999999.0);
    final bookingFee = discountedCost * 0.03;
    final totalRequired = discountedCost + bookingFee;

    if (rentee.tyxBalance < totalRequired) {
      throw Exception(
        'Insufficient balance. Required: ${totalRequired.toStringAsFixed(2)} TYXBIT (including 3% booking fee), but available: ${rentee.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Deduct from renter
    final newRenterBalance = rentee.tyxBalance - totalRequired;
    await updateTyxBalance(renteeId, newRenterBalance);

    // Save transaction record for renter
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    final txData = {
      'uid': renteeId,
      'type': 'payment',
      'amount': totalRequired,
      'title': 'Vehicle Booking Request',
      'desc': 'Requested ${rental.brand} ${rental.model} for $multiplier $durationType(s)${promoCode != null ? ' (Promo $promoCode applied: -₱${discount.toStringAsFixed(2)})' : ''}',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('transactions/$txId', txData);

    // Save request document
    final requestId = 'req_${DateTime.now().microsecondsSinceEpoch}';
    final requestDoc = {
      'id': requestId,
      'rentalId': rentalId,
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': renteePhotoUrl ?? '',
      'durationType': durationType,
      'multiplier': multiplier,
      'totalCost': discountedCost,
      'originalCost': totalCost,
      'bookingFee': bookingFee,
      'signatureName': '', // Signature not signed yet
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
    };
    await setDocument('rental_requests/$requestId', requestDoc);

    // Put funds in escrow for this specific request
    final escrowDoc = {
      'requestId': requestId,
      'rentalId': rentalId,
      'renteeId': renteeId,
      'hostId': rental.hostId,
      'amount': discountedCost,
      'status': 'Held',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('rental_escrows/$requestId', escrowDoc);

    // Increment promo usage
    if (promoCode != null) {
      await incrementPromoUsage(promoCode, renteeId);
    }

    // Notify host
    await createNotification(
      uid: rental.hostId,
      title: 'Booking Request Received',
      message: '$renteeName wants to book your ${rental.brand} ${rental.model}.',
    );
  }

  /// Approve a booking request and automatically reject all other requests for the same vehicle
  Future<void> approveBookingRequest(String requestId, String rentalId, bool allowChat) async {
    final reqDoc = await getDocument('rental_requests/$requestId');
    if (reqDoc == null) throw Exception('Booking request not found.');
    if (reqDoc['status'] != 'Pending') throw Exception('Request is already processed.');

    final rentalDoc = await getDocument('rentals/$rentalId');
    if (rentalDoc == null) throw Exception('Rental listing not found.');
    final rental = VehicleRental.fromMap(rentalDoc, rentalId);
    if (rental.status != 'Available') {
      throw Exception('Vehicle is no longer available (already booked).');
    }

    final renteeId = reqDoc['renteeId'] as String;
    final renteeName = reqDoc['renteeName'] as String;
    final durationType = reqDoc['durationType'] as String;
    final multiplier = (reqDoc['multiplier'] as num).toInt();
    final totalCost = (reqDoc['totalCost'] as num).toDouble();
    final hireWithDriver = reqDoc['hireWithDriver'] as bool? ?? false;
    final rentalType = reqDoc['rentalType'] as String? ?? 'pickup';
    final deliveryAddress = reqDoc['deliveryAddress'] as String? ?? '';
    final startDate = (reqDoc['startDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final endDate =
        (reqDoc['endDate'] as num?)?.toInt() ?? DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;

    // 1. Approve this request
    await setDocument('rental_requests/$requestId', {'status': 'Approved'});

    // 2. Move request's escrow to standard rental escrow (include bookingFee for full-refund tracking)
    final reqEscrowDoc = await getDocument('rental_escrows/$requestId');
    final reqBookingFee = (reqDoc['bookingFee'] as num? ?? totalCost * 0.03).toDouble();
    if (reqEscrowDoc != null) {
      await setDocument('rental_escrows/$rentalId', {
        'rentalId': rentalId,
        'renteeId': renteeId,
        'hostId': rental.hostId,
        'amount': totalCost,
        'bookingFee': reqBookingFee,
        'totalPaid': totalCost + reqBookingFee,
        'status': 'Held',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      await deleteDocument('rental_escrows/$requestId');
    }

    // 3. Update the rental listing document with renter details - Status set to "Awaiting Signature"
    await setDocument('rentals/$rentalId', {
      'status': 'Awaiting Signature',
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': reqDoc['renteePhotoUrl'] ?? '',
      'rentalDurationType': durationType,
      'rentalMultiplier': multiplier,
      'startDate': startDate,
      'endDate': endDate,
      'totalCost': totalCost,
      'bookingFee': reqBookingFee,
      'renteeSignatureName': '',
      'renteeLicenseNumber': reqDoc['licenseNumber'] ?? '',
      'signedAt': 0,
      'trackingLat': rental.pickupLat,
      'trackingLng': rental.pickupLng,
      'hireWithDriver': hireWithDriver,
      'rentalType': rentalType,
      'deliveryAddress': deliveryAddress,
      'currentRequestId': requestId,
      'allowChat': allowChat,
    });

    // 4. Reject all other pending requests for the same vehicle
    final allRequests = await getPendingRequestsForVehicle(rentalId);
    for (final otherReq in allRequests) {
      final otherReqId = otherReq['id'] as String;
      if (otherReqId == requestId) continue;
      try {
        await rejectBookingRequest(otherReqId);
      } catch (e) {
        print('Error rejecting other request $otherReqId: $e');
      }
    }

    // Notifications
    await createNotification(
      uid: renteeId,
      title: 'Booking Request Approved',
      message:
          'Your request to book ${rental.brand} ${rental.model} has been approved! Please sign the contract to activate the rental.',
    );
    await createNotification(
      uid: rental.hostId,
      title: 'Booking Approved',
      message:
          'You approved $renteeName\'s booking request for ${rental.brand} ${rental.model}. Awaiting renter\'s signature.',
    );
  }

  /// Sign vehicle contract to activate booking
  Future<void> signVehicleContract(String rentalId, String signatureDataUrl, {String? signatureHash}) async {
    final rentalDoc = await getDocument('rentals/$rentalId');
    if (rentalDoc == null) throw Exception('Rental listing not found.');

    final now = DateTime.now();
    await setDocument('rentals/$rentalId', {
      'status': 'Booked',
      'renteeSignatureName': signatureDataUrl,
      'signedAt': now.millisecondsSinceEpoch,
      'signatureHash': ?signatureHash,
    });

    final hostId = rentalDoc['hostId'] as String;
    final renteeName = rentalDoc['renteeName'] as String? ?? 'Renter';
    final brand = rentalDoc['brand'] ?? '';
    final model = rentalDoc['model'] ?? '';

    await createNotification(
      uid: hostId,
      title: 'Contract Signed',
      message:
          '$renteeName has signed the contract for your vehicle $brand $model. Booking is now active and ready for handover.',
    );
  }

  /// Reject a booking request and refund the rentee's wallet
  Future<void> rejectBookingRequest(String requestId) async {
    final reqDoc = await getDocument('rental_requests/$requestId');
    if (reqDoc == null) return;
    if (reqDoc['status'] != 'Pending') return;

    final renteeId = reqDoc['renteeId'] as String;
    final totalCost = (reqDoc['totalCost'] as num).toDouble();
    final bookingFee = (reqDoc['bookingFee'] as num).toDouble();
    final refundAmount = totalCost + bookingFee;

    // Set request status to Rejected
    await setDocument('rental_requests/$requestId', {'status': 'Rejected'});

    // Revert promo usage
    final promoCode = reqDoc['promoCode'] as String?;
    if (promoCode != null) {
      await decrementPromoUsage(promoCode, renteeId);
    }

    // Refund rentee
    final rentee = await getUser(renteeId);
    if (rentee != null) {
      await updateTyxBalance(renteeId, rentee.tyxBalance + refundAmount);

      // Save transaction record for refund
      final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
      final txData = {
        'uid': renteeId,
        'type': 'refund',
        'amount': refundAmount,
        'title': 'Booking Request Refund',
        'desc': 'Refund for rejected request of ${reqDoc['brand']} ${reqDoc['model']}',
        'method': 'Tranyx Wallet',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      await setDocument('transactions/$txId', txData);
    }

    // Release/delete the held escrow
    await deleteDocument('rental_escrows/$requestId');

    // Notify renter
    await createNotification(
      uid: renteeId,
      title: 'Booking Request Rejected',
      message: 'Your request to book ${reqDoc['brand']} ${reqDoc['model']} was rejected. Funds have been refunded.',
    );
  }

  /// Cancel a pending booking request by the rentee and refund their wallet
  Future<void> cancelBookingRequest(String requestId) async {
    final reqDoc = await getDocument('rental_requests/$requestId');
    if (reqDoc == null) return;
    if (reqDoc['status'] != 'Pending') return;

    final renteeId = reqDoc['renteeId'] as String;
    final hostId = reqDoc['hostId'] as String;
    final totalCost = (reqDoc['totalCost'] as num).toDouble();
    final bookingFee = (reqDoc['bookingFee'] as num).toDouble();
    final refundAmount = totalCost + bookingFee;

    // Set request status to Cancelled
    await setDocument('rental_requests/$requestId', {'status': 'Cancelled'});

    // Revert promo usage
    final promoCode = reqDoc['promoCode'] as String?;
    if (promoCode != null) {
      await decrementPromoUsage(promoCode, renteeId);
    }

    // Refund rentee
    final rentee = await getUser(renteeId);
    if (rentee != null) {
      await updateTyxBalance(renteeId, rentee.tyxBalance + refundAmount);

      // Save transaction record for refund
      final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
      final txData = {
        'uid': renteeId,
        'type': 'refund',
        'amount': refundAmount,
        'title': 'Booking Request Cancelled',
        'desc': 'Refund for cancelled request of ${reqDoc['brand']} ${reqDoc['model']}',
        'method': 'Tranyx Wallet',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      await setDocument('transactions/$txId', txData);
    }

    // Release/delete the held escrow
    await deleteDocument('rental_escrows/$requestId');

    // Notify host
    await createNotification(
      uid: hostId,
      title: 'Booking Request Cancelled',
      message:
          '${reqDoc['renteeName'] ?? "Renter"} has cancelled their booking request for your ${reqDoc['brand']} ${reqDoc['model']}.',
    );
  }

  /// Fetch all pending requests for a specific vehicle, filtered in-memory
  Future<List<Map<String, dynamic>>> getPendingRequestsForVehicle(String rentalId) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'rental_requests'},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'rentalId'},
            'op': 'EQUAL',
            'value': {'stringValue': rentalId},
          },
        },
      },
    });

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) return [];

    final List<dynamic> results = jsonDecode(req.body);
    final list = <Map<String, dynamic>>[];
    for (final r in results) {
      if (r is Map && r.containsKey('document')) {
        final doc = r['document'] as Map<String, dynamic>;
        final name = doc['name'] as String;
        final parts = name.split('/');
        final docId = parts.last;
        final data = _fromFirestoreDoc(doc);
        data['id'] = docId;
        if (data['status'] == 'Pending') {
          list.add(data);
        }
      }
    }
    return list;
  }

  /// Fetch all pending requests for a specific host, filtered in-memory
  Future<List<Map<String, dynamic>>> getPendingRequestsForHost(String hostId) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'rental_requests'},
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'hostId'},
                  'op': 'EQUAL',
                  'value': {'stringValue': hostId},
                },
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'status'},
                  'op': 'EQUAL',
                  'value': {'stringValue': 'Pending'},
                },
              },
            ],
          },
        },
      },
    });

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) return [];

    final List<dynamic> results = jsonDecode(req.body);
    final list = <Map<String, dynamic>>[];
    for (final r in results) {
      if (r is Map && r.containsKey('document')) {
        final doc = r['document'] as Map<String, dynamic>;
        final name = doc['name'] as String;
        final docId = name.split('/').last;
        final data = _fromFirestoreDoc(doc);
        data['id'] = docId;
        list.add(data);
      }
    }
    return list;
  }

  /// Fetch all pending requests submitted by a renter, filtered in-memory
  Future<List<Map<String, dynamic>>> getRenterPendingRequests(String renteeId) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'rental_requests'},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'renteeId'},
            'op': 'EQUAL',
            'value': {'stringValue': renteeId},
          },
        },
      },
    });

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) return [];

    final List<dynamic> results = jsonDecode(req.body);
    final list = <Map<String, dynamic>>[];
    for (final r in results) {
      if (r is Map && r.containsKey('document')) {
        final doc = r['document'] as Map<String, dynamic>;
        final name = doc['name'] as String;
        final parts = name.split('/');
        final docId = parts.last;
        final data = _fromFirestoreDoc(doc);
        data['id'] = docId;
        if (data['status'] == 'Pending') {
          list.add(data);
        }
      }
    }
    return list;
  }

  /// Fetch all completed rental history (both as host and rentee) — vehicles + properties
  Future<List<Map<String, dynamic>>> getMyRentalHistory(String uid) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final list = <Map<String, dynamic>>[];
    final ids = <String>{};

    /// Runs a Firestore structuredQuery and appends results tagged with [rentalKind]
    Future<void> runQuery(String collectionId, String field, String rentalKind) async {
      final body = jsonEncode({
        'structuredQuery': {
          'from': [
            {'collectionId': collectionId},
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': field},
              'op': 'EQUAL',
              'value': {'stringValue': uid},
            },
          },
        },
      });
      try {
        final req = await http.post(Uri.parse(url), headers: headers, body: body);
        if (req.statusCode >= 400) return;
        final List<dynamic> results = jsonDecode(req.body);
        for (final r in results) {
          if (r is Map && r.containsKey('document')) {
            final doc = r['document'] as Map<String, dynamic>;
            final name = doc['name'] as String;
            final parts = name.split('/');
            final docId = parts.last;
            final uniqueKey = '${rentalKind}_$docId';
            if (ids.contains(uniqueKey)) continue;
            ids.add(uniqueKey);
            final data = _fromFirestoreDoc(doc);
            data['id'] = docId;
            data['rentalKind'] = rentalKind; // 'vehicle' or 'property'
            list.add(data);
          }
        }
      } catch (e) {
        print('Error running history query ($collectionId/$field): $e');
      }
    }

    // Vehicle rentals — as host and as rentee
    await runQuery('rental_history', 'hostId', 'vehicle');
    await runQuery('rental_history', 'renteeId', 'vehicle');

    // Property rentals — as host and as rentee
    await runQuery('property_history', 'hostId', 'property');
    await runQuery('property_history', 'renteeId', 'property');

    // Sort by completedAt descending
    list.sort((a, b) {
      final tA = a['completedAt'] ?? a['createdAt'] ?? 0;
      final tB = b['completedAt'] ?? b['createdAt'] ?? 0;
      return tB.compareTo(tA);
    });

    return list;
  }

  /// Submit a role-specific rating for a counterparty after a completed rental.
  /// [role] must be 'renter' or 'host'.
  /// Uses a weighted moving average: newRating = (existingRating * count + stars) / (count + 1).
  Future<void> submitRentalRating({
    required String targetUid,
    required String callerUid, // UID of the person submitting the rating
    required String role, // 'renter' or 'host'
    required double stars, // 1.0 – 5.0
    required String rentalId,
  }) async {
    assert(role == 'renter' || role == 'host', 'role must be renter or host');
    assert(stars >= 1.0 && stars <= 5.0, 'stars must be 1–5');

    final field = role == 'renter' ? 'renterRating' : 'hostRating';
    final countField = role == 'renter' ? 'renterRatingCount' : 'hostRatingCount';

    // Fetch current values
    final userDoc = await getDocument('users/$targetUid');
    if (userDoc == null) throw Exception('User not found.');

    final existingRating = (userDoc[field] as num?)?.toDouble() ?? 0.0;
    final existingCount = (userDoc[countField] as num?)?.toInt() ?? 0;
    final newCount = existingCount + 1;
    final newRating = ((existingRating * existingCount) + stars) / newCount;

    await setDocument('users/$targetUid', {
      field: double.parse(newRating.toStringAsFixed(2)),
      countField: newCount,
    });

    // Mark this rental as rated so the button is hidden after submission
    final ratedField = '${role}RatedBy_$callerUid';
    final collection = rentalId.startsWith('ph_') ? 'property_history' : 'rental_history';
    await setDocument('$collection/$rentalId', {ratedField: true});
  }

  /// Cancel rental — full refund (totalCost + bookingFee) back to rentee
  Future<void> cancelRental(String rentalId) async {
    final rentalDoc = await getDocument('rentals/$rentalId');
    if (rentalDoc == null) throw Exception('Rental listing not found.');
    final rental = VehicleRental.fromMap(rentalDoc, rentalId);

    if (rental.renteeId == null || rental.renteeId!.isEmpty) {
      // Never booked — just reset status
      await setDocument('rentals/$rentalId', {'status': 'Available'});
      return;
    }

    final rentee = await getUser(rental.renteeId!);
    if (rentee == null) throw Exception('Rentee profile not found.');

    final baseCost = rental.totalCost ?? 0.0;

    // Retrieve booking fee from rental doc; fallback to escrow doc; fallback to 3% of base
    double bookingFee = (rentalDoc['bookingFee'] as num?)?.toDouble() ?? 0.0;
    if (bookingFee == 0.0) {
      final escrowDoc = await getDocument('rental_escrows/$rentalId');
      bookingFee = (escrowDoc?['bookingFee'] as num?)?.toDouble() ?? baseCost * 0.03;
    }
    final fullRefundAmount = baseCost + bookingFee;
    const cancellationFee = 2.0; // flat platform cancellation processing fee
    final refundToRentee = (fullRefundAmount - cancellationFee).clamp(0.0, double.infinity);

    // Refund (total - 2 TYXBIT fee) to rentee
    await updateTyxBalance(rental.renteeId!, rentee.tyxBalance + refundToRentee);

    // Save refund transaction
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    final txData = {
      'uid': rental.renteeId!,
      'type': 'refund',
      'amount': refundToRentee,
      'title': 'Rental Cancellation — Refund',
      'desc':
          'Refund for cancelled rental: ${rental.brand} ${rental.model} (total paid: ${fullRefundAmount.toStringAsFixed(2)} − 2.00 TYXBIT cancellation fee)',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('transactions/$txId', txData);

    // Mark escrow as Refunded
    await setDocument('rental_escrows/$rentalId', {
      'status': 'Refunded',
      'cancelledAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Mark current request as Cancelled
    final currentRequestId = rentalDoc['currentRequestId'] as String?;
    if (currentRequestId != null) {
      final reqDoc = await getDocument('rental_requests/$currentRequestId');
      if (reqDoc != null) {
        final promoCode = reqDoc['promoCode'] as String?;
        if (promoCode != null) {
          await decrementPromoUsage(promoCode, rental.renteeId!);
        }
      }
      await setDocument('rental_requests/$currentRequestId', {'status': 'Cancelled'});
    }

    // Reset rental listing to Available
    await setDocument('rentals/$rentalId', {
      'status': 'Available',
      'renteeId': null,
      'renteeName': null,
      'renteePhotoUrl': null,
      'rentalDurationType': null,
      'rentalMultiplier': null,
      'startDate': null,
      'endDate': null,
      'totalCost': null,
      'bookingFee': null,
      'renteeSignatureName': null,
      'renteeLicenseNumber': null,
      'signedAt': null,
      'trackingLat': null,
      'trackingLng': null,
      'rentalType': null,
      'deliveryAddress': null,
      'currentRequestId': null,
    });

    // Notifications
    await createNotification(
      uid: rental.hostId,
      title: 'Rental Booking Cancelled',
      message: 'Rental booking for ${rental.brand} ${rental.model} was cancelled. The listing is now available again.',
    );
    await createNotification(
      uid: rental.renteeId!,
      title: 'Rental Cancelled — Refund Issued',
      message:
          'Your rental was cancelled. ${refundToRentee.toStringAsFixed(2)} TYXBIT refunded (total paid: ${fullRefundAmount.toStringAsFixed(2)} − 2.00 TYXBIT cancellation fee).',
    );
  }

  /// Fetch all approved requests for a specific vehicle
  Future<List<Map<String, dynamic>>> getApprovedRequestsForVehicle(String rentalId) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'rental_requests'},
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'rentalId'},
                  'op': 'EQUAL',
                  'value': {'stringValue': rentalId},
                },
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'status'},
                  'op': 'EQUAL',
                  'value': {'stringValue': 'Approved'},
                },
              },
            ],
          },
        },
      },
    });

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) return [];

    final List<dynamic> results = jsonDecode(req.body);
    final list = <Map<String, dynamic>>[];
    for (final r in results) {
      if (r is Map && r.containsKey('document')) {
        final doc = r['document'] as Map<String, dynamic>;
        final name = doc['name'] as String;
        final docId = name.split('/').last;
        final data = _fromFirestoreDoc(doc);
        data['id'] = docId;
        list.add(data);
      }
    }
    return list;
  }

  /// Fetch all pending extensions for a specific vehicle
  Future<List<Map<String, dynamic>>> getPendingExtensionsForVehicle(String rentalId) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'rental_extensions'},
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'rentalId'},
                  'op': 'EQUAL',
                  'value': {'stringValue': rentalId},
                },
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'status'},
                  'op': 'EQUAL',
                  'value': {'stringValue': 'Pending'},
                },
              },
            ],
          },
        },
      },
    });

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) return [];

    final List<dynamic> results = jsonDecode(req.body);
    final list = <Map<String, dynamic>>[];
    for (final r in results) {
      if (r is Map && r.containsKey('document')) {
        final doc = r['document'] as Map<String, dynamic>;
        final name = doc['name'] as String;
        final docId = name.split('/').last;
        final data = _fromFirestoreDoc(doc);
        data['id'] = docId;
        list.add(data);
      }
    }
    return list;
  }

  /// Create a pending extension request and debit the rentee's balance into extension escrow
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
        'Insufficient balance. Extension requires ${fee.toStringAsFixed(2)} TYXBIT, but available: ${rentee.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Debit rentee
    await updateTyxBalance(renteeId, rentee.tyxBalance - fee);

    // Save transaction
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    final txData = {
      'uid': renteeId,
      'type': 'payment',
      'amount': fee,
      'title': 'Rental Extension Request',
      'desc': 'Requested extension of $extendHours hour(s) for vehicle rental.',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('transactions/$txId', txData);

    // Create pending extension request doc
    final extensionId = 'ext_${DateTime.now().microsecondsSinceEpoch}';
    final extensionDoc = {
      'id': extensionId,
      'rentalId': rentalId,
      'renteeId': renteeId,
      'extendHours': extendHours,
      'fee': fee,
      'status': 'Pending',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('rental_extensions/$extensionId', extensionDoc);

    // Put funds in extension escrow
    final escrowDoc = {
      'extensionId': extensionId,
      'rentalId': rentalId,
      'renteeId': renteeId,
      'amount': fee,
      'status': 'Held',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('rental_extension_escrows/$extensionId', escrowDoc);
  }

  /// Auto-approve extension (no overlap): debit rentee and update rental immediately
  Future<void> autoApproveExtension({
    required String rentalId,
    required String renteeId,
    required int extendHours,
    required double fee,
  }) async {
    final rentalDoc = await getDocument('rentals/$rentalId');
    if (rentalDoc == null) throw Exception('Rental listing not found.');

    final rentee = await getUser(renteeId);
    if (rentee == null) throw Exception('Renter profile not found.');
    if (rentee.tyxBalance < fee) {
      throw Exception(
        'Insufficient balance. Extension requires ${fee.toStringAsFixed(2)} TYXBIT, but available: ${rentee.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Debit rentee
    await updateTyxBalance(renteeId, rentee.tyxBalance - fee);

    // Save transaction
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    final txData = {
      'uid': renteeId,
      'type': 'payment',
      'amount': fee,
      'title': 'Rental Extension (Auto-Approved)',
      'desc': 'Extended rental by $extendHours hour(s) automatically.',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('transactions/$txId', txData);

    // Add fee directly to rental escrow
    final escrowDoc = await getDocument('rental_escrows/$rentalId');
    if (escrowDoc != null) {
      final currentAmount = (escrowDoc['amount'] as num? ?? 0.0).toDouble();
      await setDocument('rental_escrows/$rentalId', {
        ...escrowDoc,
        'amount': currentAmount + fee,
      });
    }

    // Update rental endDate and totalCost
    final currentEndMs = rentalDoc['endDate'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final currentCost = (rentalDoc['totalCost'] as num? ?? 0.0).toDouble();

    final newEndDate = DateTime.fromMillisecondsSinceEpoch(currentEndMs).add(Duration(hours: extendHours));

    await setDocument('rentals/$rentalId', {
      ...rentalDoc,
      'endDate': newEndDate.millisecondsSinceEpoch,
      'totalCost': currentCost + fee,
    });
  }

  /// Approve pending extension request (move escrow and update rental)
  Future<void> approveExtension(String extensionId) async {
    final extDoc = await getDocument('rental_extensions/$extensionId');
    if (extDoc == null) throw Exception('Extension request not found.');
    if (extDoc['status'] != 'Pending') throw Exception('Extension already processed.');

    final rentalId = extDoc['rentalId'] as String;
    final extendHours = (extDoc['extendHours'] as num).toInt();
    final fee = (extDoc['fee'] as num).toDouble();

    final rentalDoc = await getDocument('rentals/$rentalId');
    if (rentalDoc == null) throw Exception('Rental listing not found.');

    // 1. Mark request approved
    await setDocument('rental_extensions/$extensionId', {'status': 'Approved'});

    // 2. Merge extension escrow into main rental escrow
    final extEscrow = await getDocument('rental_extension_escrows/$extensionId');
    if (extEscrow != null) {
      final escrowDoc = await getDocument('rental_escrows/$rentalId');
      if (escrowDoc != null) {
        final currentAmount = (escrowDoc['amount'] as num? ?? 0.0).toDouble();
        await setDocument('rental_escrows/$rentalId', {
          ...escrowDoc,
          'amount': currentAmount + fee,
        });
      }
      await deleteDocument('rental_extension_escrows/$extensionId');
    }

    // 3. Update rental endDate and totalCost
    final currentEndMs = rentalDoc['endDate'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final currentCost = (rentalDoc['totalCost'] as num? ?? 0.0).toDouble();

    final newEndDate = DateTime.fromMillisecondsSinceEpoch(currentEndMs).add(Duration(hours: extendHours));

    await setDocument('rentals/$rentalId', {
      ...rentalDoc,
      'endDate': newEndDate.millisecondsSinceEpoch,
      'totalCost': currentCost + fee,
    });
  }

  /// Reject pending extension request (refund rentee and delete request escrow)
  Future<void> rejectExtension(String extensionId) async {
    final extDoc = await getDocument('rental_extensions/$extensionId');
    if (extDoc == null) return;
    if (extDoc['status'] != 'Pending') return;

    final renteeId = extDoc['renteeId'] as String;
    final fee = (extDoc['fee'] as num).toDouble();

    // 1. Mark request rejected
    await setDocument('rental_extensions/$extensionId', {'status': 'Rejected'});

    // 2. Refund rentee
    final rentee = await getUser(renteeId);
    if (rentee != null) {
      await updateTyxBalance(renteeId, rentee.tyxBalance + fee);

      // Save refund transaction
      final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
      final txData = {
        'uid': renteeId,
        'type': 'refund',
        'amount': fee,
        'title': 'Rental Extension Refund',
        'desc': 'Refund for rejected rental extension request.',
        'method': 'Tranyx Wallet',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      await setDocument('transactions/$txId', txData);
    }

    // 3. Delete extension escrow
    await deleteDocument('rental_extension_escrows/$extensionId');
  }

  // ── Property Rentals ──────────────────────────────────────────

  /// Create a new property rental posting, deducting 1.5% listing fee
  Future<String> createPropertyRental(PropertyRental property) async {
    final host = await getUser(property.hostId);
    if (host == null) {
      throw Exception('Host profile not found.');
    }
    final listingFee = 0.015 * property.priceMonthly;
    if (host.tyxBalance < listingFee) {
      throw Exception(
        'Insufficient balance. Listing fee requires ${listingFee.toStringAsFixed(2)} TYXBIT, but your balance is ${host.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Deduct fee
    final newBalance = host.tyxBalance - listingFee;
    await updateTyxBalance(property.hostId, newBalance);

    // Save transaction record
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    final txData = {
      'uid': property.hostId,
      'type': 'listing_fee',
      'amount': listingFee,
      'title': 'Property Listing Fee',
      'desc': '1.5% posting fee for property: ${property.title}',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('transactions/$txId', txData);

    // Post property document
    final url = '$_firestoreBase/properties';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final req = await _client.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(_toFirestoreFields(property.toMap())),
    );

    if (req.statusCode >= 400) {
      final data = jsonDecode(req.body) as Map<String, dynamic>;
      final err = data['error'] as Map? ?? {};
      throw FirebaseException(err['message'] as String? ?? 'Create property rental failed', req.statusCode);
    }

    final result = jsonDecode(req.body) as Map<String, dynamic>;
    final docId = _docId(result);
    await setDocument('properties/$docId', {'id': docId});
    return docId;
  }

  /// Delete property rental posting and reject pending requests
  Future<void> deletePropertyRental(String propertyId) async {
    final propDoc = await getDocument('properties/$propertyId');
    if (propDoc == null) throw Exception('Property listing not found.');

    final property = PropertyRental.fromMap(propDoc, propertyId);
    if (property.status != 'Available') {
      throw Exception('Cannot delete a property listing that is currently booked or active.');
    }

    // Fetch and reject all pending requests for this property
    final pendingRequests = await getPropertyPendingRequestsForProperty(propertyId);
    for (final req in pendingRequests) {
      final requestId = req['id'] as String;
      try {
        await rejectPropertyBookingRequest(requestId);
      } catch (e) {
        print('Error rejecting request $requestId during property deletion: $e');
      }
    }

    await deleteDocument('properties/$propertyId');
  }

  /// Fetch all properties
  Future<List<PropertyRental>> getPropertyRentals() async {
    final url = '$_firestoreBase/properties';
    final headers = <String, String>{};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final req = await _client.get(Uri.parse(url), headers: headers);
    if (req.statusCode >= 400) return [];

    final data = jsonDecode(req.body) as Map<String, dynamic>;
    final docs = data['documents'] as List? ?? [];
    return docs.map((d) {
      final doc = d as Map<String, dynamic>;
      final id = _docId(doc);
      return PropertyRental.fromMap(_fromFirestoreDoc(doc), id);
    }).toList();
  }

  /// Fetch specific property
  Future<PropertyRental?> getPropertyRental(String propertyId) async {
    final doc = await getDocument('properties/$propertyId');
    if (doc == null) return null;
    return PropertyRental.fromMap(doc, propertyId);
  }

  /// Submit a property rental booking request (debits rentee and puts in request-specific escrow)
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
    final propDoc = await getDocument('properties/$propertyId');
    if (propDoc == null) throw Exception('Property listing not found.');
    final property = PropertyRental.fromMap(propDoc, propertyId);

    if (property.status != 'Available') {
      throw Exception('Property is no longer available.');
    }

    final rentee = await getUser(renteeId);
    if (rentee == null) throw Exception('Renter profile not found.');

    final discount = discountAmount ?? 0.0;
    final discountedCost = (totalCost - discount).clamp(0.0, 999999.0);
    final bookingFee = discountedCost * 0.03;
    final totalRequired = discountedCost + bookingFee;

    if (rentee.tyxBalance < totalRequired) {
      throw Exception(
        'Insufficient balance. Required: ${totalRequired.toStringAsFixed(2)} TYXBIT (including 3% booking fee), but available: ${rentee.tyxBalance.toStringAsFixed(2)} TYXBIT.',
      );
    }

    // Deduct from renter
    final newRenterBalance = rentee.tyxBalance - totalRequired;
    await updateTyxBalance(renteeId, newRenterBalance);

    // Save transaction record for renter
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    final txData = {
      'uid': renteeId,
      'type': 'payment',
      'amount': totalRequired,
      'title': 'Property Booking Request',
      'desc': 'Requested property "${property.title}" for $multiplier $durationType(s)${promoCode != null ? ' (Promo $promoCode applied: -₱${discount.toStringAsFixed(2)})' : ''}',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('transactions/$txId', txData);

    // Save request document
    final requestId = 'req_${DateTime.now().microsecondsSinceEpoch}';
    final requestDoc = {
      'id': requestId,
      'propertyId': propertyId,
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': renteePhotoUrl ?? '',
      'durationType': durationType,
      'multiplier': multiplier,
      'totalCost': discountedCost,
      'originalCost': totalCost,
      'bookingFee': bookingFee,
      'signatureName': '', // unsigned
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
      'promoCode': ?promoCode,
      if (promoCode != null) 'discountAmount': discount,
    };
    await setDocument('property_requests/$requestId', requestDoc);

    // Put funds in escrow for this specific request
    final escrowDoc = {
      'requestId': requestId,
      'propertyId': propertyId,
      'renteeId': renteeId,
      'hostId': property.hostId,
      'amount': discountedCost,
      'status': 'Held',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('property_escrows/$requestId', escrowDoc);

    // Increment promo usage
    if (promoCode != null) {
      await incrementPromoUsage(promoCode, renteeId);
    }

    // Notify host
    await createNotification(
      uid: property.hostId,
      title: 'Booking Request Received',
      message: '$renteeName wants to rent your property: "${property.title}".',
    );
  }

  /// Approve a booking request, set status to Awaiting Signature, reject other requests
  Future<void> approvePropertyBookingRequest(String requestId, String propertyId, bool allowChat) async {
    final reqDoc = await getDocument('property_requests/$requestId');
    if (reqDoc == null) throw Exception('Booking request not found.');
    if (reqDoc['status'] != 'Pending') throw Exception('Request is already processed.');

    final propDoc = await getDocument('properties/$propertyId');
    if (propDoc == null) throw Exception('Property listing not found.');
    final property = PropertyRental.fromMap(propDoc, propertyId);
    if (property.status != 'Available') {
      throw Exception('Property is no longer available (already rented).');
    }

    final renteeId = reqDoc['renteeId'] as String;
    final renteeName = reqDoc['renteeName'] as String;
    final durationType = reqDoc['durationType'] as String;
    final multiplier = (reqDoc['multiplier'] as num).toInt();
    final totalCost = (reqDoc['totalCost'] as num).toDouble();
    final startDate = (reqDoc['startDate'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final endDate =
        (reqDoc['endDate'] as num?)?.toInt() ?? DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;

    // 1. Approve request
    await setDocument('property_requests/$requestId', {'status': 'Approved'});

    // 2. Move escrow
    final reqEscrowDoc = await getDocument('property_escrows/$requestId');
    final reqBookingFee = (reqDoc['bookingFee'] as num? ?? totalCost * 0.03).toDouble();
    if (reqEscrowDoc != null) {
      await setDocument('property_escrows/$propertyId', {
        'propertyId': propertyId,
        'renteeId': renteeId,
        'hostId': property.hostId,
        'amount': totalCost,
        'bookingFee': reqBookingFee,
        'totalPaid': totalCost + reqBookingFee,
        'status': 'Held',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      await deleteDocument('property_escrows/$requestId');
    }

    // 3. Update property listing
    await setDocument('properties/$propertyId', {
      'status': 'Awaiting Signature',
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': reqDoc['renteePhotoUrl'] ?? '',
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
      'licenseNumber': reqDoc['licenseNumber'] ?? '',
    });

    // 4. Reject other requests
    final allRequests = await getPropertyPendingRequestsForProperty(propertyId);
    for (final otherReq in allRequests) {
      final otherReqId = otherReq['id'] as String;
      if (otherReqId == requestId) continue;
      try {
        await rejectPropertyBookingRequest(otherReqId);
      } catch (e) {
        print('Error rejecting other request $otherReqId: $e');
      }
    }

    // Notifications
    await createNotification(
      uid: renteeId,
      title: 'Property Request Approved',
      message:
          'Your request to rent "${property.title}" has been approved! Please sign the lease agreement to finalize.',
    );
    await createNotification(
      uid: property.hostId,
      title: 'Booking Approved',
      message: 'You approved $renteeName\'s request for "${property.title}". Awaiting tenant signature.',
    );
  }

  /// Reject a property booking request and refund rentee
  Future<void> rejectPropertyBookingRequest(String requestId) async {
    final reqDoc = await getDocument('property_requests/$requestId');
    if (reqDoc == null) return;
    if (reqDoc['status'] != 'Pending') return;

    final renteeId = reqDoc['renteeId'] as String;
    final totalCost = (reqDoc['totalCost'] as num).toDouble();
    final bookingFee = (reqDoc['bookingFee'] as num).toDouble();
    final refundAmount = totalCost + bookingFee;

    await setDocument('property_requests/$requestId', {'status': 'Rejected'});

    // Revert promo usage
    final promoCode = reqDoc['promoCode'] as String?;
    if (promoCode != null) {
      await decrementPromoUsage(promoCode, renteeId);
    }


    final rentee = await getUser(renteeId);
    if (rentee != null) {
      await updateTyxBalance(renteeId, rentee.tyxBalance + refundAmount);

      final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
      final txData = {
        'uid': renteeId,
        'type': 'refund',
        'amount': refundAmount,
        'title': 'Property Booking Refund',
        'desc': 'Refund for rejected request of property "${reqDoc['title']}"',
        'method': 'Tranyx Wallet',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      await setDocument('transactions/$txId', txData);
    }

    await deleteDocument('property_escrows/$requestId');

    await createNotification(
      uid: renteeId,
      title: 'Booking Request Rejected',
      message: 'Your request to rent "${reqDoc['title']}" was rejected. Funds have been refunded.',
    );
  }

  /// Sign property contract to activate lease
  Future<void> signPropertyContract(String propertyId, String signatureDataUrl, {String? signatureHash}) async {
    final propDoc = await getDocument('properties/$propertyId');
    if (propDoc == null) throw Exception('Property listing not found.');

    final now = DateTime.now();
    await setDocument('properties/$propertyId', {
      'status': 'Booked',
      'renteeSignatureName': signatureDataUrl,
      'signedAt': now.millisecondsSinceEpoch,
      'signatureHash': ?signatureHash,
    });

    final hostId = propDoc['hostId'] as String;
    final renteeName = propDoc['renteeName'] as String? ?? 'Renter';
    final title = propDoc['title'] ?? '';

    await createNotification(
      uid: hostId,
      title: 'Lease Agreement Signed',
      message: '$renteeName has signed the Lease Agreement for "$title". The lease is now active.',
    );
  }

  /// Update property status
  Future<void> updatePropertyStatus(String propertyId, String status) async {
    await setDocument('properties/$propertyId', {'status': status});

    final propDoc = await getDocument('properties/$propertyId');
    if (propDoc != null) {
      final property = PropertyRental.fromMap(propDoc, propertyId);
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

  /// Complete property rental (releases escrow to host minus 3% commission, archives to history, sets status to Completed)
  Future<void> completePropertyRental(String propertyId) async {
    final propDoc = await getDocument('properties/$propertyId');
    if (propDoc == null) throw Exception('Property listing not found.');
    final property = PropertyRental.fromMap(propDoc, propertyId);

    final host = await getUser(property.hostId);
    if (host == null) throw Exception('Host profile not found.');

    final escrowDoc = await getDocument('property_escrows/$propertyId');
    if (escrowDoc == null) {
      throw Exception('Escrow transaction not found. Payout aborted to ensure secure transaction.');
    }
    if (escrowDoc['status'] != 'Held') {
      throw Exception('Escrow is not in Held status. Current status: ${escrowDoc['status']}. Payout aborted.');
    }

    final cost = property.totalCost ?? 0.0;
    final commission = cost * 0.03;
    final hostPayout = cost - commission;

    // Release payout
    final newHostBalance = host.tyxBalance + hostPayout;
    await updateTyxBalance(property.hostId, newHostBalance);

    // Save transaction record
    final txId = 'tx_${DateTime.now().microsecondsSinceEpoch}';
    final txData = {
      'uid': property.hostId,
      'type': 'payment',
      'amount': hostPayout,
      'baseAmount': cost,
      'commissionFee': commission,
      'commissionLabel': 'Platform Commission (3%)',
      'title': 'Property Rental Payout',
      'desc':
          'Earnings payout for "${property.title}" (3% platform commission of ${commission.toStringAsFixed(2)} TYXBIT deducted)',
      'method': 'Tranyx Wallet',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('transactions/$txId', txData);

    // Update escrow
    await setDocument('property_escrows/$propertyId', {
      'status': 'Released',
      'releasedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Save to history
    final historyId = 'ph_${DateTime.now().microsecondsSinceEpoch}';
    final historyDoc = {
      ...propDoc,
      'status': 'Completed',
      'completedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await setDocument('property_history/$historyId', historyDoc);

    // Update active property listing to Completed (does NOT reset to Available, preserving non-retention)
    await setDocument('properties/$propertyId', {
      'status': 'Completed',
    });

    // Notifications
    await createNotification(
      uid: property.hostId,
      title: 'Lease Completed & Paid',
      message:
          'Lease for "${property.title}" has been completed. Payout of ${hostPayout.toStringAsFixed(2)} TYXBIT credited to your wallet.',
    );
    if (property.renteeId != null && property.renteeId!.isNotEmpty) {
      await createNotification(
        uid: property.renteeId!,
        title: 'Lease Term Completed',
        message: 'Your lease for "${property.title}" has successfully ended. Thank you!',
      );
    }
  }

  /// Fetch all pending requests for a property
  Future<List<Map<String, dynamic>>> getPropertyPendingRequestsForProperty(String propertyId) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'property_requests'},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'propertyId'},
            'op': 'EQUAL',
            'value': {'stringValue': propertyId},
          },
        },
      },
    });

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) return [];

    final List<dynamic> results = jsonDecode(req.body);
    final list = <Map<String, dynamic>>[];
    for (final r in results) {
      if (r is Map && r.containsKey('document')) {
        final doc = r['document'] as Map<String, dynamic>;
        final name = doc['name'] as String;
        final docId = name.split('/').last;
        final data = _fromFirestoreDoc(doc);
        data['id'] = docId;
        if (data['status'] == 'Pending') {
          list.add(data);
        }
      }
    }
    return list;
  }

  /// Fetch approved request for a property
  Future<List<Map<String, dynamic>>> getPropertyApprovedRequests(String propertyId) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'property_requests'},
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'propertyId'},
                  'op': 'EQUAL',
                  'value': {'stringValue': propertyId},
                },
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'status'},
                  'op': 'EQUAL',
                  'value': {'stringValue': 'Approved'},
                },
              },
            ],
          },
        },
      },
    });

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) return [];

    final List<dynamic> results = jsonDecode(req.body);
    final list = <Map<String, dynamic>>[];
    for (final r in results) {
      if (r is Map && r.containsKey('document')) {
        final doc = r['document'] as Map<String, dynamic>;
        final name = doc['name'] as String;
        final docId = name.split('/').last;
        final data = _fromFirestoreDoc(doc);
        data['id'] = docId;
        list.add(data);
      }
    }
    return list;
  }

  /// Fetch pending property requests for a host
  Future<List<Map<String, dynamic>>> getPropertyPendingRequestsForHost(String hostId) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'property_requests'},
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'hostId'},
                  'op': 'EQUAL',
                  'value': {'stringValue': hostId},
                },
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'status'},
                  'op': 'EQUAL',
                  'value': {'stringValue': 'Pending'},
                },
              },
            ],
          },
        },
      },
    });

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) return [];

    final List<dynamic> results = jsonDecode(req.body);
    final list = <Map<String, dynamic>>[];
    for (final r in results) {
      if (r is Map && r.containsKey('document')) {
        final doc = r['document'] as Map<String, dynamic>;
        final name = doc['name'] as String;
        final docId = name.split('/').last;
        final data = _fromFirestoreDoc(doc);
        data['id'] = docId;
        list.add(data);
      }
    }
    return list;
  }

  /// Fetch pending property requests submitted by a renter
  Future<List<Map<String, dynamic>>> getPropertyPendingRequestsForRenter(String renteeId) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'property_requests'},
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'renteeId'},
                  'op': 'EQUAL',
                  'value': {'stringValue': renteeId},
                },
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'status'},
                  'op': 'EQUAL',
                  'value': {'stringValue': 'Pending'},
                },
              },
            ],
          },
        },
      },
    });

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) return [];

    final List<dynamic> results = jsonDecode(req.body);
    final list = <Map<String, dynamic>>[];
    for (final r in results) {
      if (r is Map && r.containsKey('document')) {
        final doc = r['document'] as Map<String, dynamic>;
        final name = doc['name'] as String;
        final docId = name.split('/').last;
        final data = _fromFirestoreDoc(doc);
        data['id'] = docId;
        list.add(data);
      }
    }
    return list;
  }

  Future<Promo?> getPromo(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return null;
    final doc = await getDocument('promos/$cleanCode');
    if (doc == null) return null;
    return Promo.fromMap(doc, cleanCode);
  }

  Future<List<Promo>> getAllActivePromos() async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'promos'},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'isActive'},
            'op': 'EQUAL',
            'value': {'booleanValue': true},
          },
        },
      },
    });

    try {
      final req = await http.post(Uri.parse(url), headers: headers, body: body);
      if (req.statusCode >= 400) return [];

      final results = jsonDecode(req.body) as List;
      final list = <Promo>[];
      for (final r in results) {
        if (r is Map && r.containsKey('document')) {
          final doc = r['document'] as Map<String, dynamic>;
          final name = doc['name'] as String;
          final docId = name.split('/').last;
          final data = _fromFirestoreDoc(doc);
          list.add(Promo.fromMap(data, docId));
        }
      }
      return list;
    } catch (e) {
      print('ERROR: getAllActivePromos failed: $e');
      return [];
    }
  }

  Future<List<NewsPost>> getAllActiveNewsPosts() async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'news_posts'},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'isActive'},
            'op': 'EQUAL',
            'value': {'booleanValue': true},
          },
        },
        'orderBy': [
          {
            'field': {'fieldPath': 'createdAt'},
            'direction': 'DESCENDING',
          }
        ],
      },
    });

    try {
      final req = await http.post(Uri.parse(url), headers: headers, body: body);
      if (req.statusCode >= 400) return [];

      final results = jsonDecode(req.body) as List;
      final list = <NewsPost>[];
      final now = DateTime.now();
      for (final r in results) {
        if (r is Map && r.containsKey('document')) {
          final doc = r['document'] as Map<String, dynamic>;
          final name = doc['name'] as String;
          final docId = name.split('/').last;
          final data = _fromFirestoreDoc(doc);
          final post = NewsPost.fromMap(data, docId);
          if (post.isActive && (post.publishAt == null || !post.publishAt!.isAfter(now))) {
            list.add(post);
          }
        }
      }
      return list;
    } catch (e) {
      print('ERROR: getAllActiveNewsPosts failed: $e');
      return [];
    }
  }

  Future<void> incrementPromoUsage(String promoId, String userId) async {
    final cleanCode = promoId.trim().toUpperCase();
    final promoDoc = await getDocument('promos/$cleanCode');
    if (promoDoc == null) return;

    final usedBy = List<String>.from(promoDoc['usedBy'] ?? []);
    if (!usedBy.contains(userId)) {
      usedBy.add(userId);
    }
    final usedCount = (promoDoc['usedCount'] as num? ?? 0).toInt() + 1;

    await setDocument('promos/$cleanCode', {
      ...promoDoc,
      'usedBy': usedBy,
      'usedCount': usedCount,
    });
  }

  Future<void> decrementPromoUsage(String promoId, String userId) async {
    final cleanCode = promoId.trim().toUpperCase();
    final promoDoc = await getDocument('promos/$cleanCode');
    if (promoDoc == null) return;

    final usedBy = List<String>.from(promoDoc['usedBy'] ?? []);
    usedBy.remove(userId);
    final usedCount = ((promoDoc['usedCount'] as num? ?? 0).toInt() - 1).clamp(0, 999999);

    await setDocument('promos/$cleanCode', {
      ...promoDoc,
      'usedBy': usedBy,
      'usedCount': usedCount,
    });
  }

  Future<String?> redeemPromoToProfile(String code, String userId) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return 'Please enter a promo code.';

    final promo = await getPromo(cleanCode);
    if (promo == null) return 'Promo code not found.';

    final userDoc = await getDocument('users/$userId');
    if (userDoc == null) return 'User profile not found.';
    final user = UserProfile.fromMap(userId, userDoc);

    if (user.disabledPromos.contains(cleanCode)) {
      return 'You have disabled this promotion and cannot re-enable it.';
    }

    final now = DateTime.now();
    if (!promo.isActive) return 'This promo code is inactive.';
    if (promo.expirationDate != null && promo.expirationDate!.isBefore(now)) {
      return 'This promo code has expired.';
    }
    if (promo.maxUsers != null && promo.usedCount >= promo.maxUsers!) {
      return 'This promo code has reached its maximum usage limit.';
    }
    if (promo.isSingleUsePerUser && promo.usedBy.contains(userId)) {
      return 'You have already used this promo code.';
    }
    if (promo.eligibleUserUids != null &&
        promo.eligibleUserUids!.isNotEmpty &&
        !promo.eligibleUserUids!.contains(userId)) {
      return 'You are not eligible for this promo code.';
    }
    if (promo.onlyForSubscribed && !user.isPremium) {
      return 'This promo code is only for subscribed premium users.';
    }
    if (promo.onlyForHybrid && user.accountType != AccountType.hybrid) {
      return 'This promo code is only for Hybrid PRO accounts.';
    }

    final roles = promo.applicableRoles;
    if (roles.isNotEmpty) {
      final userRoles = <String>[];
      if (user.accountType == AccountType.employer) {
        userRoles.addAll(['renter', 'employer']);
      } else if (user.accountType == AccountType.nyxian) {
        userRoles.addAll(['host', 'nyxian']);
      } else if (user.accountType == AccountType.hybrid) {
        userRoles.addAll(['renter', 'host', 'employer', 'nyxian']);
      }
      final hasMatchingRole = roles.any((r) => userRoles.contains(r));
      if (!hasMatchingRole) {
        return 'This promo code is not applicable for your account role.';
      }
    }

    await setDocument('users/$userId', {
      ...userDoc,
      'activePromoCode': cleanCode,
      'activePromoDiscountType': promo.discountType,
      'activePromoDiscountValue': promo.discountValue,
    });

    return null;
  }

  Future<void> disablePromoForUser(String code, String userId) async {
    final userDoc = await getDocument('users/$userId');
    if (userDoc == null) return;
    
    final disabledPromos = List<String>.from(userDoc['disabledPromos'] ?? []);
    if (!disabledPromos.contains(code)) {
      disabledPromos.add(code);
    }
    
    final updatedDoc = Map<String, dynamic>.from(userDoc);
    updatedDoc['activePromoCode'] = null;
    updatedDoc['activePromoDiscountType'] = null;
    updatedDoc['activePromoDiscountValue'] = null;
    updatedDoc['disabledPromos'] = disabledPromos;
    
    await setDocument('users/$userId', updatedDoc);
  }

  Future<bool> awardPointsIfEligible(String uid, String questId) async {
    try {
      final quest = RewardQuest.quests.firstWhere((q) => q.id == questId);
      final userDoc = await getDocument('users/$uid');
      if (userDoc == null) return false;

      final currentPoints = userDoc['terraPoints'] as int? ?? 0;
      final earnedRewards = List<String>.from(userDoc['earnedRewards'] as List? ?? []);

      if (quest.limit == 'Once' && earnedRewards.contains(questId)) {
        return false; // Already completed
      }

      // Update User Doc (write only target fields)
      final newRewards = List<String>.from(earnedRewards)..add(questId);
      await setDocument('users/$uid', {
        'terraPoints': currentPoints + quest.points,
        'earnedRewards': newRewards,
      });

      // Log to points_history
      final historyId = '${uid}_${questId}_${DateTime.now().millisecondsSinceEpoch}';
      await setDocument('points_history/$historyId', {
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

  Future<List<Map<String, dynamic>>> getUserPointsHistory(String uid) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': 'points_history'},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'uid'},
            'op': 'EQUAL',
            'value': {'stringValue': uid},
          },
        },
      }
    });

    try {
      final req = await _rawRequestWithRetry(url, idToken, _refreshToken, (token) {
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        return _client.post(Uri.parse(url), headers: headers, body: body);
      });

      if (req.statusCode >= 400) return [];

      final List<dynamic> results = jsonDecode(req.body);
      final list = <Map<String, dynamic>>[];
      for (final res in results) {
        if (res is Map<String, dynamic> && res.containsKey('document')) {
          final doc = res['document'] as Map<String, dynamic>;
          final id = (doc['name'] as String).split('/').last;
          final parsed = _fromFirestoreDoc(doc);
          list.add({...parsed, 'id': id});
        }
      }
      // Sort descending by createdAt
      list.sort((a, b) => (b['createdAt'] as int? ?? 0).compareTo(a['createdAt'] as int? ?? 0));
      return list;
    } catch (e) {
      print('getUserPointsHistory error: $e');
    }
    return [];
  }

  Future<bool> checkAndAwardOnboardingQuests(String uid) async {
    bool newlyAwarded = false;
    try {
      final userMap = await getDocument('users/$uid');
      if (userMap == null) return false;

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

      // 6. Deposit any amount to Wallet (tyxBalance > 0 means at least one deposit has occurred)
      final tyxBalance = (userMap['tyxBalance'] as num?)?.toDouble() ?? 0.0;
      if (tyxBalance > 0 && !earnedRewards.contains('deposit_any_amount')) {
        final success = await awardPointsIfEligible(uid, 'deposit_any_amount');
        if (success) newlyAwarded = true;
      }

      // 7. Subscribe to Hybrid PRO (isPremium == true)
      if (userMap['isPremium'] == true && !earnedRewards.contains('subscribe_hybrid_pro')) {
        final success = await awardPointsIfEligible(uid, 'subscribe_hybrid_pro');
        if (success) newlyAwarded = true;
      }
    } catch (e) {
      print('checkAndAwardOnboardingQuests error: $e');
    }
    return newlyAwarded;
  }
}

// ── Gemini AI Service ─────────────────────────────────────────────────────────
class GeminiService {
  final TranyxAIService _aiService;
  final Future<String?> Function()? onTokenRefresh;

  GeminiService(FirebaseConfig config, {String? idToken, this.onTokenRefresh, TranyxAIService? aiService})
      : _aiService = aiService ?? TranyxAIService();

  Future<String> generateJobDescription(String title, {String? categoryLabel}) async {
    if (title.isEmpty) return '';
    return _aiService.generateJobDescription(title, categoryLabel: categoryLabel);
  }

  Future<String> generateJobTitle(String categoryLabel, String categoryDesc, String description) async {
    final matchedCategory = JobCategory.values.firstWhere(
      (c) => c.label.toLowerCase() == categoryLabel.toLowerCase(),
      orElse: () => JobCategory.others,
    );
    return _aiService.generateJobTitle(matchedCategory, description);
  }

  Future<String> evaluateJobAuthenticity(Map<String, dynamic> jobData) async {
    return _aiService.evaluateJobAuthenticity(jobData);
  }

  Future<bool> validateJobTitle(String title, String categoryLabel) async {
    final matchedCategory = JobCategory.values.firstWhere(
      (c) => c.label.toLowerCase() == categoryLabel.toLowerCase(),
      orElse: () => JobCategory.others,
    );
    return _aiService.validateJobTitle(title, matchedCategory);
  }

  Future<String> generateCoverNote(String jobTitle, {String? workerExperience}) async {
    if (jobTitle.isEmpty) return '';
    return _aiService.generateCoverNote(jobTitle, workerExperience: workerExperience);
  }

  Future<String> askSupportQuestion(
    List<Map<String, String>> conversationHistory, {
    TranyxAIUserContext? appContext,
  }) async {
    if (conversationHistory.isEmpty) return 'Please ask a valid question.';
    return _aiService.getChatResponse(conversationHistory, appContext: appContext);
  }
}

typedef LocalNyxAIService = GeminiService;


// ── ImgBB service ─────────────────────────────────────────────────────────────
class ImgBBService {
  final FirebaseConfig _config;
  String? _idToken;
  final Future<String?> Function()? onTokenRefresh;
  String? _imgbbKeyCache;

  ImgBBService(this._config, {String? idToken, this.onTokenRefresh}) : _idToken = idToken;

  Future<String?> _refreshToken() async {
    if (onTokenRefresh != null) {
      final newToken = await onTokenRefresh!();
      if (newToken != null) {
        _idToken = newToken;
        return newToken;
      }
    }
    return null;
  }

  Future<String> _getApiKey() async {
    if (_imgbbKeyCache != null) return _imgbbKeyCache!;
    try {
      final url =
          'https://firestore.googleapis.com/v1/projects/${_config.projectId}/databases/(default)/documents/config/app_config';
      final res = await _get(url, idToken: _idToken, onTokenRefresh: _refreshToken);
      final fields = res['fields'] as Map<String, dynamic>?;
      final keyVal = fields?['imgbb']?['stringValue'] as String?;
      if (keyVal != null && keyVal.isNotEmpty) {
        _imgbbKeyCache = keyVal;
        return keyVal;
      }
    } catch (_) {}
    return Env.imgbbApiKey;
  }

  Future<String?> uploadImageBytes(List<int> bytes, String filename, {int? expiration}) async {
    try {
      final apiKey = await _getApiKey();
      if (apiKey.isEmpty) return null;

      var uri = Uri.parse('https://api.imgbb.com/1/upload');
      uri = uri.replace(
        queryParameters: {
          'key': apiKey,
          if (expiration != null) 'expiration': expiration.toString(),
        },
      );

      var request = http.MultipartRequest('POST', uri);

      // Attach the file
      request.files.add(http.MultipartFile.fromBytes('image', bytes, filename: filename));

      // Send the request
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data']['url'] as String?;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
