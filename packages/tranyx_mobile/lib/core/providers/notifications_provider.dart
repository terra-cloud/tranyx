import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';

final notificationsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return Stream.value([]);

  final firestore = ref.watch(firestoreProvider);
  return firestore
      .collection('notifications')
      .where('uid', isEqualTo: user.uid)
      .snapshots()
      .map((snapshot) {
        final list = snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
        // Sort by createdAt descending
        list.sort((a, b) => (b['createdAt'] as int? ?? 0).compareTo(a['createdAt'] as int? ?? 0));
        return list;
      });
});

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notifsAsync = ref.watch(notificationsStreamProvider);
  return notifsAsync.maybeWhen(
    data: (list) => list.where((n) => n['isRead'] == false).length,
    orElse: () => 0,
  );
});

class NotificationService {
  final FirebaseFirestore _firestore;

  NotificationService(this._firestore);

  Future<void> markAsRead(String notifId) async {
    try {
      await _firestore.collection('notifications').doc(notifId).update({
        'isRead': true,
      });
    } catch (e) {
      // ignore
    }
  }

  Future<void> markAllAsRead(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('uid', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      // ignore
    }
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref.watch(firestoreProvider));
});
