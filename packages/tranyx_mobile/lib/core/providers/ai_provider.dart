import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/services/nyx_ai_assistant_service.dart';

final aiServiceProvider = Provider<NyxAIAssistantService>((ref) {
  return NyxAIAssistantService();
});
