// ignore_for_file: subtype_of_sealed_class

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';
import 'package:tranyx_mobile/core/providers/fcm_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';
import 'helpers/fake_firestore.dart';

// ─── Mocks ──────────────────────────────────────────────────────────────────

class MockUser extends Fake implements User {
  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? displayName;

  MockUser({required this.uid, this.email, this.displayName});

  @override
  bool get emailVerified => true;
}

class MockUserCredential extends Fake implements UserCredential {
  @override
  final User? user;
  MockUserCredential(this.user);
}

class FakeFirebaseAuth extends Fake implements FirebaseAuth {
  User? _currentUser;

  FakeFirebaseAuth({User? initialUser}) : _currentUser = initialUser;

  @override
  User? get currentUser => _currentUser;

  @override
  Stream<User?> authStateChanges() async* {
    yield _currentUser;
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final user = MockUser(uid: 'mock_uid_123', email: email);
    _currentUser = user;
    return MockUserCredential(user);
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final user = MockUser(uid: 'mock_uid_123', email: email);
    _currentUser = user;
    return MockUserCredential(user);
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }
}

class MockPhantomService extends Fake implements PhantomService {
  final String mockPublicKey;
  MockPhantomService({required this.mockPublicKey});

  @override
  Map<String, dynamic>? decryptConnectResponse({
    required String phantomPubB58,
    required String dataB58,
    required String nonceB58,
    required Uint8List sessionPrivateKeyBytes,
  }) {
    return {'public_key': mockPublicKey};
  }
}

