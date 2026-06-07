import 'dart:convert';

class Env {
  static final Map<String, String> _vars = {};

  /// Retrieves the value of the environment variable for [key].
  /// First checks runtime loaded variables, then falls back to String.fromEnvironment.
  static String get(String key, {String defaultValue = ''}) {
    if (_vars.containsKey(key)) {
      return _vars[key]!;
    }
    return String.fromEnvironment(key, defaultValue: defaultValue);
  }

  /// Parses the .env content and populates the runtime environment variables map.
  static void load(String content) {
    final lines = const LineSplitter().convert(content);
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final parts = trimmed.split('=');
      if (parts.length >= 2) {
        final key = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();
        
        var cleanValue = value;
        if ((cleanValue.startsWith("'") && cleanValue.endsWith("'")) ||
            (cleanValue.startsWith('"') && cleanValue.endsWith('"'))) {
          cleanValue = cleanValue.substring(1, cleanValue.length - 1);
        }
        _vars[key] = cleanValue;
      }
    }
  }
}
