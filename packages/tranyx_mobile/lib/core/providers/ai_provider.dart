import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/providers/cloudflare_ai_service.dart';

import 'package:shared/shared.dart';

final aiServiceProvider = Provider<CloudflareAIService>((ref) {
  return CloudflareAIService(
    accountId: Env.get('CLOUDFLARE_ACCOUNT_ID'),
    apiToken: Env.get('CLOUDFLARE_API_TOKEN'),
  );
});
