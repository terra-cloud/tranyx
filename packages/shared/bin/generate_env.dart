import 'dart:io';

void main() {
  final Map<String, String> vars = {};

  // 1. Try to read from .env file
  // We check multiple relative paths to ensure it works regardless of where the command is run from.
  final candidates = [
    '.env',
    '../.env',
    '../../.env',
    '../../../.env',
    'packages/shared/.env',
    '../packages/shared/.env',
  ];

  File? envFile;
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      envFile = file;
      break;
    }
  }

  if (envFile != null) {
    print('Found .env file at: ${envFile.path}');
    final lines = envFile.readAsLinesSync();
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
        vars[key] = cleanValue;
      }
    }
  } else {
    print('No .env file found. Falling back to system environment variables.');
  }

  // 2. Fallback to system environment variables (useful for CI/CD pipelines)
  final keysToLoad = <String>[];

  for (final key in keysToLoad) {
    if (!vars.containsKey(key) || vars[key]!.isEmpty) {
      final envVal = Platform.environment[key];
      if (envVal != null && envVal.isNotEmpty) {
        vars[key] = envVal;
      }
    }
  }

  // 3. Determine the destination path for env.g.dart
  // We find packages/shared/lib/src/env.g.dart relative to the script execution path
  final destCandidates = [
    'lib/src/env.g.dart',
    'packages/shared/lib/src/env.g.dart',
    '../shared/lib/src/env.g.dart',
    '../packages/shared/lib/src/env.g.dart',
    '../../packages/shared/lib/src/env.g.dart',
  ];

  File? destFile;
  for (final path in destCandidates) {
    // We want to write to the parent directory of lib/src if we find it
    final dir = Directory(path.replaceFirst('/env.g.dart', ''));
    if (dir.existsSync()) {
      destFile = File(path);
      break;
    }
  }

  // Fallback to current directory src if not found
  destFile ??= File('lib/src/env.g.dart');

  final buffer = StringBuffer();
  buffer.writeln('// GENERATED FILE - DO NOT EDIT OR COMMIT');
  buffer.writeln('class EnvConfig {');
  buffer.writeln('  static const Map<String, String> values = {');
  vars.forEach((key, value) {
    // Escape single quotes in value
    final escapedVal = value.replaceAll("'", "\\'");
    buffer.writeln("    '$key': '$escapedVal',");
  });
  buffer.writeln('  };');
  buffer.writeln('}');

  destFile.writeAsStringSync(buffer.toString());
  print('Successfully generated ${destFile.path} with ${vars.length} variables.');
}
