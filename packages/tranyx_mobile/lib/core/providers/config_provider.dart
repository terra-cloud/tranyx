import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appConfigProvider = FutureProvider<String?>((ref) async {
  try {
    final doc = await FirebaseFirestore.instance.collection('config').doc('app_config').get();
    if (doc.exists) {
      return doc.data()?['gemini'] as String?;
    }
    return null;
  } catch (e) {
    return null;
  }
});
