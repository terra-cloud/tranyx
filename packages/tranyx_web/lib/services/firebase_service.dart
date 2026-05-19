// Firebase REST API service — only imported by @client components (browser-only)
// Uses package:http and package:web for web-safe networking and storage.
// Run jaspr with: --dart-define=ENV=dev   (or uat / prod)

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

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

  factory FirebaseConfig.fromShared(SharedFirebaseOptions options) {
    return FirebaseConfig(
      apiKey: options.apiKey,
      authDomain: '${options.projectId}.firebaseapp.com',
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
    options = DefaultFirebaseConfig.prodAndroid;
  } else if (env == 'uat') {
    options = DefaultFirebaseConfig.uatAndroid;
  } else {
    options = DefaultFirebaseConfig.devAndroid;
  }

  return FirebaseConfig.fromShared(options);
}

final currentFirebaseConfig = _getEnvironmentConfig();

// ── Endpoints ───────────────────────────────────────────────────────────────
const _authBase = 'https://identitytoolkit.googleapis.com/v1/accounts';
String get _firestoreBase =>
    'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents';

// ── Generic HTTP helpers ──────────────────────────────────────────────────────
final _client = http.Client();

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

Future<Map<String, dynamic>> _requestWithRetry(
  String url,
  String? initialToken,
  Future<String?> Function()? onTokenRefresh,
  Future<http.Response> Function(String? token) requestBuilder,
) async {
  var token = initialToken;
  var req = await requestBuilder(token);

  if (req.statusCode == 401 && onTokenRefresh != null) {
    try {
      final newToken = await onTokenRefresh();
      if (newToken != null) {
        token = newToken;
        req = await requestBuilder(token);
      }
    } catch (_) {
      // Ignore refresh errors and let the original 401 propagate
    }
  }

  final bodyText = req.body.trim();
  final data = bodyText.isNotEmpty ? jsonDecode(bodyText) : <String, dynamic>{};

  if (req.statusCode >= 400) {
    final err = (data is Map) ? (data['error'] as Map? ?? {}) : {};
    throw FirebaseException(err['message'] as String? ?? 'Request failed', req.statusCode);
  }
  return data as Map<String, dynamic>;
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
class FirebaseException implements Exception {
  final String message;
  final int? statusCode;
  FirebaseException(this.message, [this.statusCode]);
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

class FirebaseAuthService {
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
    final res = await _post(
      'https://securetoken.googleapis.com/v1/token?key=${currentFirebaseConfig.apiKey}',
      {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
    );
    return res['id_token'] as String;
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
      onTokenRefresh,
    );
  }

  Future<void> createOrUpdate(String path, Map<String, dynamic> data) async {
    final url = '$_firestoreBase/$path';
    final body = _toFirestoreFields(data);
    await _patch(url, body, idToken, onTokenRefresh);
  }

  Future<void> deleteDocument(String path) async {
    final url = '$_firestoreBase/$path';
    final headers = <String, String>{};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';
    await _client.delete(Uri.parse(url), headers: headers);
  }

  Future<Map<String, dynamic>?> getDocument(String path) async {
    try {
      final url = '$_firestoreBase/$path';
      final res = await _get(url, idToken: idToken, onTokenRefresh: onTokenRefresh);
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

  Future<void> saveUser(UserProfile profile) async {
    await createOrUpdate('users/${profile.uid}', profile.toMap());
  }

  // ── Wallet Links ───────────────────────────────────────────
  /// Stores a mapping from walletPublicKey -> uid in walletLinks collection.
  Future<void> linkWalletToUser(String uid, String walletPublicKey, {String? refreshToken}) async {
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
    // Use a POST to create with auto-generated ID
    final url = '$_firestoreBase/jobs';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final req = await _client.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(_toFirestoreFields(jobData)),
    );

    if (req.statusCode >= 400) {
      final data = jsonDecode(req.body) as Map<String, dynamic>;
      final err = data['error'] as Map? ?? {};
      throw FirebaseException(err['message'] as String? ?? 'Create job failed', req.statusCode);
    }

    final result = jsonDecode(req.body) as Map<String, dynamic>;
    return _docId(result);
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
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

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

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) {
      return []; // Return empty if error or not found
    }

    final List<dynamic> results = jsonDecode(req.body);
    final transactions = <Map<String, dynamic>>[];
    for (final res in results) {
      if (res is Map<String, dynamic> && res.containsKey('document')) {
        final doc = res['document'] as Map<String, dynamic>;
        final id = _docId(doc);
        transactions.add({'id': id, ..._fromFirestoreDoc(doc)});
      }
    }
    return transactions;
  }

  /// Fetch notifications for [uid].
  Future<List<Map<String, dynamic>>> getNotifications(String uid) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

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

    final req = await http.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) {
      return [];
    }

    final List<dynamic> results = jsonDecode(req.body);
    final notifications = <Map<String, dynamic>>[];
    for (final res in results) {
      if (res is Map<String, dynamic> && res.containsKey('document')) {
        final doc = res['document'] as Map<String, dynamic>;
        final id = _docId(doc);
        notifications.add({'id': id, ..._fromFirestoreDoc(doc)});
      }
    }
    return notifications;
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

  Future<List<Map<String, dynamic>>> _queryJobs(List<Map<String, dynamic>> filters) async {
    final url =
        'https://firestore.googleapis.com/v1/projects/${currentFirebaseConfig.projectId}/databases/(default)/documents:runQuery';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final body = jsonEncode({
      'structuredQuery': {
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
        'orderBy': [
          {
            'field': {'fieldPath': 'createdAt'},
            'direction': 'DESCENDING',
          },
        ],
        'limit': 50,
      },
    });

    final req = await _client.post(Uri.parse(url), headers: headers, body: body);
    if (req.statusCode >= 400) {
      print('FIRESTORE QUERY ERROR: ${req.statusCode} - ${req.body}');
      return [];
    }

    final results = jsonDecode(req.body) as List;
    return results.where((r) => (r as Map).containsKey('document')).map((r) {
      final doc = (r as Map<String, dynamic>)['document'] as Map<String, dynamic>;
      final id = _docId(doc);
      return {'id': id, ..._fromFirestoreDoc(doc)};
    }).toList();
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
    }
  }

  Future<List<Map<String, dynamic>>> getApplications(String jobId) async {
    final url = '$_firestoreBase/jobs/$jobId/applications';
    final headers = <String, String>{};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final req = await _client.get(Uri.parse(url), headers: headers);
    if (req.statusCode >= 400) return [];

    final data = jsonDecode(req.body) as Map<String, dynamic>;
    final docs = data['documents'] as List? ?? [];
    return docs.map((d) {
      final doc = d as Map<String, dynamic>;
      final id = _docId(doc);
      return {'id': id, ..._fromFirestoreDoc(doc)};
    }).toList();
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
    // POST to auto-generate ID
    final url = '$_firestoreBase/jobs/$jobId/questions';
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final req = await _client.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode(_toFirestoreFields(questionData)),
    );

    if (req.statusCode >= 400) throw FirebaseException('Add question failed: ${req.statusCode}');
    final result = jsonDecode(req.body) as Map<String, dynamic>;
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
    final headers = <String, String>{};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';
    await _client.delete(Uri.parse(url), headers: headers);
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
    final headers = <String, String>{};
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';

    final req = await _client.get(Uri.parse(url), headers: headers);
    if (req.statusCode >= 400) return [];

    final data = jsonDecode(req.body) as Map<String, dynamic>;
    final docs = data['documents'] as List? ?? [];
    final result = docs.map((d) {
      final doc = d as Map<String, dynamic>;
      final id = _docId(doc);
      return {'id': id, ..._fromFirestoreDoc(doc)};
    }).toList();
    result.sort((a, b) => (a['createdAt'] as int? ?? 0).compareTo(b['createdAt'] as int? ?? 0));
    return result;
  }
}

