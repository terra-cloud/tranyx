import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tranyx_mobile/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Solana MWA Compliance & Launch Resilience Integration Tests', () {
    testWidgets('Verify app boots without crashing when no wallet is installed', (tester) async {
      // 1. Pump the App widget inside a ProviderScope
      await tester.pumpWidget(
        const ProviderScope(
          child: App(),
        ),
      );

      // 2. Allow initial frames to render
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 3. Assert app rendered the main screen or splash screen cleanly without crashing
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Verify PhantomService handles wallet store fallback gracefully', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final phantomService = container.read(phantomServiceProvider);

      // Verify store URLs resolve correctly for Android
      final phantomStoreUrl = phantomService.storeUrlFor('phantom');
      expect(phantomStoreUrl, contains('phantom.app'));

      final solflareStoreUrl = phantomService.storeUrlFor('solflare');
      expect(solflareStoreUrl, contains('solflare'));
    });
  });
}
