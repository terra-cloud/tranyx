import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared/shared.dart';
export 'package:shared/shared.dart' show AccountType, EmployerType, UserProfile;
import 'package:tranyx_mobile/flavors.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final authStateProvider = Provider<bool>((ref) {
  final user = ref.watch(authStateChangesProvider).value;
  return user != null;
});

final userProvider = Provider<User?>((ref) {
  return ref.watch(authStateChangesProvider).value;
});

final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return Stream.value(null);

  // Silently run onboarding quests check in the background when the profile stream is subscribed
  final repo = ref.read(transitRepositoryProvider);
  repo.checkAndAwardOnboardingQuests(user.uid);
  repo.checkAndExpireSubscription(user.uid);

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((doc) {
        if (!doc.exists || doc.data() == null) {
          return null;
        }
        return UserProfile.fromMap(user.uid, doc.data()!);
      });
});

class AuthController {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final Ref _ref;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  AuthController(this._auth, this._firestore, this._ref);

  Future<void> signInWithEmailAndPassword(String email, String password) async {
    final userCredential = await _auth.signInWithEmailAndPassword(email: email, password: password);
    await SecureStorageHelper.savePassword(password);

    final user = userCredential.user;
    if (user != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        final defaultName = user.displayName != null && user.displayName!.isNotEmpty
            ? user.displayName!
            : email.split('@').first;
        final profile = UserProfile(
          uid: user.uid,
          name: defaultName,
          email: email,
          accountType: AccountType.employer,
          createdAt: DateTime.now(),
        );
        try {
          await _firestore.collection('users').doc(user.uid).set(profile.toMap());
        } catch (e) {
          debugPrint('Error creating initial user document on email sign-in: $e');
        }
      }
    }

    await _linkPendingWallet(password);
  }

  Future<void> createUserWithEmailAndPassword({
    required String email,
    required String password,
    required String displayName,
    required AccountType accountType,
    AccountType? baseType,
    EmployerType? employerType,
    String? businessName,
    String? businessPermit,
  }) async {
    final userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await SecureStorageHelper.savePassword(password);

    final user = userCredential.user;
    if (user != null) {
      await user.updateDisplayName(displayName);

      final profile = UserProfile(
        uid: user.uid,
        name: displayName,
        email: email,
        accountType: accountType,
        employerType: accountType == AccountType.employer
            ? (employerType ?? EmployerType.personal)
            : null,
        businessName: businessName,
        businessPermit: businessPermit,
        createdAt: DateTime.now(),
      );

      await _firestore.collection('users').doc(user.uid).set(profile.toMap());
      await _linkPendingWallet(password);
      await SecureStorageHelper.saveHasSeenOnboarding(false);
    }
  }

  Future<void> signInWithGoogle({AccountType? pendingType}) async {
    await _googleSignIn.initialize(
      clientId: F.googleClientId,
      serverClientId: F.googleServerClientId,
      // serverClientId is null for non-prod flavors — GoogleSignIn accepts null fine
    );
    final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

    final GoogleSignInAuthentication googleAuth = googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    final userCredential = await _auth.signInWithCredential(credential);

    final user = userCredential.user;
    if (user != null) {
      final googleEmail = user.email ?? googleUser.email;

      if (pendingType != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          // Only create profile automatically if it's Nyxian and we have a name
          if (pendingType == AccountType.nyxian &&
              user.displayName != null &&
              user.displayName!.isNotEmpty) {
            final profile = UserProfile(
              uid: user.uid,
              name: user.displayName!,
              email: googleEmail,
              photoUrl: user.photoURL,
              accountType: pendingType,
              googleEmail: googleEmail,
              createdAt: DateTime.now(),
            );
            await _firestore
                .collection('users')
                .doc(user.uid)
                .set(profile.toMap());
          }
        } else {
          // Doc already exists — ensure googleEmail is stamped
          await _firestore.collection('users').doc(user.uid).update({
            'googleEmail': googleEmail,
          });
        }
      } else {
        // Sign-in without pending account type — stamp googleEmail on existing doc
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          await _firestore.collection('users').doc(user.uid).update({
            'googleEmail': googleEmail,
          });
        }
      }

      await _linkPendingWallet(null);
    }
  }

  Future<void> _linkPendingWallet(String? password) async {
    final pendingWalletKey = _ref.read(pendingWalletPublicKeyProvider);
    if (pendingWalletKey != null) {
      _ref.read(pendingWalletPublicKeyProvider.notifier).state = null;
      try {
        final user = _auth.currentUser;
        if (user != null) {
          final providers = user.providerData.map((p) => p.providerId).toList();
          final provider = providers.contains('google.com') ? 'google.com' : 'password';

          final linkData = <String, dynamic>{
            'uid': user.uid,
            'email': user.email,
            'provider': provider,
            'linkedAt': DateTime.now().millisecondsSinceEpoch,
          };
          if (password != null) {
            linkData['password'] = SecureStorageHelper.obfuscate(password);
          }
          await _firestore
              .collection('walletLinks')
              .doc(pendingWalletKey)
              .set(linkData);
          await _firestore.collection('users').doc(user.uid).update({
            'walletPublicKey': pendingWalletKey,
          });
          _ref.invalidate(userProfileProvider);
        }
      } catch (e) {
        debugPrint("Error linking pending wallet: $e");
      }
    }
  }

  Future<void> completeProfile({
    required String name,
    required AccountType accountType,
    AccountType? baseType,
    EmployerType? employerType,
    String? businessName,
    String? businessPermit,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user logged in');

    // Detect if signed in via Google and carry over googleEmail
    final providers = user.providerData.map((p) => p.providerId).toList();
    final googleEmail = providers.contains('google.com') ? user.email : null;

    final profile = UserProfile(
      uid: user.uid,
      name: name,
      email: user.email ?? '',
      photoUrl: user.photoURL,
      accountType: accountType,
      employerType: accountType == AccountType.employer
          ? (employerType ?? EmployerType.personal)
          : null,
      businessName: businessName,
      businessPermit: businessPermit,
      googleEmail: googleEmail,
      createdAt: DateTime.now(),
    );

    await _firestore.collection('users').doc(user.uid).set(profile.toMap());
    await SecureStorageHelper.saveHasSeenOnboarding(false);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
    await SecureStorageHelper.deletePassword();
  }

  Future<void> updateProfile(UserProfile profile) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user logged in');

    await _firestore.collection('users').doc(user.uid).update(profile.toMap());
  }
}

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
    ref,
  );
});

final accountTypeProvider = StateProvider<AccountType>(
  (ref) => AccountType.employer,
);
final authViewProvider = StateProvider<String>((ref) => 'login');
final pendingAccountTypeProvider = StateProvider<AccountType?>((ref) => null);
final pendingBaseAccountTypeProvider = StateProvider<AccountType?>(
  (ref) => null,
);

final currentViewModeProvider = Provider<AccountType>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  final accountType = profile?.accountType ?? ref.watch(accountTypeProvider);
  final hybridToggle = ref.watch(hybridToggleProvider);
  return accountType == AccountType.hybrid
      ? hybridToggle
      : (accountType ?? AccountType.nyxian);
});

final hybridToggleProvider = StateProvider<AccountType>(
  (ref) => AccountType.employer,
);
