import 'package:test/test.dart';
import '../lib/services/firebase_service.dart';
import 'package:shared/shared.dart';

void main() {
  group('E2E Job Lifecycle and Wallet Fees Integration Test', () {
    late FirebaseAuthService auth;
    
    // Test users info
    late AuthResult empAuth;
    late AuthResult nyxAuth;
    late String empEmail;
    late String nyxEmail;
    final testPassword = 'Password123!';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Document paths
    late String jobId;
    late String jobPath;
    late String appPath;
    late String escrowPath;
    late String feePath;
    late String empTxPath;
    late String nyxTxPath;

    setUpAll(() async {
      auth = FirebaseAuthService();
      empEmail = 'lifecycle_emp_$timestamp@tranyx.com';
      nyxEmail = 'lifecycle_nyx_$timestamp@tranyx.com';
      jobId = 'lifecycle_job_$timestamp';
      jobPath = 'jobs/$jobId';
      appPath = 'jobs/$jobId/applications/nyx_applicant';
      escrowPath = 'escrow/$jobId';
      feePath = 'platform_fees/$jobId';
      empTxPath = 'transactions/fees_emp_$jobId';
      nyxTxPath = 'transactions/payout_nyx_$jobId';

      // 1. Register Employer & Nyxian
      print('Registering Employer: $empEmail');
      empAuth = await auth.register(empEmail, testPassword);
      print('Registering Nyxian: $nyxEmail');
      nyxAuth = await auth.register(nyxEmail, testPassword);
    });

    test('Full E2E Job Transaction Flow with Fee Deductions', () async {
      final empSvc = FirestoreService(empAuth.idToken);
      final nyxSvc = FirestoreService(nyxAuth.idToken);

      // 2. Setup user profiles with initial balances
      print('Setting up user profiles...');
      final empProfile = UserProfile(
        uid: empAuth.uid,
        name: 'E2E Employer',
        email: empEmail,
        accountType: AccountType.employer,
        tyxBalance: 5000.0, // Starts with 5000 PHP
      );
      final nyxProfile = UserProfile(
        uid: nyxAuth.uid,
        name: 'E2E Nyxian',
        email: nyxEmail,
        accountType: AccountType.nyxian,
        tyxBalance: 1000.0, // Starts with 1000 PHP
      );

      await empSvc.createOrUpdate('users/${empAuth.uid}', empProfile.toMap());
      await nyxSvc.createOrUpdate('users/${nyxAuth.uid}', nyxProfile.toMap());

      // 3. Employer posts an Open Job with pricing 2000 PHP
      print('Employer posting job...');
      final job = Job(
        id: jobId,
        creatorId: empAuth.uid,
        creatorName: 'E2E Employer',
        creatorType: AccountType.employer,
        title: 'E2E Test Painting Gig',
        description: 'Complete painting of main lobby',
        category: JobCategory.painter,
        categoryGroup: JobCategoryGroup.homeRepair,
        employmentType: 'One-time Gig',
        dateRequirement: 'Flexible',
        timePreference: 'Morning',
        pricingType: 'Package (Fixed)',
        pricingValue: 2000.0, // 2000 PHP base price
        locationType: 'On-site',
        createdAt: DateTime.now(),
        status: 'Open',
      );
      await empSvc.createOrUpdate(jobPath, job.toMap());

      // 4. Nyxian applies to the job
      print('Nyxian applying for job...');
      final app = JobApplication(
        id: 'nyx_applicant',
        jobId: jobId,
        applicantUid: nyxAuth.uid,
        applicantName: 'E2E Nyxian',
        coverNote: 'I have 5 years painting experience.',
        proposalRate: 2000.0,
        isCounterOffer: false,
        createdAt: DateTime.now(),
      );
      await nyxSvc.createOrUpdate(appPath, app.toMap());

      // 5. Employer accepts the Nyxian and puts base funds into escrow
      print('Employer accepting applicant and funding escrow...');
      final basePrice = 2000.0;
      final verifyCode = '123456';

      // Update job to In Progress
      await empSvc.createOrUpdate(jobPath, {
        ...job.toMap(),
        'status': 'In Progress',
        'acceptedApplicantId': nyxAuth.uid,
        'acceptedApplicantName': 'E2E Nyxian',
        'completionCode': verifyCode,
      });

      // Deduct base price from Employer's wallet for escrow
      final currentEmpDoc = await empSvc.getDocument('users/${empAuth.uid}');
      final empBalAfterEscrow = (currentEmpDoc!['tyxBalance'] as num).toDouble() - basePrice;
      await empSvc.createOrUpdate('users/${empAuth.uid}', {
        ...currentEmpDoc,
        'tyxBalance': empBalAfterEscrow,
      });

      // Write escrow record
      await empSvc.createOrUpdate(escrowPath, {
        'jobId': jobId,
        'amount': basePrice,
        'employerId': empAuth.uid,
        'nyxianId': nyxAuth.uid,
        'status': 'held',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      // 6. Verify Escrow status
      final escrowDoc = await empSvc.getDocument(escrowPath);
      expect(escrowDoc, isNotNull);
      expect((escrowDoc!['amount'] as num).toDouble(), equals(2000.0));

      // 7. Nyxian completes job by providing correct code (simulate handleCompleteJob)
      print('Simulating job completion and payouts...');
      final jobDoc = await nyxSvc.getDocument(jobPath);
      expect(jobDoc!['completionCode'].toString(), equals(verifyCode));

      // Calculate Fees:
      final platformFee = basePrice * 0.03; // Nyxian 3% commission
      final nyxianPayout = basePrice - platformFee; // Net payout to worker

      final txFee = basePrice * 0.07; // Employer 7% transaction fee
      final convFee = basePrice * 0.03; // Employer 3% convenience fee
      final totalEmployerFees = txFee + convFee; // Employer total fees (10%)

      final totalCompanyIncome = platformFee + txFee + convFee; // 13% platform income

      // Release Escrow
      await nyxSvc.deleteDocument(escrowPath);

      // Nyxian wallet update (Payout added)
      final currentNyxDoc = await nyxSvc.getDocument('users/${nyxAuth.uid}');
      final nyxBalAfterPayout = (currentNyxDoc!['tyxBalance'] as num).toDouble() + nyxianPayout;
      await nyxSvc.createOrUpdate('users/${nyxAuth.uid}', {
        ...currentNyxDoc,
        'tyxBalance': nyxBalAfterPayout,
        'jobsDone': (currentNyxDoc['jobsDone'] as int) + 1,
        'totalEarned': (currentNyxDoc['totalEarned'] as num).toDouble() + nyxianPayout,
      });

      // Nyxian transaction log
      await nyxSvc.createOrUpdate(nyxTxPath, {
        'uid': nyxAuth.uid,
        'title': 'Gig Payout Released',
        'desc': 'Payout for completing job $jobId (3% commission deducted)',
        'amount': nyxianPayout,
        'status': 'Successful',
        'method': 'Tranyx Wallet',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'type': 'payout',
      });

      // Employer wallet update (Fees deducted)
      final currentEmpDoc2 = await empSvc.getDocument('users/${empAuth.uid}');
      final empBalAfterFees = (currentEmpDoc2!['tyxBalance'] as num).toDouble() - totalEmployerFees;
      await empSvc.createOrUpdate('users/${empAuth.uid}', {
        ...currentEmpDoc2,
        'tyxBalance': empBalAfterFees,
      });

      // Employer transaction log
      await empSvc.createOrUpdate(empTxPath, {
        'uid': empAuth.uid,
        'title': 'Job Completion Fees (10%)',
        'desc': '7% Transaction Fee & 3% Convenience Fee for job $jobId',
        'amount': totalEmployerFees,
        'status': 'Successful',
        'method': 'Tranyx Wallet',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'type': 'fee_deduction',
      });

      // Platform fees log
      await nyxSvc.createOrUpdate(feePath, {
        'jobId': jobId,
        'amount': totalCompanyIncome,
        'commissionFee': platformFee,
        'transactionFee': txFee,
        'convenienceFee': convFee,
        'employerFees': totalEmployerFees,
        'nyxianFee': platformFee,
        'totalFees': totalCompanyIncome,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Mark Job Completed
      await nyxSvc.createOrUpdate(jobPath, {
        ...jobDoc,
        'status': 'Completed',
      });

      // 8. VERIFY FINAL DATABASE STATE
      print('Verifying final database balances and states...');
      
      // Employer Final Balance: 5000 (start) - 2000 (escrow) - 200 (fees) = 2800 PHP
      final finalEmpDoc = await empSvc.getDocument('users/${empAuth.uid}');
      expect((finalEmpDoc!['tyxBalance'] as num).toDouble(), equals(2800.0));

      // Nyxian Final Balance: 1000 (start) + 1940 (payout) = 2940 PHP
      final finalNyxDoc = await nyxSvc.getDocument('users/${nyxAuth.uid}');
      expect((finalNyxDoc!['tyxBalance'] as num).toDouble(), equals(2940.0));

      // Platform fees document verification: total fees 260 PHP
      final finalFeeDoc = await empSvc.getDocument(feePath);
      expect(finalFeeDoc, isNotNull);
      expect((finalFeeDoc!['totalFees'] as num).toDouble(), equals(260.0));
      expect((finalFeeDoc['commissionFee'] as num).toDouble(), equals(60.0));

      // Transaction log verifications
      final finalEmpTx = await empSvc.getDocument(empTxPath);
      expect(finalEmpTx, isNotNull);
      expect((finalEmpTx!['amount'] as num).toDouble(), equals(200.0));

      final finalNyxTx = await nyxSvc.getDocument(nyxTxPath);
      expect(finalNyxTx, isNotNull);
      expect((finalNyxTx!['amount'] as num).toDouble(), equals(1940.0));
      
      print('E2E validation checks passed successfully!');
    });

    tearDownAll(() async {
      print('Starting E2E test documents cleanup...');
      final empSvc = FirestoreService(empAuth.idToken);
      final nyxSvc = FirestoreService(nyxAuth.idToken);

      Future<void> safeDelete(FirestoreService svc, String path) async {
        try {
          await svc.deleteDocument(path);
        } catch (e) {
          print('Safe delete skipped for $path: $e');
        }
      }

      await safeDelete(empSvc, 'users/${empAuth.uid}');
      await safeDelete(nyxSvc, 'users/${nyxAuth.uid}');
      await safeDelete(empSvc, jobPath);
      await safeDelete(empSvc, appPath);
      await safeDelete(empSvc, escrowPath);
      await safeDelete(empSvc, feePath);
      await safeDelete(empSvc, empTxPath);
      await safeDelete(empSvc, nyxTxPath);
      print('Cleanup complete.');
    });
  });
}
