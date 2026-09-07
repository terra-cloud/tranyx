import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

final appConfigProvider = FutureProvider<String?>((ref) async {
  return Env.geminiApiKey;
});

