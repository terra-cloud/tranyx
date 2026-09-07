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
    testWidgets('Verify Wallet Balance & Payment Methods Flow', (
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

      // 6. Verify Solana powered sheet
      expect(find.text('POWERED BY SOLANA SECURE'), findsOneWidget);
    });
  });
}
