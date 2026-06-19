import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';

final appConfigProvider = FutureProvider<String?>((ref) async {
  try {
    final firestore = ref.watch(firestoreProvider);
    final doc = await firestore.collection('config').doc('app_config').get();
    if (doc.exists) {
      return doc.data()?['gemini'] as String?;
    }
    return null;
  } catch (e) {
    return null;
  }
});
