import 'dart:io';

void main() {
  final rulesDir = Directory('firestore_rules');
  if (!rulesDir.existsSync()) {
    stderr.writeln('Error: Directory "firestore_rules" not found.');
    exit(1);
  }

  final files = rulesDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.rules'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    stderr.writeln('Error: No .rules files found in "firestore_rules".');
    exit(1);
  }

  final buffer = StringBuffer();
  buffer.writeln('// ============================================================================');
  buffer.writeln('// TRANYX PRODUCTION CLOUD FIRESTORE RULES');
  buffer.writeln('// AUTO-GENERATED - DO NOT DIRECTLY EDIT THIS FILE!');
  buffer.writeln('// To make changes, edit files in "firestore_rules/" and compile via:');
  buffer.writeln('//   dart run tool/build_rules.dart');
  buffer.writeln('// ============================================================================');
  buffer.writeln();

  for (final file in files) {
    final filename = file.uri.pathSegments.last;
    buffer.writeln('// >>> SOURCE: firestore_rules/$filename');
    buffer.write(file.readAsStringSync().trimRight());
    buffer.writeln('\n');
  }

  final compiledRules = buffer.toString();

  // Balance checks
  final openBraces = RegExp(r'\{').allMatches(compiledRules).length;
  final closeBraces = RegExp(r'\}').allMatches(compiledRules).length;
  if (openBraces != closeBraces) {
    stderr.writeln('Warning: Unbalanced braces detected ($openBraces open, $closeBraces close).');
  }

  final outputFile = File('firestore.rules');
  outputFile.writeAsStringSync(compiledRules);

  print('Successfully compiled ${files.length} rule files into firestore.rules (${compiledRules.length} bytes)');
  for (final file in files) {
    print('  - ${file.uri.pathSegments.last}');
  }

  // Cross-project synchronization to tranyx_admin_portal
  final adminTargetDirs = [
    Directory('../tranyx_admin_portal'),
    Directory('/Users/zeuscajurao/Desktop/tranyx_admin_portal'),
  ];
  for (final adminDir in adminTargetDirs) {
    if (adminDir.existsSync()) {
      final adminRulesFile = File('${adminDir.path}/firestore.rules');
      adminRulesFile.writeAsStringSync(compiledRules);
      print('[SYNC SUCCESS] Mirrored firestore.rules to ${adminRulesFile.path} (${compiledRules.length} bytes)');
      break;
    }
  }
}
