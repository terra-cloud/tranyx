import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared/shared.dart';
export 'package:shared/shared.dart' show AccountType, EmployerType, UserProfile;
import 'package:tranyx_mobile/flavors.dart';

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

final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final user = ref.watch(userProvider);
  if (user == null) return null;

  final doc = await ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(user.uid)
      .get();
  if (!doc.exists) return null;

  return UserProfile.fromMap(user.uid, doc.data()!);
});

class AuthController {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  AuthController(this._auth, this._firestore);

  Future<void> signInWithEmailAndPassword(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
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

    final user = userCredential.user;
    if (user != null) {
      await user.updateDisplayName(displayName);

      final profile = UserProfile(
        uid: user.uid,
        name: displayName,
        email: email,
        accountType: accountType,
        employerType: accountType == AccountType.employer ? (employerType ?? EmployerType.personal) : null,
        businessName: businessName,
        businessPermit: businessPermit,
        createdAt: DateTime.now(),
      );

      await _firestore.collection('users').doc(user.uid).set(profile.toMap());
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
    if (user != null && pendingType != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        // Only create profile automatically if it's Nyxian and we have a name
        if (pendingType == AccountType.nyxian &&
            user.displayName != null &&
            user.displayName!.isNotEmpty) {
          final profile = UserProfile(
            uid: user.uid,
            name: user.displayName!,
            email: user.email ?? '',
            photoUrl: user.photoURL,
            accountType: pendingType,
            createdAt: DateTime.now(),
          );
          await _firestore
              .collection('users')
              .doc(user.uid)
              .set(profile.toMap());
        }
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

    final profile = UserProfile(
      uid: user.uid,
      name: name,
      email: user.email ?? '',
      photoUrl: user.photoURL,
      accountType: accountType,
      employerType: accountType == AccountType.employer ? (employerType ?? EmployerType.personal) : null,
      businessName: businessName,
      businessPermit: businessPermit,
      createdAt: DateTime.now(),
    );

    await _firestore.collection('users').doc(user.uid).set(profile.toMap());
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
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
