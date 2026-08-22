import 'env.g.dart';

class Env {
  /// Known compile-time environment variables.
  static const String _imgbbApiKey = String.fromEnvironment('IMGBB_API_KEY');
  static const String _cloudflareAccountId = String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID');
  static const String _cloudflareApiToken = String.fromEnvironment('CLOUDFLARE_API_TOKEN');
  static const String _geminiApiKey = String.fromEnvironment('GEMINI_AI_API_KEY');
  static const String _solanaPrivateKey = String.fromEnvironment('SOLANA_PRIVATE_KEY');
  static const String _solanaPublicKey = String.fromEnvironment('SOLANA_PUBLIC_KEY');
  static const String _treasuryPrivateKey = String.fromEnvironment('TREASURY_PRIVATE_KEY');
  static const String _treasuryPublicKey = String.fromEnvironment('TREASURY_PUBLIC_KEY');
  static const String _env = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const String _flavor = String.fromEnvironment('FLAVOR');

  /// Retrieves the value of the environment variable for [key].
  /// First checks compile-time environment variables, then generated EnvConfig values,
  /// and finally falls back to [defaultValue].
  static String get(String key, {String defaultValue = ''}) {
    final fromConst = switch (key) {
      'GEMINI_AI_API_KEY' => _geminiApiKey,
      'SOLANA_PRIVATE_KEY' => _solanaPrivateKey,
      'SOLANA_PUBLIC_KEY' => _solanaPublicKey,
      'TREASURY_PRIVATE_KEY' => _treasuryPrivateKey,
      'TREASURY_PUBLIC_KEY' => _treasuryPublicKey,
      'IMGBB_API_KEY' => _imgbbApiKey,
      'CLOUDFLARE_ACCOUNT_ID' => _cloudflareAccountId,
      'CLOUDFLARE_API_TOKEN' => _cloudflareApiToken,
      'ENV' => _env,
      'FLAVOR' => _flavor,
      _ => '',
    };

    if (fromConst.isNotEmpty) {
      return fromConst;
    }

    if (EnvConfig.values.containsKey(key) && EnvConfig.values[key]!.isNotEmpty) {
      return EnvConfig.values[key]!;
    }

    return defaultValue;
  }

  static String get geminiApiKey => get('GEMINI_AI_API_KEY');
  static String get solanaPrivateKey =>
      get('SOLANA_PRIVATE_KEY', defaultValue: get('TREASURY_PRIVATE_KEY'));
  static String get solanaPublicKey =>
      get('SOLANA_PUBLIC_KEY', defaultValue: get('TREASURY_PUBLIC_KEY'));
  static String get treasuryPrivateKey => solanaPrivateKey;
  static String get treasuryPublicKey => solanaPublicKey;
  static String get imgbbApiKey => get('IMGBB_API_KEY');
  static String get cloudflareAccountId => get('CLOUDFLARE_ACCOUNT_ID');
  static String get cloudflareApiToken => get('CLOUDFLARE_API_TOKEN');
  static String get env => get('ENV', defaultValue: 'dev');
  static String get flavor => get('FLAVOR');
}
