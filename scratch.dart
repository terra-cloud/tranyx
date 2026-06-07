import 'dart:io';

void main() async {
  final collections = [
    'jobs',
    'rentals',
    'properties',
    'transactions',
    'notifications',
    'escrow_holdbacks',
    'rental_requests',
    'rental_extensions',
    'rental_history',
    'property_requests',
    'kyc_submissions',
    'escrow',
    'rental_escrows',
    'rental_extension_escrows',
    'property_escrows',
    'walletLinks',
    'chats',
    'platform_fees',
  ];

  // The default active project
  const project = 'tranyx-dev';
  
  print('=== TRANYX FIRESTORE CLEANUP SCRIPT ===');
  print('Target Project: $project');
  print('Collections to delete: ${collections.join(', ')}');
  print('=======================================');
  print('WARNING: This will recursively delete all data in the listed collections.');
  stdout.write('Do you want to proceed? (y/N): ');
  
  final input = stdin.readLineSync()?.trim().toLowerCase();
  if (input != 'y' && input != 'yes') {
    print('Cleanup aborted.');
    return;
  }

  print('\nStarting deletion of ${collections.length} collections...');
  
  for (final col in collections) {
    stdout.write('Deleting collection "$col" ... ');
    final result = await Process.run('npx', [
      'firebase-tools',
      'firestore:delete',
      '--project',
      project,
      '--recursive',
      col,
      '-f'
    ]);
    
    if (result.exitCode == 0) {
      print('✔ Done');
    } else {
      print('✘ Failed');
      print('Error detail: ${result.stderr.toString().trim()}');
    }
  }
  
  print('\n=== Cleanup finished! ===');
}
