# Skill: Add Gemini AI Feature (Flutter Mobile)

## Purpose
Guides an agent through integrating Gemini 2.5 Flash into the Tranyx mobile app for AI-powered content generation.

## Package Setup
Add to `pubspec.yaml`:
```yaml
dependencies:
  google_generative_ai: ^0.4.0
```

## Service Implementation
```dart
// lib/shared/services/gemini_service.dart
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  late final GenerativeModel _model;

  GeminiService(String apiKey) {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );
  }

  static const _delays = [1, 2, 4, 8, 16]; // exponential backoff seconds

  Future<String> generate(String prompt) async {
    for (int attempt = 0; attempt < _delays.length; attempt++) {
      try {
        final content = [Content.text(prompt)];
        final response = await _model.generateContent(content);
        return response.text ?? '';
      } catch (e) {
        if (attempt == _delays.length - 1) rethrow;
        await Future.delayed(Duration(seconds: _delays[attempt]));
      }
    }
    throw Exception('Gemini unreachable after retries');
  }

  Future<String> draftJobDescription(String title, String category) =>
      generate(
        'Write a professional job description for a "$category" role titled "$title". '
        'Keep it concise (3-4 sentences), friendly, and focused on tasks and requirements.',
      );

  Future<String> draftCoverNote({
    required String category,
    required bool isCounterOffer,
    String? counterRate,
  }) =>
      generate(
        'Write a professional cover note for a gig application as a "$category" worker. '
        '${isCounterOffer ? "The applicant is counter-offering at $counterRate." : ""}'
        'Keep it warm, confident, and under 100 words.',
      );
}
```

## Provider
```dart
// lib/providers/gemini_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/services/gemini_service.dart';
import '../core/config/env.dart'; // for geminiApiKey

final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService(Env.geminiApiKey);
});

// Async state for AI generation
final jobDescriptionProvider = FutureProvider.family<String, ({String title, String category})>(
  (ref, params) async {
    final gemini = ref.watch(geminiServiceProvider);
    return gemini.draftJobDescription(params.title, params.category);
  },
);
```

## UI Integration
```dart
// In ConsumerWidget build:
final isDrafting = ref.watch(isDraftingDescProvider);

ElevatedButton(
  onPressed: isDrafting ? null : () async {
    ref.read(isDraftingDescProvider.notifier).state = true;
    try {
      final desc = await ref.read(geminiServiceProvider)
        .draftJobDescription(title, category);
      descController.text = desc;
    } finally {
      ref.read(isDraftingDescProvider.notifier).state = false;
    }
  },
  child: isDrafting
    ? Row(children: [CircularProgressIndicator(strokeWidth: 2), Text(' Generating...')])
    : Row(children: [Icon(Icons.auto_awesome), Text(' Auto-Draft')]),
)
```
