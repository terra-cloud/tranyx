import 'package:cloud_firestore/cloud_firestore.dart';

enum MwaLinkOutcome { linked, alreadyLinkedToAnotherAccount }

/// `connectedWalletType` stored on the user doc for MWA-linked wallets.
const String kMwaWalletType = 'mwa';

/// Links an MWA-authorized [publicKey] to [uid] in ONE transaction.
///
/// - the `walletLinks/{key}` index doc (uid + linkedAt only, no credentials,
///   KAN-124) is created only if it does not exist yet; a doc owned by another
///   uid refuses the link, and an existing doc already owned by [uid] is left
///   as is (the rules allow create, not a blind re-set);
/// - the user's previous `walletLinks` doc is removed (only if it is theirs),
///   so replacing a wallet never leaves a dangling claim on the old one;
/// - the profile key is updated in the same transaction.
Future<MwaLinkOutcome> linkMwaWallet({
  required FirebaseFirestore firestore,
  required String uid,
  required String publicKey,
}) {
  return firestore.runTransaction<MwaLinkOutcome>((tx) async {
    final userRef = firestore.collection('users').doc(uid);
    final newRef = firestore.collection('walletLinks').doc(publicKey);

    // All reads first.
    final userSnap = await tx.get(userRef);
    final newSnap = await tx.get(newRef);
    final previous = (userSnap.data()?['walletPublicKey'] as String?) ?? '';
    final DocumentSnapshot<Map<String, dynamic>>? previousSnap =
        previous.isNotEmpty && previous != publicKey
        ? await tx.get(firestore.collection('walletLinks').doc(previous))
        : null;

    if (newSnap.exists && newSnap.data()?['uid'] != uid) {
      return MwaLinkOutcome.alreadyLinkedToAnotherAccount;
    }

    if (previousSnap != null &&
        previousSnap.exists &&
        previousSnap.data()?['uid'] == uid) {
      tx.delete(previousSnap.reference);
    }
    if (!newSnap.exists) {
      tx.set(newRef, {
        'uid': uid,
        'linkedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
    tx.update(userRef, {
      'walletPublicKey': publicKey,
      'connectedWalletType': kMwaWalletType,
    });
    return MwaLinkOutcome.linked;
  });
}

/// Unlinks the user's wallet: removes their own `walletLinks` doc and clears
/// the profile fields in one transaction.
Future<void> unlinkWallet({
  required FirebaseFirestore firestore,
  required String uid,
}) {
  return firestore.runTransaction<void>((tx) async {
    final userRef = firestore.collection('users').doc(uid);
    final userSnap = await tx.get(userRef);
    final key = (userSnap.data()?['walletPublicKey'] as String?) ?? '';
    DocumentSnapshot<Map<String, dynamic>>? linkSnap;
    if (key.isNotEmpty) {
      linkSnap = await tx.get(firestore.collection('walletLinks').doc(key));
    }
    if (linkSnap != null && linkSnap.exists && linkSnap.data()?['uid'] == uid) {
      tx.delete(linkSnap.reference);
    }
    tx.update(userRef, {'walletPublicKey': null, 'connectedWalletType': null});
  });
}
