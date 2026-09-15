import 'dart:io';

const Map<String, String> projectTargets = {
  'dev': 'tranyx-dev',
  'uat': 'tranyx-uat',
  'prod': 'tranyx-app',
};

void main(List<String> args) async {
  final targetEnv = args.isNotEmpty ? args.first.toLowerCase() : 'dev';
  final projectId = projectTargets[targetEnv];

  if (projectId == null) {
    stderr.writeln('Invalid target environment: "$targetEnv".');
    stderr.writeln('Available targets:');
    projectTargets.forEach((k, v) => stderr.writeln('  $k -> $v'));
    exit(1);
  }

  print('=== STEP 1: Assembling Firestore Rules from firestore_rules/ ===');
  final buildProcess = await Process.run('dart', ['run', 'tool/build_rules.dart']);
  stdout.write(buildProcess.stdout);
  if (buildProcess.exitCode != 0) {
    stderr.write(buildProcess.stderr);
    exit(buildProcess.exitCode);
  }

  print('\n=== STEP 2: Deploying to Firebase project "$projectId" ($targetEnv) ===');
  final deployProcess = await Process.start(
    'firebase',
    ['deploy', '--only', 'firestore:rules', '--project', projectId],
    mode: ProcessStartMode.inheritStdio,
  );

  final exitCode = await deployProcess.exitCode;
  if (exitCode == 0) {
    print('\n[DEPLOY SUCCESS] Rules successfully compiled and released to "$projectId".');
  } else {
    stderr.writeln('\n[DEPLOY FAILED] Firebase deployment exited with code $exitCode.');
    exit(exitCode);
  }
}
