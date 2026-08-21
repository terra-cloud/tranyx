import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/widgets/user_badge_widget.dart';
import 'package:tranyx_mobile/core/widgets/interactive_walkthrough_overlay.dart';

void main() {
  group('UserBadgeWidget & Verification Tier Tests (Scenarios 1, 2, 3)', () {
    test('VerificationLevel enum parsing works correctly for all inputs', () {
      expect(VerificationLevel.fromValue(null), VerificationLevel.none);
      expect(VerificationLevel.fromValue(0), VerificationLevel.none);
      expect(VerificationLevel.fromValue('NONE'), VerificationLevel.none);
      expect(VerificationLevel.fromValue('UNVERIFIED'), VerificationLevel.none);
      expect(VerificationLevel.fromValue(false), VerificationLevel.none);

      expect(VerificationLevel.fromValue(1), VerificationLevel.level1Basic);
      expect(VerificationLevel.fromValue('LEVEL_1_BASIC'), VerificationLevel.level1Basic);
      expect(VerificationLevel.fromValue('BASIC'), VerificationLevel.level1Basic);
      expect(VerificationLevel.fromValue(true), VerificationLevel.level1Basic);

      expect(VerificationLevel.fromValue(2), VerificationLevel.level2Pro);
      expect(VerificationLevel.fromValue(3), VerificationLevel.level2Pro);
      expect(VerificationLevel.fromValue('LEVEL_2_PRO'), VerificationLevel.level2Pro);
      expect(VerificationLevel.fromValue('PRO'), VerificationLevel.level2Pro);
      expect(VerificationLevel.fromValue('MERCHANT'), VerificationLevel.level2Pro);
    });

    testWidgets('Unverified user renders SizedBox.shrink with ZERO badge icons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Text('John Doe'),
                UserBadgeWidget(level: VerificationLevel.none),
              ],
            ),
          ),
        ),
      );

      expect(find.text('John Doe'), findsOneWidget);
      expect(find.byType(UserBadgeWidget), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
      expect(find.text('VERIFIED'), findsNothing);
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets('Verified Level 1 user renders distinct Level 1 badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Text('Alice Smith'),
                UserBadgeWidget(
                  level: VerificationLevel.level1Basic,
                  showLabel: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Alice Smith'), findsOneWidget);
      expect(find.byType(UserBadgeWidget), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('VERIFIED'), findsOneWidget);
    });

    testWidgets('Verified Level 2 user renders upgraded Pro Gold badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Text('Bob Merchant'),
                UserBadgeWidget(
                  level: VerificationLevel.level2Pro,
                  showLabel: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Bob Merchant'), findsOneWidget);
      expect(find.byType(UserBadgeWidget), findsOneWidget);
      expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
      expect(find.text('PRO'), findsOneWidget);
    });

    testWidgets('Tapping badge opens informative verification details modal', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: UserBadgeWidget(
                level: VerificationLevel.level2Pro,
                showLabel: true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(UserBadgeWidget));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Verified (Level 2 Pro)'), findsOneWidget);
      expect(find.text('Tier 2 Pro Counterparty'), findsOneWidget);
      expect(find.text('Government ID'), findsOneWidget);
      expect(find.text('Merchant / Business Record'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Government ID'), findsNothing);
    });
  });

  group('Interactive Walkthrough Overlay Tests (Scenarios 1 to 5)', () {
    testWidgets('Walkthrough renders sequential spotlight steps and can advance to completion', (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  InteractiveWalkthroughOverlay.show(
                    context,
                    onComplete: () {
                      completed = true;
                    },
                    recordAsSeen: false,
                  );
                },
                child: const Text('Start Walkthrough'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Walkthrough'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Step 1: Trust & Verification Badges
      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(find.text('Trust & Verification Badges'), findsOneWidget);
      expect(find.text('Level 1: Basic Gov ID Verified'), findsOneWidget);
      expect(find.text('Level 2: Merchant & Pro Verified'), findsOneWidget);
      expect(find.text('Unverified: Zero badges shown'), findsOneWidget);

      // Advance to Step 2: Rentals
      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Step 2 of 4'), findsOneWidget);
      expect(find.text('Rentals & Calendar Availability'), findsOneWidget);

      // Advance to Step 3: Jobs
      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Step 3 of 4'), findsOneWidget);
      expect(find.text('Jobs & Live Execution Tracking'), findsOneWidget);

      // Advance to Step 4: Wallet
      await tester.tap(find.text('Next'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Step 4 of 4'), findsOneWidget);
      expect(find.text('MWA Web3 Wallet & Fiat Ledger'), findsOneWidget);
      expect(find.text('Got It'), findsOneWidget);

      // Complete walkthrough
      await tester.tap(find.text('Got It'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(completed, isTrue);
    });

    testWidgets('Walkthrough skip action dismisses immediately', (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  InteractiveWalkthroughOverlay.show(
                    context,
                    onDismiss: () {
                      dismissed = true;
                    },
                    recordAsSeen: false,
                  );
                },
                child: const Text('Start Walkthrough'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start Walkthrough'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Step 1 of 4'), findsOneWidget);

      // Tap close icon button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(dismissed, isTrue);
    });
  });
}
