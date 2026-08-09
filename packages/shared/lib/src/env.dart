import 'env.g.dart';

class Env {
  /// Known compile-time environment variables.
  static const String _xenditSecretKey = String.fromEnvironment('XENDIT_SECRET_KEY');
  static const String _imgbbApiKey = String.fromEnvironment('IMGBB_API_KEY', defaultValue: '50952d72f276ff20aa3362f346b134ab');
  static const String _cloudflareAccountId = String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID');
  static const String _cloudflareApiToken = String.fromEnvironment('CLOUDFLARE_API_TOKEN');
  static const String _env = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const String _flavor = String.fromEnvironment('FLAVOR');

  /// Retrieves the value of the environment variable for [key].
  /// First checks compile-time environment variables, then generated EnvConfig values,
  /// and finally falls back to [defaultValue].
  static String get(String key, {String defaultValue = ''}) {
    final fromConst = switch (key) {
      'XENDIT_SECRET_KEY' => _xenditSecretKey,
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

  static String get xenditSecretKey => get('XENDIT_SECRET_KEY');
  static String get imgbbApiKey => get('IMGBB_API_KEY', defaultValue: '50952d72f276ff20aa3362f346b134ab');
  static String get cloudflareAccountId => get('CLOUDFLARE_ACCOUNT_ID');
  static String get cloudflareApiToken => get('CLOUDFLARE_API_TOKEN');
  static String get env => get('ENV', defaultValue: 'dev');
  static String get flavor => get('FLAVOR');
}
