import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tranyx_mobile/core/services/mwa_service.dart';

enum MwaLinkOutcome { linked, alreadyLinkedToAnotherAccount }

/// `connectedWalletType` stored on the user doc for MWA-linked wallets.
const String kMwaWalletType = 'mwa';

/// Links an MWA-authorized [publicKey] to [uid], using the same shape as the
/// Trust Wallet link: a `walletLinks/{key}` index doc (uid + linkedAt only, no
/// credentials, KAN-124) and the profile key, written in one batch.
Future<MwaLinkOutcome> linkMwaWallet({
  required FirebaseFirestore firestore,
  required String uid,
  required String publicKey,
}) async {
  final existing = await firestore.collection('walletLinks').doc(publicKey).get();
  if (walletLinkedToAnotherAccount(
    existingOwnerUid: existing.data()?['uid'] as String?,
    uid: uid,
  )) {
    return MwaLinkOutcome.alreadyLinkedToAnotherAccount;
  }
  await (firestore.batch()
        ..set(firestore.collection('walletLinks').doc(publicKey), {
          'uid': uid,
          'linkedAt': DateTime.now().millisecondsSinceEpoch,
        })
        ..update(firestore.collection('users').doc(uid), {
          'walletPublicKey': publicKey,
          'connectedWalletType': kMwaWalletType,
        }))
      .commit();
  return MwaLinkOutcome.linked;
}
