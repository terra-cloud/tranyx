import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:tranyx_mobile/core/utils/enums.dart';

class CloudflareAIService {
  final String accountId;
  final String apiToken;
  final String model;

  CloudflareAIService({
    required this.accountId,
    required this.apiToken,
    this.model = '@cf/meta/llama-3.2-3b-instruct',
  });

  String _buildUrl() {
    final directUrl =
        'https://api.cloudflare.com/client/v4/accounts/$accountId/ai/run/$model';
    if (kIsWeb) {
      return 'https://proxy.corsfix.com/?url=${Uri.encodeComponent(directUrl)}';
    }
    return directUrl;
  }

  Future<String> _runModel(String prompt, {String? systemPrompt}) async {
    final url = _buildUrl();

    final messages = <Map<String, String>>[];
    if (systemPrompt != null) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    messages.add({'role': 'user', 'content': prompt});

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'messages': messages}),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          return decoded['result']['response'] ?? '';
        } else {
          final errors = decoded['errors'] as List?;
          final errorMsg = errors != null && errors.isNotEmpty
              ? errors.first['message']
              : 'Unknown Cloudflare error';
          return 'Error: $errorMsg';
        }
      } else {
        return 'HTTP Error: ${response.statusCode}\nBody: ${response.body}';
      }
    } catch (e) {
      return 'Request failed: $e';
    }
  }

  Future<String> generateJobDescription(String title) async {
    if (title.isEmpty) return '';

    final prompt =
        'Generate a professional job description for a gig titled "$title".';
    final systemPrompt =
        'You are a professional assistant for the Tranyx platform (Philippine on-demand labor market).\n'
        'Instructions:\n'
        '- Generate a concise, clear, and professional job description (3-4 sentences).\n'
        '- Mention that the worker should bring basic tools if applicable.\n'
        '- DO NOT include any introductory or concluding remarks, explanations, or quotes. Output ONLY the description text.\n'
        '- Language rule: Detect the language of the title. If the title is in Waray-Waray, the description MUST be in Waray-Waray. If it is in English, the description MUST be in English.';

    return _runModel(prompt, systemPrompt: systemPrompt);
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
        'Context: $descPart';

    final systemPrompt =
        'You are a professional assistant for the Tranyx platform.\n'
        'Instructions:\n'
        '- Generate a professional and catchy job title (maximum 5 words) that perfectly fits the category and context.\n'
        '- Return ONLY the title text. Do not include quotes, markdown bold, or extra explanations.\n'
        '- Language rule: Detect the language of the context. If it is in Waray-Waray, generate the title in Waray-Waray. If it is in English, generate it in English.';

    final result = await _runModel(prompt, systemPrompt: systemPrompt);
    return result.trim().replaceAll('"', '');
  }

  Future<bool> validateJobTitle(String title, JobCategory category) async {
    if (title.isEmpty) return false;

    final prompt =
        'Verify if the job title matches the category.\n\n'
        'Category: "${category.label}"\n'
        'Job Title: "$title"\n\n'
        'Does this title reasonably belong to this category? Respond with ONLY "YES" or "NO".';

    try {
      final result = await _runModel(prompt);
      final cleanResult = result.trim().toUpperCase();
      return cleanResult.contains('YES');
    } catch (e) {
      return true;
    }
  }

  Future<String> generateCoverNote(String jobTitle) async {
    if (jobTitle.isEmpty) return '';

    final prompt =
        'Write a professional and enthusiastic cover note applying for a gig titled "$jobTitle".';
    final systemPrompt =
        'You are a skilled worker applying for a gig on the Tranyx platform.\n'
        'Instructions:\n'
        '- Write a friendly and concise cover note (2-3 sentences).\n'
        '- Mention having relevant experience, being reliable, and possessing the necessary tools.\n'
        '- Return ONLY the cover note text. Do not include subject lines, placeholders, or explanations.\n'
        '- Language rule: Detect the language of the job title. If the title is in Waray-Waray, the note MUST be in Waray-Waray. If the title is in English, the note MUST be in English.';

    return _runModel(prompt, systemPrompt: systemPrompt);
  }

  Future<String> getChatResponse(
    List<Map<String, String>> conversationHistory,
  ) async {
    final url = _buildUrl();

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content':
            'You are Nyx, the official AI support assistant for the Tranyx platform—a localized service bridging and asset rental platform for the Philippine market.\n\n'
            'TRANYX SYSTEM WORKFLOWS & USER STEPS:\n'
            '1. Gigs & Service Gigs (Odd Jobs / Stationary / Courier):\n'
            '   - Posting Gigs: Employers tap "Post a Gig" / "Post a new Gig" (Jobs tab), select a Category, enter Title, Rate, and detailed Description (or use "Auto-write" AI generation). For courier/delivery tasks, toggle "hasTracker = true" and specify "First Point" (pickup) and "Second Point" (drop-off).\n'
            '   - Applying to Gigs: Nyxians (workers) browse/search the Jobs tab, select a gig, click "Proceed to Apply", choose to bid at "Standard Rate" or "Make a Counter Offer", draft/generate a cover note, and tap "Submit Application".\n'
            '   - Standard Job Completion: Nyxian taps "Mark as Done" -> Employer generates a QR code -> Nyxian scans QR (or enters code) -> Escrow releases payout to Nyxian -> Both rate each other 1-5 stars.\n'
            '   - Delivery Job Tracker Completion (hasTracker = true): Nyxian updates location checkpoints: "Arrived at First Point" -> Taps "Paid Cashier" and uploads receipt photo -> Taps "Going to Second Point" -> "Arrived at Drop-off" -> Nyxian generates QR code -> Employer/recipient scans it -> Escrow releases payout -> Both rate each other 1-5 stars. (Note: QR code flow is reversed: Nyxian generates, Employer scans).\n'
            '2. Vehicle Rentals (Transit Category):\n'
            '   - Listing a Vehicle: Hosts go to the Transit tab -> "Vehicles" -> "Host" tab -> tap "List a Vehicle" and enter brand, model, daily rate, type, transmission, fuel type, photos, and optional GPS Tracker ID (incurs 1.5% listing fee).\n'
            '   - Renting/Booking a Vehicle: Renters go to Transit tab -> "Vehicles" -> "Rent" tab -> select a vehicle card -> tap "Book Now" to send a booking request (locks escrow funds + 3% booking fee). Once the Host approves the request from their "Manage" page, the renter signs the contract (Awaiting Signature status) with their signature to activate the booking. Renters can chat with hosts, view live GPS tracking, and request extensions.\n'
            '3. Property Rentals (Web3 Real Estate Category):\n'
            '   - Listing a Property: Hosts go to Transit tab -> "Real Estate" -> "Host" tab -> tap "List a Property" to rent out residential (Condo, House, Room, Bed Space) or commercial (Office, Coworking, Warehouse) space.\n'
            '   - Renting/Booking a Property: Renters go to Transit tab -> "Real Estate" -> "Rent" tab -> select a property card -> tap "Rent Now" to send a booking request.\n'
            '   - Web3 Transaction System: Purchases/sales are processed securely via Solana (\$SOL) smart contract escrows. Leases and rentals are handled using our custom utility token (\$TYXBIT) for automated lease tracking. Once approved by the host, the renter signs the Lease Agreement.\n\n'
            'CHAT INSTRUCTIONS:\n'
            '- Keep answers friendly, helpful, professional, and very concise (under 4 sentences).\n'
            '- Rely strictly on the Tranyx system workflows and user steps listed above. If you do not know the answer based on these, politely state that you cannot answer.\n'
            '- AVOID UNRELATED QUESTIONS: If the user asks about anything unrelated to Tranyx (e.g., general knowledge, math, coding, or other topics outside the platform), you MUST politely decline to answer (e.g., "I can only help you with questions about the Tranyx platform."). Do not provide answers for unrelated topics.\n'
            '- SATISFACTION CHECK: Always end your response by politely asking the user if there is anything else they need help with (e.g., "Is there anything else I can help you with?", "May iba pa ba akong maitutulong sa iyo?"). Respond using the language/dialect the user is using.\n'
            '- USER SUPPORT LIMITS: Users have support chat rate limits (5 free support tokens maximum, with 1 token recovering every hour). Keep this in mind, and if the user asks about support limits or why they might be blocked, politely explain these rules (5 free tokens max, recovering 1 token/hour).\n'
            '- Converse fluently in English, Tagalog, and Waray-Waray. Respond in the same language/dialect the user uses.',
      },
      ...conversationHistory,
    ];

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'messages': messages}),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          return decoded['result']['response'] ?? '';
        } else {
          final errors = decoded['errors'] as List?;
          final errorMsg = errors != null && errors.isNotEmpty
              ? errors.first['message']
              : 'Unknown Cloudflare error';
          return 'Error: $errorMsg';
        }
      } else {
        return 'HTTP Error: ${response.statusCode}\nBody: ${response.body}';
      }
    } catch (e) {
      return 'Request failed: $e';
    }
  }
}
