import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/utils/enums.dart';

final geminiModelProvider = Provider<GenerativeModel>((ref) {
  return FirebaseAI.googleAI().generativeModel(model: 'gemini-2.5-flash');
});

final aiServiceProvider = Provider((ref) {
  final model = ref.watch(geminiModelProvider);
  return AIService(model);
});

class AIService {
  final GenerativeModel _model;
  AIService(this._model);

  Future<String> generateJobDescription(String title) async {
    if (title.isEmpty) return '';

    final prompt =
        'Generate a professional job description for a gig titled "$title". '
        'IMPORTANT: DO NOT include the explanation, just the description.'
        'IMPORTANT: Detect the language of the title. If the title is in Waray-Waray, the description MUST be in Waray-Waray. '
        'If the title is in English, the description MUST be in English. '
        'Keep it concise, clear, and professional. '
        'Mention that the worker should bring basic tools if applicable. '
        'Limit to about 3-4 sentences.';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? 'Failed to generate description.';
    } catch (e) {
      return 'Error generating description: $e';
    }
  }

  Future<String> generateJobTitle(
    JobCategory category,
    String description,
  ) async {
    final descPart = description.isEmpty
        ? 'its official description: "${category.description}"'
        : 'the following user-provided description: "$description"';

    final prompt =
        'Category: "${category.label}"\n'
        'Context: $descPart\n\n'
        'Task: Generate a professional and catchy job title (maximum 5 words) that perfectly fits this category and context. '
        'IMPORTANT: Detect the language of the Context. It should match the Job Title\'s language. '
        'If it is in English, generate the title in English. '
        'Return ONLY the title text. Do not include quotes or extra explanations.';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      return (response.text ?? '').trim().replaceAll('"', '');
    } catch (e) {
      return 'Error generating title: $e';
    }
  }

  Future<bool> validateJobTitle(String title, JobCategory category) async {
    if (title.isEmpty) return false;

    final prompt =
        'Verify if the job title matches the category.\n\n'
        'Category: "${category.label}"\n'
        'Job Title: "$title"\n\n'
        'Does this title reasonably belong to this category? Respond with ONLY "YES" or "NO".';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final result = (response.text ?? '').trim().toUpperCase();
      return result.contains('YES');
    } catch (e) {
      return true;
    }
  }

  Future<String> generateCoverNote(String jobTitle) async {
    if (jobTitle.isEmpty) return '';

    final prompt =
        'Write a professional and enthusiastic cover note applying for a gig titled "$jobTitle". '
        'IMPORTANT: Detect the language of the job title. If the title is in Waray-Waray, the note MUST be in Waray-Waray. '
        'If the title is in English, the note MUST be in English. '
        'Mention having relevant experience, being reliable, and possessing the necessary tools. '
        'Keep it friendly and concise (2-3 sentences).';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? 'Failed to generate cover note.';
    } catch (e) {
      return 'Error generating cover note: $e';
    }
  }
}
