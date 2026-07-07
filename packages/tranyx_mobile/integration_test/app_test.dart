import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/app.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'package:tranyx_mobile/flavors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tranyx_mobile/core/providers/fcm_provider.dart';
import '../test/helpers/fake_firestore.dart';

class MockFirebaseUser implements User {
  @override
  String get uid => 'e2e_user';

  @override
  String? get displayName => 'E2E Tester';

  @override
  String? get email => 'e2e@tranyx.com';

  @override
  bool get emailVerified => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockTransitRepository extends TransitRepository {
  final FirebaseFirestore firestoreInstance;
  MockTransitRepository(this.firestoreInstance) : super(firestoreInstance);

  @override
  Future<Map<String, dynamic>> createXenditInvoice({
    required String uid,
    required double amount,
    required String userName,
  }) async {
    return {
      'id': 'inv_mock_123456',
      'invoice_url':
          'https://checkout-staging.xendit.co/v2/invoices/inv_mock_123456',
    };
  }

  @override
  Future<bool> verifyXenditPayment({
    required String uid,
    required String invoiceId,
    required double amount,
  }) async {
    // Simulate successful backend verification
    final user = await getUser(uid);
    if (user != null) {
      final newBal = user.tyxBalance + amount;
      await updateTyxBalance(uid, newBal);

      // Save transaction
      await firestoreInstance
          .collection('transactions')
          .doc('deposit_$invoiceId')
          .set({
            'uid': uid,
            'type': 'deposit',
            'amount': amount,
            'title': 'Wallet Top-Up',
            'desc': 'Fiat deposit via Xendit',
            'method': 'Xendit',
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });
      return true;
    }
    return false;
  }
}

class MockFirebaseMessagingService extends Fake implements FirebaseMessagingService {
  @override
  Future<void> initialize(BuildContext context) async {
    // No-op
  }

  @override
  void dispose() {
    // No-op
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  F.appFlavor = Flavor.dev;

  group('Mobile E2E Integration Tests', () {
    testWidgets('Verify Wallet Balance, Xendit Checkout & Verify Payment Flow', (
      WidgetTester tester,
    ) async {
      final fakeFirestore = FakeFirebaseFirestore();

      // Seed initial data
      fakeFirestore.db['users/e2e_user'] = {
        'uid': 'e2e_user',
        'name': 'E2E Tester',
        'email': 'e2e@tranyx.com',
        'accountType': 'employer',
        'tyxBalance': 500.0,
        'walletPublicKey': '4zMMC4mCK23ccaJ2rbzn36gkJr2cT6w9P5BmgFniS1234',
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firestoreProvider.overrideWithValue(fakeFirestore),
            userProvider.overrideWithValue(MockFirebaseUser()),
            authStateProvider.overrideWithValue(true),
            fcmProvider.overrideWithValue(MockFirebaseMessagingService()),
            transitRepositoryProvider.overrideWith(
              (ref) => MockTransitRepository(fakeFirestore),
            ),
          ],
          child: const App(),
        ),
      );

      // 1. Initial boot and settle
      await tester.pumpAndSettle();
      expect(find.byType(App), findsOneWidget);

      // 2. Navigate to Profile
      final profileTab = find.byIcon(Icons.person);
      expect(profileTab, findsOneWidget);
      await tester.tap(profileTab);
      await tester.pumpAndSettle();

      // 3. Open Payment Methods
      final paymentMethodsCard = find.text('Payment Methods');
      expect(paymentMethodsCard, findsOneWidget);
      await tester.tap(paymentMethodsCard);
      await tester.pumpAndSettle();

      // 4. Verify initial wallet balance is 500.00
      expect(find.text('500.00'), findsOneWidget);

      // 5. Open Deposit Sheet
      final depositButton = find.widgetWithText(ElevatedButton, 'Deposit');
      expect(depositButton, findsOneWidget);
      await tester.tap(depositButton);
      await tester.pumpAndSettle();

      // 6. Fill amount
      final amountField = find.byType(TextField);
      expect(amountField, findsOneWidget);
      await tester.enterText(amountField, '200');
      await tester.pumpAndSettle();

      // 7. Confirm Xendit Payment
      final confirmButton = find.text('Confirm Payment (Xendit)');
      expect(confirmButton, findsOneWidget);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      // 8. Verify the Pending Deposit card is now displayed in the Payment Pane
      expect(find.text('Pending Deposit'), findsOneWidget);
      expect(find.text('₱ 200.00'), findsOneWidget);
      expect(find.text('inv_mock_123...'), findsOneWidget);

      // 9. Tap Verify to finish checkout flow
      final verifyButton = find.text('Verify');
      expect(verifyButton, findsOneWidget);
      await tester.tap(verifyButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // 10. Verify balance is updated to 700.00 and Pending Deposit card is cleared
      expect(find.text('700.00'), findsOneWidget);
      expect(find.text('Pending Deposit'), findsNothing);
    });
  });
}