class MockFirebaseMessagingService extends Fake
    implements FirebaseMessagingService {
  @override
  Future<void> initialize(BuildContext context) async {}

  @override
  void dispose() {}
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Simulates the /onConnect handler logic that lives in app_router.dart.
/// We call it directly to avoid widget-tree complexity.
Future<void> simulateOnConnect({
  required ProviderContainer container,
  required FakeFirebaseAuth fakeAuth,
  required String solanaPublicKey,
  /// Called when a password prompt is needed — return the user's answer.
  Future<String?> Function(String email)? onPasswordPrompt,
}) async {
  final ref = container;

  final user = fakeAuth.currentUser;
  final walletType = ref.read(connectingWalletTypeProvider) ?? 'phantom';

  // Clear session state (mirrors the router)
  ref.read(phantomSessionPrivateKeyProvider.notifier).state = null;
  ref.read(connectingWalletTypeProvider.notifier).state = null;

  final firestore = ref.read(firestoreProvider);

  if (user != null) {
    // ── Linked-wallet update path (user already logged in) ─────────────────
    await firestore
        .collection('users')
        .doc(user.uid)
        .update({
          'walletPublicKey': solanaPublicKey,
          'connectedWalletType': walletType,
        });

    ref.invalidate(userProfileProvider);

    final password = await SecureStorageHelper.getPassword();
    final obfuscatedPassword =
        password != null ? SecureStorageHelper.obfuscate(password) : null;

    final linkData = <String, dynamic>{
      'uid': user.uid,
      'email': user.email,
      'linkedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (obfuscatedPassword != null) {
      linkData['password'] = obfuscatedPassword;
    }

    await firestore
        .collection('walletLinks')
        .doc(solanaPublicKey)
        .set(linkData);
  } else {
    // ── Wallet sign-in path (user NOT logged in) ────────────────────────────
    final walletLinkDoc = await firestore
        .collection('walletLinks')
        .doc(solanaPublicKey)
        .get();

    if (!walletLinkDoc.exists) {
      ref.read(pendingWalletPublicKeyProvider.notifier).state = solanaPublicKey;
      ref.read(authViewProvider.notifier).state = 'register-path';
      return;
    }

    final linkData = walletLinkDoc.data();
    var email = linkData?['email'] as String?;
    final uid = linkData?['uid'] as String?;
    final obfuscatedPassword = linkData?['password'] as String?;

    if ((email == null || email.isEmpty) && uid != null) {
      final userDoc =
          await firestore.collection('users').doc(uid).get();
      email = userDoc.data()?['email'] as String?;
    }

    if (email == null || email.isEmpty) {
      throw 'No email associated with this wallet link.';
    }

    if (obfuscatedPassword != null && obfuscatedPassword.isNotEmpty) {
      final password = SecureStorageHelper.deobfuscate(obfuscatedPassword);
      await fakeAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } else {
      // Prompt the user for a password
      final password = await onPasswordPrompt?.call(email);
      if (password != null && password.isNotEmpty) {
        await fakeAuth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        await SecureStorageHelper.savePassword(password);
        await firestore
            .collection('walletLinks')
            .doc(solanaPublicKey)
            .update({
              'password': SecureStorageHelper.obfuscate(password),
            });
      }
    }
  }
}

// ─── Test suite ───────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> secureStorageValues = {};

  setUp(() {
    secureStorageValues.clear();

    final handler = (MethodCall methodCall) async {
      if (methodCall.method == 'write') {
        secureStorageValues[methodCall.arguments['key'] as String] =
            methodCall.arguments['value'] as String;
        return true;
      }
      if (methodCall.method == 'read') {
        return secureStorageValues[methodCall.arguments['key'] as String];
      }
      if (methodCall.method == 'delete') {
        secureStorageValues.remove(methodCall.arguments['key'] as String);
        return true;
      }
      if (methodCall.method == 'clear') {
        secureStorageValues.clear();
        return true;
      }
      return null;
    };

    for (final channel in [
      'plugins.it_nomads.com/flutter_secure_storage',
      'plugins.it_nomads.com/flutter_secure_storage_darwin',
      'plugins.it_nomads.com/flutter_secure_storage_macos',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), handler);
    }
  });

  const mockPublicKey = '4zMMC4mCK23ccaJ2rbzn36gkJr2cT6w9P5BmgFniS1234';

  group('Solana Wallet Connect — Logic Tests', () {
    // ── Test 1 ───────────────────────────────────────────────────────────────
    test('1. Logged-in user: links wallet and writes walletLinks entry', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final fakeAuth = FakeFirebaseAuth(
        initialUser: MockUser(uid: 'user_123', email: 'test@tranyx.com'),
      );

      // Seed user doc so update() doesn't throw "not found"
      fakeFirestore.db['users/user_123'] = {
        'uid': 'user_123',
        'name': 'Test User',
        'email': 'test@tranyx.com',
        'accountType': 'employer',
      };

      // Pre-save a password so it gets obfuscated into walletLinks
      await SecureStorageHelper.savePassword('password123');

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(fakeFirestore),
          firebaseAuthProvider.overrideWithValue(fakeAuth),
          fcmProvider.overrideWithValue(MockFirebaseMessagingService()),
          phantomServiceProvider.overrideWithValue(
            MockPhantomService(mockPublicKey: mockPublicKey),
          ),
          phantomSessionPrivateKeyProvider.overrideWith(
            (ref) => Uint8List.fromList([1, 2, 3]),
          ),
          connectingWalletTypeProvider.overrideWith((ref) => 'phantom'),
        ],
      );
      addTearDown(container.dispose);

      await simulateOnConnect(
        container: container,
        fakeAuth: fakeAuth,
        solanaPublicKey: mockPublicKey,
      );

      // User doc updated
      final userDoc = fakeFirestore.db['users/user_123'];
      expect(userDoc, isNotNull);
      expect(userDoc!['walletPublicKey'], equals(mockPublicKey));

      // walletLinks written
      final linkDoc = fakeFirestore.db['walletLinks/$mockPublicKey'];
      expect(linkDoc, isNotNull);
      expect(linkDoc!['uid'], equals('user_123'));
      expect(linkDoc['email'], equals('test@tranyx.com'));
      expect(
        SecureStorageHelper.deobfuscate(linkDoc['password'] as String),
        equals('password123'),
      );
    });

    // ── Test 2 ───────────────────────────────────────────────────────────────
    test('2. Not logged-in: auto signs in via obfuscated password in walletLinks', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final fakeAuth = FakeFirebaseAuth(initialUser: null);

      // Seed wallet link with obfuscated password
      fakeFirestore.db['walletLinks/$mockPublicKey'] = {
        'uid': 'user_123',
        'email': 'test@tranyx.com',
        'password': SecureStorageHelper.obfuscate('password123'),
        'linkedAt': DateTime.now().millisecondsSinceEpoch,
      };

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(fakeFirestore),
          firebaseAuthProvider.overrideWithValue(fakeAuth),
          fcmProvider.overrideWithValue(MockFirebaseMessagingService()),
          phantomServiceProvider.overrideWithValue(
            MockPhantomService(mockPublicKey: mockPublicKey),
          ),
          phantomSessionPrivateKeyProvider.overrideWith(
            (ref) => Uint8List.fromList([1, 2, 3]),
          ),
          connectingWalletTypeProvider.overrideWith((ref) => 'phantom'),
        ],
      );
      addTearDown(container.dispose);

      await simulateOnConnect(
        container: container,
        fakeAuth: fakeAuth,
        solanaPublicKey: mockPublicKey,
      );

      expect(fakeAuth.currentUser, isNotNull);
      expect(fakeAuth.currentUser!.email, equals('test@tranyx.com'));
    });

    // ── Test 3 ───────────────────────────────────────────────────────────────
    test('3. Not logged-in, no password in link: prompts & saves password, then signs in', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final fakeAuth = FakeFirebaseAuth(initialUser: null);

      // Link exists but WITHOUT a password (e.g. linked via web)
      fakeFirestore.db['walletLinks/$mockPublicKey'] = {
        'uid': 'user_123',
        'email': 'test@tranyx.com',
        'linkedAt': DateTime.now().millisecondsSinceEpoch,
      };

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(fakeFirestore),
          firebaseAuthProvider.overrideWithValue(fakeAuth),
          fcmProvider.overrideWithValue(MockFirebaseMessagingService()),
          phantomServiceProvider.overrideWithValue(
            MockPhantomService(mockPublicKey: mockPublicKey),
          ),
          phantomSessionPrivateKeyProvider.overrideWith(
            (ref) => Uint8List.fromList([1, 2, 3]),
          ),
          connectingWalletTypeProvider.overrideWith((ref) => 'phantom'),
        ],
      );
      addTearDown(container.dispose);

      await simulateOnConnect(
        container: container,
        fakeAuth: fakeAuth,
        solanaPublicKey: mockPublicKey,
        // Simulate user typing their password in the dialog
        onPasswordPrompt: (_) async => 'password123',
      );

      // Signed in
      expect(fakeAuth.currentUser, isNotNull);
      expect(fakeAuth.currentUser!.email, equals('test@tranyx.com'));

      // Password saved locally
      final savedPassword = await SecureStorageHelper.getPassword();
      expect(savedPassword, equals('password123'));

      // walletLinks updated with obfuscated password
      final linkDoc = fakeFirestore.db['walletLinks/$mockPublicKey'];
      expect(linkDoc, isNotNull);
      expect(
        SecureStorageHelper.deobfuscate(linkDoc!['password'] as String),
        equals('password123'),
      );
    });

    // ── Test 4 ───────────────────────────────────────────────────────────────
    test('4. Not logged-in, unregistered wallet: sets register-path & pendingWalletPublicKey', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final fakeAuth = FakeFirebaseAuth(initialUser: null);

      // No walletLinks entry exists
      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(fakeFirestore),
          firebaseAuthProvider.overrideWithValue(fakeAuth),
          fcmProvider.overrideWithValue(MockFirebaseMessagingService()),
          phantomServiceProvider.overrideWithValue(
            MockPhantomService(mockPublicKey: 'unregistered_wallet_key'),
          ),
          phantomSessionPrivateKeyProvider.overrideWith(
            (ref) => Uint8List.fromList([1, 2, 3]),
          ),
          connectingWalletTypeProvider.overrideWith((ref) => 'phantom'),
        ],
      );
      addTearDown(container.dispose);

      await simulateOnConnect(
        container: container,
        fakeAuth: fakeAuth,
        solanaPublicKey: 'unregistered_wallet_key',
      );

      // User stays logged out
      expect(fakeAuth.currentUser, isNull);

      // Auth view state -> register path
      expect(
        container.read(authViewProvider),
        equals('register-path'),
      );

      // Pending public key set
      expect(
        container.read(pendingWalletPublicKeyProvider),
        equals('unregistered_wallet_key'),
      );
    });
  });
}
