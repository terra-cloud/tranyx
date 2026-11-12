import 'env.g.dart';

class Env {
  // KAN-146: there is intentionally NO private/treasury secret key here. Withdrawals are signed by
  // the `requestWithdrawal` Cloud Function with a key held only in Secret Manager.

  /// Known compile-time environment variables.
  /// IMGBB and Gemini are read only by the mobile getters below. They are not in [get],
  /// because the web app calls [get] for public Solana values and that switch is compiled
  /// into the public bundle. Web image upload and web AI go through Cloud Functions.
  static const String _imgbbApiKey = String.fromEnvironment('IMGBB_API_KEY');
  static const String _basemapsApiKey = String.fromEnvironment('BASEMAPS_API_KEY');
  static const String _geminiApiKey = String.fromEnvironment('GEMINI_AI_API_KEY');
  static const String _solanaPublicKey = String.fromEnvironment('SOLANA_PUBLIC_KEY');
  static const String _solanaRpcUrl = String.fromEnvironment('SOLANA_RPC_URL');
  static const String _treasuryPublicKey = String.fromEnvironment('TREASURY_PUBLIC_KEY');
  static const String _env = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const String _flavor = String.fromEnvironment('FLAVOR');

  /// Retrieves the value of the environment variable for [key].
  /// First checks compile-time environment variables, then generated EnvConfig values,
  /// and finally falls back to [defaultValue].
  static String get(String key, {String defaultValue = ''}) {
    final fromConst = switch (key) {
      'SOLANA_PUBLIC_KEY' => _solanaPublicKey,
      'SOLANA_RPC_URL' => _solanaRpcUrl,
      'TREASURY_PUBLIC_KEY' => _treasuryPublicKey,
      'BASEMAPS_API_KEY' => _basemapsApiKey,
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

  static String get geminiApiKey => _geminiApiKey;
  static String get solanaPublicKey =>
      get('SOLANA_PUBLIC_KEY', defaultValue: get('TREASURY_PUBLIC_KEY'));
  static String get solanaRpcUrl => get('SOLANA_RPC_URL');
  static String get treasuryPublicKey => solanaPublicKey;
  static String get imgbbApiKey => _imgbbApiKey;
  static String get basemapsApiKey => get('BASEMAPS_API_KEY');
  static String get cloudflareAccountId => '';
  static String get cloudflareApiToken => '';
  static String get env => get('ENV', defaultValue: 'dev');
  static String get flavor => get('FLAVOR');
}