// ── Gemini AI service ─────────────────────────────────────────────────────────
class GeminiService {
  final FirebaseConfig _config;
  final String? _idToken;
  String? _geminiKeyCache;

  GeminiService(this._config, {String? idToken}) : _idToken = idToken;

  Future<String> _getApiKey() async {
    if (_geminiKeyCache != null) return _geminiKeyCache!;
    try {
      final url =
          'https://firestore.googleapis.com/v1/projects/${_config.projectId}/databases/(default)/documents/config/app_config';
      final res = await _get(url, idToken: _idToken);
      final fields = res['fields'] as Map<String, dynamic>?;
      final geminiVal = fields?['gemini']?['stringValue'] as String?;
      if (geminiVal != null && geminiVal.isNotEmpty) {
        _geminiKeyCache = geminiVal;
        return geminiVal;
      }
    } catch (_) {
      // Fallback to Firebase API key if fetch fails
    }
    return _config.apiKey;
  }

  Future<String> generateJobDescription(String title) async {
    if (title.isEmpty) return '';

    final prompt =
        'Generate a professional job description for a gig titled "$title". '
        'IMPORTANT: DO NOT include the explanation, just the description.'
        'IMPORTANT: Detect the language of the title. If the title is in Waray-Waray, the description MUST be in Waray-Waray. '
        'If the title is in English, the description MUST be in English. '
        'Keep it concise, clear, and professional. '
        'Mention that the worker should bring basic tools if applicable. '
        'Limit to about 3-4 sentences.';
    return _generate(prompt);
  }

  Future<String> generateJobTitle(String categoryLabel, String categoryDesc, String description) async {
    final descPart = description.isEmpty
        ? 'its official description: "$categoryDesc"'
        : 'the following user-provided description: "$description"';

    final prompt =
        'Category: "$categoryLabel"\n'
        'Context: $descPart\n\n'
        'Task: Generate a professional and catchy job title (maximum 5 words) that perfectly fits this category and context. '
        'IMPORTANT: Detect the language of the Context. It should match the Job Title\'s language. '
        'IMPORTANT: DO NOT include the explanation, just the description.'
        'If it is in English, generate the title in English. '
        'Return ONLY the title text. Do not include quotes or extra explanations.';

    final result = await _generate(prompt);
    return result.replaceAll('"', '').trim();
  }

