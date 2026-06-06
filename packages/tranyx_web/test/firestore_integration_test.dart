import 'package:test/test.dart';
import 'package:tranyx_web/services/firebase_service.dart';
import 'package:shared/shared.dart';

void main() {
  group('Firestore Service Integration Tests', () {
    late FirebaseAuthService auth;
    late AuthResult authResult;
    late String testEmail;
    final testPassword = 'Password123!';
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    setUpAll(() async {
      auth = FirebaseAuthService();
      testEmail = 'integration_test_$timestamp@tranyx.com';

      // Register the test user
      print('Registering test user: $testEmail');
      authResult = await auth.register(testEmail, testPassword);
      print('Test user registered with UID: ${authResult.uid}');
    });

    test('Authenticate and get user data from Auth lookup API', () async {
      final userData = await auth.getUserData(authResult.idToken);
      expect(userData['localId'], equals(authResult.uid));
      expect(userData['email'], equals(testEmail));
    });

    test('Save and read UserProfile document via FirestoreService', () async {
      final svc = FirestoreService(authResult.idToken);
      final userPath = 'users/${authResult.uid}';

      final profile = UserProfile(
        uid: authResult.uid,
        name: 'Integration Test User',
        email: testEmail,
        accountType: AccountType.employer,
        tyxBalance: 5000.0,
      );

      // Write User Profile to Firestore
      print('Saving user profile...');
      await svc.createOrUpdate(userPath, profile.toMap());

      // Read User Profile back from Firestore
      print('Retrieving user profile...');
      final retrievedData = await svc.getDocument(userPath);
      expect(retrievedData, isNotNull);
      expect(retrievedData!['name'], equals('Integration Test User'));
      expect((retrievedData['tyxBalance'] as num).toDouble(), equals(5000.0));
      expect(retrievedData['accountType'], equals(AccountType.employer.name));
    });

    test('Write and read Platform Fees document with correct calculations', () async {
      final svc = FirestoreService(authResult.idToken);
      final jobId = 'job_integration_$timestamp';
      final feePath = 'platform_fees/$jobId';

      final price = 2000.0;
      final platformFee = price * 0.03; // Nyxian 3% commission
      final txFee = price * 0.07; // Employer 7% transaction fee
      final convFee = price * 0.03; // Employer 3% convenience fee
      final totalFees = platformFee + txFee + convFee; // 13% total platform income

      // Write platform fee record to Firestore
      print('Writing platform fee record...');
      await svc.createOrUpdate(feePath, {
        'jobId': jobId,
        'amount': totalFees,
        'commissionFee': platformFee,
        'transactionFee': txFee,
        'convenienceFee': convFee,
        'employerFees': txFee + convFee,
        'nyxianFee': platformFee,
        'totalFees': totalFees,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Read Platform Fees record back and verify details
      print('Retrieving platform fee record...');
      final retrievedFee = await svc.getDocument(feePath);
      expect(retrievedFee, isNotNull);
      expect(retrievedFee!['jobId'], equals(jobId));
      expect((retrievedFee['amount'] as num).toDouble(), equals(260.0));
      expect((retrievedFee['commissionFee'] as num).toDouble(), equals(60.0));
      expect((retrievedFee['transactionFee'] as num).toDouble(), equals(140.0));
      expect((retrievedFee['convenienceFee'] as num).toDouble(), equals(60.0));
      expect((retrievedFee['employerFees'] as num).toDouble(), equals(200.0));
      expect((retrievedFee['nyxianFee'] as num).toDouble(), equals(60.0));
      expect((retrievedFee['totalFees'] as num).toDouble(), equals(260.0));

      // Clean up the platform fee document
      print('Cleaning up fee document...');
      await svc.deleteDocument(feePath);
      final deletedFee = await svc.getDocument(feePath);
      expect(deletedFee, null);
    });

    tearDownAll(() async {
      final svc = FirestoreService(authResult.idToken);
      // Clean up the user profile document
      print('Cleaning up user profile document...');
      await svc.deleteDocument('users/${authResult.uid}');
    });
  });
}
