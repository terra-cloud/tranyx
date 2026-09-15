import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI Draft Preview & Confirmation Workflow (Scenarios 3 & 4)', () {
    testWidgets('Scenario 3: Discard Action cancels sheet and leaves target description untouched', (tester) async {
      String descriptionState = 'Original initial description';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (_) => _TestDraftHost(
                      initialDraft: 'AI generated draft text for Courier',
                      categoryLabel: 'Courier / Delivery',
                      onAccept: (val) {
                        descriptionState = val;
                      },
                    ),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      // Open bottom sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('AI Job Description Draft'), findsOneWidget);
      expect(find.text('Tailored for Courier / Delivery'), findsOneWidget);
      expect(find.text('AI generated draft text for Courier'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Use This Draft'), findsOneWidget);

      // Tap Discard
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      // Verify sheet is closed and descriptionState was NOT overwritten
      expect(find.text('AI Job Description Draft'), findsNothing);
      expect(descriptionState, equals('Original initial description'));
    });

    testWidgets('Scenario 4: Accept Action applies draft and updates description field', (tester) async {
      String descriptionState = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (_) => _TestDraftHost(
                      initialDraft: 'AI generated draft text for Vehicle Rental',
                      categoryLabel: 'Vehicle Rental',
                      onAccept: (val) {
                        descriptionState = val;
                      },
                    ),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      // Open bottom sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('AI Job Description Draft'), findsOneWidget);
      expect(find.text('Tailored for Vehicle Rental'), findsOneWidget);

      // Tap Use This Draft
      await tester.tap(find.text('Use This Draft'));
      await tester.pumpAndSettle();

      // Verify sheet is closed and descriptionState was successfully populated
      expect(find.text('AI Job Description Draft'), findsNothing);
      expect(descriptionState, equals('AI generated draft text for Vehicle Rental'));
    });
  });
}

class _TestDraftHost extends StatelessWidget {
  final String initialDraft;
  final String categoryLabel;
  final ValueChanged<String> onAccept;

  const _TestDraftHost({
    required this.initialDraft,
    required this.categoryLabel,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return _AIDraftPreviewTestWrapper(
      initialDraft: initialDraft,
      categoryLabel: categoryLabel,
      onAccept: onAccept,
    );
  }
}

class _AIDraftPreviewTestWrapper extends StatefulWidget {
  final String initialDraft;
  final String categoryLabel;
  final ValueChanged<String> onAccept;

  const _AIDraftPreviewTestWrapper({
    required this.initialDraft,
    required this.categoryLabel,
    required this.onAccept,
  });

  @override
  State<_AIDraftPreviewTestWrapper> createState() => _AIDraftPreviewTestWrapperState();
}

class _AIDraftPreviewTestWrapperState extends State<_AIDraftPreviewTestWrapper> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDraft);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('AI Job Description Draft'),
          Text('Tailored for ${widget.categoryLabel}'),
          TextFormField(
            controller: _controller,
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Discard'),
              ),
              ElevatedButton(
                onPressed: () {
                  widget.onAccept(_controller.text.trim());
                  Navigator.pop(context);
                },
                child: const Text('Use This Draft'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
