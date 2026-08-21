import 'package:shared/shared.dart';

/// Dynamic App Context container passed into Nyx AI prompt window
typedef NyxAppContext = TranyxAIUserContext;

/// Secure AI Assistant Service for Tranyx Mobile powered by Google Gemini.
class NyxAIAssistantService {
  final TranyxAIService _aiService;

  NyxAIAssistantService({TranyxAIService? aiService})
      : _aiService = aiService ?? TranyxAIService();

  /// Strips prompt injection tokens and scrubs sensitive wallet seed phrases or addresses
  static String sanitizePrompt(String rawInput) {
    if (rawInput.isEmpty) return '';

    // Strip ChatML / Instruct control tokens
    var clean = rawInput
        .replaceAll(
          RegExp(
            r'<\|begin_of_text\|>|<\|start_header_id\|>|<\|end_header_id\|>|<\|eot_id\|>|<\|im_start\|>|<\|im_end\|>|\[INST\]|\[/INST\]|SYS:|### Instruction:',
          ),
          '',
        )
        .trim();

    // Scrub Solana Base58 wallet addresses (32-44 chars)
    clean = clean.replaceAll(
      RegExp(r'\b[1-9A-HJ-NP-Za-km-z]{32,44}\b'),
      '[SOLANA_ADDRESS_REDACTED]',
    );

    // Scrub potential 12/24 word seed phrases
    clean = clean.replaceAll(
      RegExp(r'\b([a-z]{3,10}\s+){11,23}[a-z]{3,10}\b', caseSensitive: false),
      '[SEED_PHRASE_REDACTED]',
    );

    return clean;
  }

  /// Generates a structured job description (3-4 sentences)
  Future<String> generateJobDescription(String title, {String? categoryLabel}) async {
    if (title.isEmpty) return '';
    return _aiService.generateJobDescription(title, categoryLabel: categoryLabel);
  }

  /// Generates a catchy job title (maximum 5 words)
  Future<String> generateJobTitle(
    JobCategory category,
    String description,
  ) async {
    return _aiService.generateJobTitle(category, description);
  }

  /// Validates whether job title fits category
  Future<bool> validateJobTitle(String title, JobCategory category) async {
    return _aiService.validateJobTitle(title, category);
  }

  /// Generates a bid cover note (2-3 sentences)
  Future<String> generateCoverNote(String jobTitle, {String? workerExperience}) async {
    if (jobTitle.isEmpty) return '';
    return _aiService.generateCoverNote(jobTitle, workerExperience: workerExperience);
  }

  /// Evaluates job authenticity score
  Future<String> evaluateJobAuthenticity(Map<String, dynamic> jobData) async {
    return _aiService.evaluateJobAuthenticity(jobData);
  }

  /// Returns chat response for Nyx assistant chat with dynamic app state context
  Future<String> getChatResponse(
    List<Map<String, String>> conversationHistory, {
    NyxAppContext? appContext,
  }) async {
    if (conversationHistory.isEmpty) return '';
    return _aiService.getChatResponse(conversationHistory, appContext: appContext);
  }
}

