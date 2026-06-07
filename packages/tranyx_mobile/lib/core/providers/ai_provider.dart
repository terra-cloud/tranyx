import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/providers/cloudflare_ai_service.dart';

const String cloudflareAccountId = String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID', defaultValue: '');

const String cloudflareApiToken = String.fromEnvironment('CLOUDFLARE_API_TOKEN', defaultValue: '');

final aiServiceProvider = Provider<CloudflareAIService>((ref) {
  return CloudflareAIService(
    accountId: cloudflareAccountId,
    apiToken: cloudflareApiToken,
  );
});
