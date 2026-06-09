import 'env.g.dart';

class Env {
  /// Retrieves the value of the environment variable for [key].
  /// First checks the generated EnvConfig values, then falls back to String.fromEnvironment.
  static String get(String key, {String defaultValue = ''}) {
    if (EnvConfig.values.containsKey(key)) {
      return EnvConfig.values[key]!;
    }
    return String.fromEnvironment(key, defaultValue: defaultValue);
  }
}