  Future<String> evaluateJobAuthenticity(Map<String, dynamic> jobData) async {
    final title = jobData['title'] as String? ?? '';
    final description = jobData['description'] as String? ?? '';
    final rate = jobData['pricingValue']?.toString() ?? 'Unknown';
    final type = jobData['employmentType'] as String? ?? '';
    final category = jobData['category'] as String? ?? '';

    final prompt =
        'You are an AI tasked with evaluating the authenticity and intent of a job posting.\n'
        'Job Title: "$title"\n'
        'Category: "$category"\n'
        'Employment Type: "$type"\n'
        'Rate: $rate PHP\n'
        'Description: "$description"\n\n'
        'Please provide a short, 2-3 sentence evaluation of this job posting. '
        'Assess whether the rate seems reasonable for the task, if the description is clear and realistic, '
        'and provide a general "Authenticity Score" out of 10 at the end.';

    return _generate(prompt);
  }

  Future<bool> validateJobTitle(String title, String categoryLabel) async {
    if (title.isEmpty) return false;

    final prompt =
        'Verify if the job title matches the category.\n\n'
        'Category: "$categoryLabel"\n'
        'Job Title: "$title"\n\n'
        'Does this title reasonably belong to this category? Respond with ONLY "YES" or "NO".';

    final result = (await _generate(prompt)).trim().toUpperCase();
    return result.contains('YES');
  }

  Future<String> generateCoverNote(String jobTitle) async {
    if (jobTitle.isEmpty) return '';

    final prompt =
        'Write a professional and enthusiastic cover note applying for a gig titled "$jobTitle". '
        'IMPORTANT: Detect the language of the job title. If the title is in Waray-Waray, the note MUST be in Waray-Waray. '
        'If the title is in English, the note MUST be in English. '
        'Mention having relevant experience, being reliable, and possessing the necessary tools. '
        'Keep it friendly and concise (2-3 sentences).';
    return _generate(prompt);
  }

  Future<String> askSupportQuestion(String question) async {
    if (question.isEmpty) return 'Please ask a valid question.';
    final prompt =
        'You are the friendly, intelligent AI support assistant for Tranyx, a premium Web3 freelance gig marketplace in the Philippines. '
        'You must provide accurate support based on the following app flow:\n'
        '1. Roles: Employers post jobs; Nyxians (workers) apply.\n'
        '2. Payment: Employers deposit funds (PHP via GCash/Xendit or Crypto via Phantom) into Escrow when posting a job.\n'
        '3. Standard Jobs: When work is done, the Employer generates a "Completion Code" from their dashboard, which they give to the Nyxian. The Nyxian inputs this code to release escrow.\n'
        '4. Delivery (Tracker) Jobs: The Nyxian updates tracking stages (pickup, dropoff). At the final stage, the Nyxian generates a "Payment Code" which the Employer scans/inputs to release payment.\n'
        '5. Fees: 3% platform fee is deducted from the payout to the Nyxian.\n'
        'Answer the following user support question in a friendly, helpful, and concise manner based ONLY on the workflow above. '
        'If the question is in Tagalog or Waray-Waray, respond in that language. Otherwise respond in English. '
        'Keep the answer within 3-4 sentences.\n\n'
        'User Question: "$question"';
    return _generate(prompt);
  }

  Future<String> _generate(String prompt) async {
    final apiKey = await _getApiKey();
    final baseUrl =
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey';

    const delays = [1000, 2000, 4000];
    for (var i = 0; i <= 3; i++) {
      try {
        final res = await _post(
          baseUrl,
          {
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
          },
        );
        final candidates = res['candidates'] as List?;
        final content = candidates?.first['content'] as Map?;
        final parts = content?['parts'] as List?;
        return parts?.first['text'] as String? ?? '';
      } catch (e) {
        if (i == 3) rethrow;
        await Future.delayed(Duration(milliseconds: delays[i]));
      }
    }
    return '';
  }
}

// ── ImgBB service ─────────────────────────────────────────────────────────────
class ImgBBService {
  final FirebaseConfig _config;
  final String? _idToken;
  String? _imgbbKeyCache;

  ImgBBService(this._config, {String? idToken}) : _idToken = idToken;

  Future<String> _getApiKey() async {
    if (_imgbbKeyCache != null) return _imgbbKeyCache!;
    try {
      final url =
          'https://firestore.googleapis.com/v1/projects/${_config.projectId}/databases/(default)/documents/config/app_config';
      final res = await _get(url, idToken: _idToken);
      final fields = res['fields'] as Map<String, dynamic>?;
      final keyVal = fields?['imgbb']?['stringValue'] as String?;
      if (keyVal != null && keyVal.isNotEmpty) {
        _imgbbKeyCache = keyVal;
        return keyVal;
      }
    } catch (_) {}
    return '50952d72f276ff20aa3362f346b134ab'; // Fallback working apiKey from mobile
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
