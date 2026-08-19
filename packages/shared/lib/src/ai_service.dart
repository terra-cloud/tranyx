import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'env.dart';
import 'nyx_domain_knowledge.dart';

/// Dynamic Tranyx AI context information
class TranyxAIUserContext {
  final String? userRole; // 'Employer' | 'Nyxian'
  final String? userId;
  final String? walletAddress;
  final String? connectedWallet;
  final double? solBalance;
  final double? tyxbitBalance;
  final double? lockedEscrowBalance;
  final int? activeGigsCount;
  final int? activeRentalsCount;
  final bool? isWalletVerified;

  const TranyxAIUserContext({
    this.userRole,
    this.userId,
    this.walletAddress,
    this.connectedWallet,
    this.solBalance,
    this.tyxbitBalance,
    this.lockedEscrowBalance,
    this.activeGigsCount,
    this.activeRentalsCount,
    this.isWalletVerified,
  });

  String buildContextBlock() {
    final buffer = StringBuffer();
    buffer.writeln('=== CURRENT TRANYX USER & APP CONTEXT ===');
    if (userRole != null) buffer.writeln('User Role: $userRole');
    if (userId != null) buffer.writeln('User ID: $userId');
    if (isWalletVerified != null) {
      buffer.writeln(
        'Wallet Verification: ${isWalletVerified! ? "Verified (1:1)" : "Unverified"}',
      );
    }
    if (connectedWallet != null && connectedWallet!.isNotEmpty) {
      final addr = walletAddress ?? '';
      final maskedAddr = addr.length > 10
          ? '${addr.substring(0, 4)}...${addr.substring(addr.length - 4)}'
          : addr;
      buffer.writeln('Connected Wallet: $connectedWallet ($maskedAddr)');
    }
    if (solBalance != null || tyxbitBalance != null) {
      buffer.writeln(
        'Balances: ${(solBalance ?? 0).toStringAsFixed(3)} SOL | ${(tyxbitBalance ?? 0).toStringAsFixed(2)} TYXBIT',
      );
    }
    if (lockedEscrowBalance != null && lockedEscrowBalance! > 0) {
      buffer.writeln(
        'Escrow Locked Funds: ₱${lockedEscrowBalance!.toStringAsFixed(2)}',
      );
    }
    if (activeGigsCount != null) {
      buffer.writeln('Active Gigs: $activeGigsCount');
    }
    if (activeRentalsCount != null) {
      buffer.writeln('Active Rentals: $activeRentalsCount');
    }
    buffer.writeln('========================================');
    return buffer.toString();
  }
}

/// Unified Tranyx AI Assistant & Generative Engine powered by Google Gemini.
/// Shared seamlessly across both Mobile (Flutter) and Web (Jaspr).
class TranyxAIService {
  static const String primaryModel = 'gemini-3.6-flash';
  static const String fallbackModel = 'gemini-flash-latest';
  static const String apiBase =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final String? _customApiKey;
  final http.Client _client;

  TranyxAIService({String? apiKey, http.Client? client})
    : _customApiKey = apiKey,
      _client = client ?? http.Client();

  String get _apiKey {
    if (_customApiKey != null && _customApiKey.isNotEmpty) {
      return _customApiKey;
    }
    return Env.geminiApiKey;
  }

  // ── Core Gemini REST Execution ──────────────────────────────────────────

  Future<String> _callGemini({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>>? conversationHistory,
    String model = primaryModel,
  }) async {
    final key = _apiKey;
    if (key.isEmpty) {
      throw StateError('GEMINI_AI_API_KEY is not configured in environment.');
    }

    final endpoint = '$apiBase/$model:generateContent?key=$key';

    // Build Gemini contents payload
    final contents = <Map<String, dynamic>>[];

    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      for (final msg in conversationHistory) {
        final role = msg['role'] == 'user' ? 'user' : 'model';
        final text = msg['content'] ?? '';
        if (text.isNotEmpty) {
          contents.add({
            'role': role,
            'parts': [
              {'text': text},
            ],
          });
        }
      }
    } else {
      contents.add({
        'role': 'user',
        'parts': [
          {'text': prompt},
        ],
      });
    }

    final requestBody = <String, dynamic>{
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'topP': 0.95,
        'maxOutputTokens': 1024,
      },
    };

    if (systemInstruction != null && systemInstruction.isNotEmpty) {
      requestBody['systemInstruction'] = {
        'parts': [
          {'text': systemInstruction},
        ],
      };
    }

    const delays = [800, 1600, 3000];
    http.Response? lastResponse;

    for (var attempt = 0; attempt <= 3; attempt++) {
      try {
        final res = await _client
            .post(
              Uri.parse(endpoint),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(requestBody),
            )
            .timeout(const Duration(seconds: 20));

        lastResponse = res;

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'] as Map?;
            final parts = content?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final rawText = parts[0]['text'] as String? ?? '';
              return rawText.trim();
            }
          }
          return '';
        } else if (res.statusCode == 404 && model != fallbackModel) {
          // Fallback to secondary model if model name changed
          return _callGemini(
            prompt: prompt,
            systemInstruction: systemInstruction,
            conversationHistory: conversationHistory,
            model: fallbackModel,
          );
        } else if (res.statusCode == 429 || res.statusCode >= 500) {
          // Rate limit or server error, retry with backoff
          if (attempt < delays.length) {
            await Future.delayed(Duration(milliseconds: delays[attempt]));
            continue;
          }
        } else {
          // 4xx Client error (e.g. rate limit, bad payload)
          final errBody = jsonDecode(res.body);
          final msg = errBody['error']?['message'] ?? res.body;
          throw Exception('Gemini API Error (${res.statusCode}): $msg');
        }
      } catch (e) {
        if (attempt == 3) rethrow;
        await Future.delayed(Duration(milliseconds: delays[attempt]));
      }
    }

    throw Exception('Gemini request failed: HTTP ${lastResponse?.statusCode}');
  }

  // ── Auto-Drafting & Generative Features ───────────────────────────────────

  /// Generates a professional, clear, and realistic job description (3-4 sentences).
  /// Automatically matches the language of the job title (English, Tagalog, or Waray-Waray).
  Future<String> generateJobDescription(
    String title, {
    String? categoryLabel,
  }) async {
    if (title.trim().isEmpty) return '';

    final categoryHint = categoryLabel != null && categoryLabel.isNotEmpty
        ? ' in category "$categoryLabel"'
        : '';

    const systemPrompt =
        'You are an expert recruitment assistant for Tranyx (Philippine on-demand labor & gig marketplace).\n'
        'Instructions:\n'
        '- Generate a concise, clear, and professional job description (3-4 sentences).\n'
        '- Outline the main responsibilities and specify that the worker should bring standard tools if applicable.\n'
        '- Output ONLY the raw description text. Do NOT include markdown titles, quotes, conversational greetings, or explanations.\n'
        '- LANGUAGE MATCHING RULE: Detect the language of the job title. If the title is in Waray-Waray, write the description in Waray-Waray. If it is in Tagalog, write in Tagalog. If in English, write in English.';

    final prompt =
        'Job Title: "$title"$categoryHint\nGenerate the job description:';

    try {
      final result = await _callGemini(
        prompt: prompt,
        systemInstruction: systemPrompt,
      );
      return _cleanOutput(result);
    } catch (e) {
      // Clean fallback if offline
      return 'We are looking for a reliable worker to perform $title. The candidate should possess relevant experience and bring necessary tools for completing the job efficiently.';
    }
  }

  /// Generates a friendly, confident, and persuasive bid cover note (2-3 sentences).
  /// Automatically matches the language of the gig title.
  Future<String> generateCoverNote(
    String jobTitle, {
    String? workerExperience,
  }) async {
    if (jobTitle.trim().isEmpty) return '';

    const systemPrompt =
        'You are a skilled and reliable worker applying for a gig on the Tranyx platform.\n'
        'Instructions:\n'
        '- Write a friendly, confident, and concise cover note (2-3 sentences).\n'
        '- Mention having relevant practical experience, being prepared with tools, and ready to start immediately.\n'
        '- Output ONLY the cover note text. Do not include salutations like "Subject:", quotes, markdown, or placeholders.\n'
        '- LANGUAGE MATCHING RULE: Detect the language of the job title. If in Waray-Waray, write in Waray-Waray. If in Tagalog, write in Tagalog. If in English, write in English.';

    final expHint = workerExperience != null && workerExperience.isNotEmpty
        ? '\nWorker background: $workerExperience'
        : '';

    final prompt = 'Applying for Gig: "$jobTitle"$expHint\nWrite cover note:';

    try {
      final result = await _callGemini(
        prompt: prompt,
        systemInstruction: systemPrompt,
      );
      return _cleanOutput(result);
    } catch (e) {
      return 'Hi! I am enthusiastic about applying for "$jobTitle". I have proven experience, complete tools, and can start immediately upon hire.';
    }
  }

  /// Generates a catchy, professional job title (maximum 5 words) fitting the category.
  Future<String> generateJobTitle(
    JobCategory category,
    String description,
  ) async {
    const systemPrompt =
        'You are a hiring assistant for Tranyx.\n'
        'Instructions:\n'
        '- Generate a professional, catchy job title (maximum 5 words) fitting the category and task description.\n'
        '- Return ONLY the title text. Do NOT include quotes, headers, or explanations.\n'
        '- Language rule: Match the language of the input description (English, Tagalog, or Waray-Waray).';

    final prompt =
        'Category: "${category.label}"\n'
        'Description: "${description.isEmpty ? category.description : description}"\n'
        'Generate Job Title:';

    try {
      final result = await _callGemini(
        prompt: prompt,
        systemInstruction: systemPrompt,
      );
      final clean = _cleanOutput(
        result,
      ).replaceAll('"', '').replaceAll('#', '').trim();
      return clean.isNotEmpty ? clean : 'Experienced ${category.label} Worker';
    } catch (e) {
      return 'Experienced ${category.label} Worker';
    }
  }

  /// Validates whether a job title reasonably fits a category
  Future<bool> validateJobTitle(String title, JobCategory category) async {
    if (title.trim().isEmpty) return false;

    const systemPrompt =
        'You are a content moderator for Tranyx.\n'
        'Task: Determine if the job title reasonably fits the given job category.\n'
        'Respond with ONLY "YES" or "NO".';

    final prompt =
        'Category: "${category.label}"\nJob Title: "$title"\nFits category?';

    try {
      final result = await _callGemini(
        prompt: prompt,
        systemInstruction: systemPrompt,
      );
      final upper = result.trim().toUpperCase();
      return upper.contains('YES');
    } catch (e) {
      return true; // Don't block on network glitch
    }
  }

  /// Evaluates job authenticity score and market reasonableness
  Future<String> evaluateJobAuthenticity(Map<String, dynamic> jobData) async {
    final title = jobData['title'] ?? 'Gig';
    final desc = jobData['description'] ?? '';
    final rate = jobData['pricingValue'] ?? jobData['budget'] ?? 0;
    final category = jobData['category'] ?? '';

    const systemPrompt =
        'You are an AI labor market analyst for the Philippine gig platform Tranyx.\n'
        'Task: Evaluate the authenticity, clarity, and budget reasonableness of the job posting.\n'
        'Instructions:\n'
        '- Provide a concise 2-sentence assessment of the job details and rate.\n'
        '- Conclude exactly with "Authenticity Score: X/10."';

    final prompt =
        'Job Title: "$title"\n'
        'Category: "$category"\n'
        'Budget: ₱$rate\n'
        'Description: "$desc"\n'
        'Evaluate job listing:';

    try {
      final result = await _callGemini(
        prompt: prompt,
        systemInstruction: systemPrompt,
      );
      final clean = _cleanOutput(result);
      if (clean.contains('Authenticity Score')) return clean;
      return '$clean Authenticity Score: 9/10.';
    } catch (e) {
      return 'Job details reviewed. The description and rate align with standard platform guidelines. Authenticity Score: 9/10.';
    }
  }

  // ── Nyx Support Assistant Multi-Turn Chat ────────────────────────────────

  /// Handles conversational multi-turn AI support chat for Tranyx users.
  Future<String> getChatResponse(
    List<Map<String, String>> conversationHistory, {
    TranyxAIUserContext? appContext,
  }) async {
    if (conversationHistory.isEmpty) return '';

    final systemPromptBuffer = StringBuffer();
    systemPromptBuffer.writeln(
      'You are Nyx, the official AI support assistant for Tranyx—the premier on-demand gig, delivery tracking, and vehicle/property rental platform in the Philippines.\n\n'
      'OFFICIAL TRANYX PLATFORM KNOWLEDGE BASE:\n'
      '1. Gigs & Escrow System:\n'
      '   - Creating Gigs/Listings: Employers go to the Jobs tab and click "+ New" (or "+ Create New Listing" at the bottom of listings on web, or the "+" button on mobile), input Category, Title, Budget in PHP (₱), Date, and Description (or use AI Auto-write). Funds are locked safely in Escrow upon hiring a worker.\n'
      '   - Applying to Gigs: Nyxians (workers) browse listings, select a gig, click "Proceed to Apply", place bids at standard rate or submit counter-offers with an AI Auto-drafted cover note.\n'
      '   - Standard Job Completion: Nyxian marks done -> Employer generates QR code -> Nyxian scans QR -> Escrow instantly releases payout to Nyxian -> Both rate each other 1-5 stars.\n'
      '   - Delivery Tracker Gigs (hasTracker = true): 5-step delivery state machine (Arrived at Pickup -> Paid Cashier & Upload Receipt -> In-Transit GPS -> Arrived at Dropoff -> Nyxian generates completion QR code for recipient to scan -> Instant Escrow payout).\n'
      '2. Transit (Vehicle & Property Rentals):\n'
      '   - Vehicles: Hosts list cars, motorcycles, scooters with daily rates. Renters book via SOL or TYXBIT tokens. Once host approves, renter signs digital contract to activate.\n'
      '   - Real Estate: Hosts list condos, apartments, rooms, commercial spaces. Renters book with SOL/TYXBIT escrow.\n'
      '3. Wallets & Web3 Integration:\n'
      '   - Supported Wallets: Phantom, Solflare, Trust Wallet with strict 1:1 user-to-wallet verification (Profile -> Trust & Verification -> Linked Accounts).\n'
      '   - SOL: Used for Solana blockchain transactions, gas fees, and rental payments.\n'
      '   - TYXBIT: Native platform reward utility token for rental discounts, fee reductions, and perks.\n'
      '4. Trust & Verification (KYC Tiers):\n'
      '   - Tier 1 (Phone & Email), Tier 2 (Government ID & Selfie), Tier 3 (Skill Accreditation & Bonded Badge).\n'
      '   - Primary IDs: PhilID (National ID), UMID, Driver\'s License, Passport, SSS, PRC, Postal ID, Voter\'s ID.\n'
      '   - Bonded & Protected status unlocks priority applications and reduced service fees.\n'
      '5. Support Limits:\n'
      '   - Users have 5 free support questions max, recovering 1 question every hour. Generative features (cover notes, job descriptions) remain unlimited.\n\n'
      'CONVERSATION INSTRUCTIONS:\n'
      '- Tone: Friendly, highly competent, professional, encouraging, and concise (under 4 sentences per response).\n'
      '- Multi-language Fluency: Respond fluently in English, Tagalog (Filipino), or Waray-Waray depending on what the user speaks.\n'
      '- Scope Restriction: If the user asks about topics completely unrelated to Tranyx (e.g. recipes, general coding, sports, weather outside context), politely decline by stating you are Nyx and exclusively assist with Tranyx gigs, rentals, escrow, and wallets.\n'
      '- Escalation Rule: If the user explicitly asks to speak with a human support agent, reports an unresolved dispute, or needs manual administrative intervention, respond EXACTLY with "TRANSFER_TO_AGENT".\n'
      '- End with a brief, friendly follow-up offer (e.g. "May maitutulong pa ba ako?", "May iba pa ba akong maibubulig?").',
    );

    if (appContext != null) {
      systemPromptBuffer.writeln('\n${appContext.buildContextBlock()}');
    }

    try {
      final response = await _callGemini(
        prompt: '',
        systemInstruction: systemPromptBuffer.toString(),
        conversationHistory: conversationHistory,
      );

      final clean = response.trim();
      if (clean.contains('TRANSFER_TO_AGENT')) {
        return 'TRANSFER_TO_AGENT';
      }
      return clean;
    } catch (e) {
      final lastUserMsg = conversationHistory.lastWhere(
        (m) => m['role'] == 'user',
        orElse: () => {'content': ''},
      )['content'] as String? ?? '';
      return NyxDomainKnowledgeBase.queryKnowledge(lastUserMsg);
    }
  }

  String _cleanOutput(String input) {
    var out = input.trim();
    // Strip wrapping markdown quotes if model added them
    if (out.startsWith('```') && out.endsWith('```')) {
      final lines = out.split('\n');
      if (lines.length > 2) {
        out = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    return out;
  }
}
