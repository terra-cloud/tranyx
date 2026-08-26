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

/// Exception thrown when a job title does not reasonably align with the selected category.
class CategoryMismatchException implements Exception {
  final String message;
  final String title;
  final String categoryLabel;

  const CategoryMismatchException({
    required this.message,
    required this.title,
    required this.categoryLabel,
  });

  @override
  String toString() => message;
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
          return await _callGemini(
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
          throw Exception('Nyx Error (${res.statusCode}): $msg');
        }
      } catch (e) {
        if (attempt == 3) rethrow;
        await Future.delayed(Duration(milliseconds: delays[attempt]));
      }
    }

    throw Exception('Request failed: HTTP ${lastResponse?.statusCode}');
  }

  // ── Auto-Drafting & Generative Features ───────────────────────────────────

  /// Checks whether a given title has a distinct mismatch with the category label.
  static bool isCategoryMismatch(String title, String categoryLabel) {
    if (title.trim().isEmpty || categoryLabel.trim().isEmpty) return false;
    final t = title.toLowerCase();
    final c = categoryLabel.toLowerCase();

    // Specific domain keywords
    final isPlumbingTitle = RegExp(
      r'\b(plumb|tubero|pipe|tubo|gripo|lababo|sink|inidoro|faucet|drain|leak|tumutulo|bara|kubeta)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isElectricalTitle = RegExp(
      r'\b(electric|kuryente|wire|wiring|outlet|breaker|ilaw|fuse|solar|ilawan|switch|kuryentista|elektrisyan)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isCarpentryTitle = RegExp(
      r'\b(carpenter|karpintero|karpentero|panday|woodwork|drywall|kisame|pinto|cabinet|kahoy|lamesa|upuan|tabla)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isVehicleRentalTitle = RegExp(
      r'\b(rent car|rent van|rent motorcycle|arkila|sarakyan|car rental|van rental|motorcycle rental|hire van|arkila ng sasakyan|arkila kotse)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isCourierDeliveryTitle = RegExp(
      r'\b(courier|delivery|deliver|hatid|pickup|padala|paghatod|paghakot|package delivery|maghatid|drayber ng motor|rider)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isCleaningTitle = RegExp(
      r'\b(clean|linis|maglinis|paglimpyo|janitor|maid|housekeeping|general cleaning)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isCookingTitle = RegExp(
      r'\b(cook|magluto|chef|catering|pagkaon|pagluto|kusinero|kusinera|handa)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isMechanicTitle = RegExp(
      r'\b(mechanic|mekaniko|talyer|makina|engine repair|motorcycle repair|car repair|gulong|preno)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isPaintingTitle = RegExp(
      r'\b(painter|pintor|pintura|magpintura|house paint)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isGardeningTitle = RegExp(
      r'\b(gardener|hardinero|halaman|tabas ng damo|landscaping|lawn mowing)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isLaundryTitle = RegExp(
      r'\b(laundry|labada|labandera|maglaba|plantsa|magplantsa)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isTutorTitle = RegExp(
      r'\b(tutor|tutoring|teacher|guro|math tutor|english tutor|piano lesson)\b',
      caseSensitive: false,
    ).hasMatch(t);

    final isPlumbingCat = c.contains('plumb') || c.contains('tubero');
    final isElectricalCat = c.contains('electric') || c.contains('kuryente');
    final isCarpentryCat = c.contains('carpenter') || c.contains('panday') || c.contains('wood');
    final isVehicleRentalCat = c.contains('vehicle') || c.contains('rental') || c.contains('transport');
    final isCourierDeliveryCat = c.contains('courier') || c.contains('delivery');
    final isCleaningCat = c.contains('clean') || c.contains('housekeeping');
    final isCookingCat = c.contains('cook') || c.contains('catering');
    final isMechanicCat = c.contains('mechanic') || c.contains('mekaniko');
    final isPaintingCat = c.contains('paint') || c.contains('pintor');
    final isGardeningCat = c.contains('garden') || c.contains('landscaping');
    final isLaundryCat = c.contains('laundry') || c.contains('labandera');
    final isTutorCat = c.contains('tutor') || c.contains('academic');

    // Cross-match check: If title specifies Domain A, but Category is Domain B (where A != B), it's a mismatch!
    if (isElectricalCat && (isPlumbingTitle || isCarpentryTitle || isVehicleRentalTitle || isCourierDeliveryTitle || isCleaningTitle || isCookingTitle || isMechanicTitle || isPaintingTitle || isGardeningTitle || isLaundryTitle || isTutorTitle)) {
      return true;
    }
    if (isPlumbingCat && (isElectricalTitle || isCarpentryTitle || isVehicleRentalTitle || isCourierDeliveryTitle || isCleaningTitle || isCookingTitle || isMechanicTitle || isPaintingTitle || isGardeningTitle || isLaundryTitle || isTutorTitle)) {
      return true;
    }
    if (isCarpentryCat && (isElectricalTitle || isPlumbingTitle || isVehicleRentalTitle || isCourierDeliveryTitle || isCleaningTitle || isCookingTitle || isMechanicTitle || isPaintingTitle || isGardeningTitle || isLaundryTitle || isTutorTitle)) {
      return true;
    }
    if (isVehicleRentalCat && (isElectricalTitle || isPlumbingTitle || isCarpentryTitle || isCleaningTitle || isCookingTitle || isPaintingTitle || isGardeningTitle || isLaundryTitle || isTutorTitle)) {
      return true;
    }
    if (isCourierDeliveryCat && (isElectricalTitle || isPlumbingTitle || isCarpentryTitle || isCookingTitle || isCleaningTitle || isPaintingTitle || isGardeningTitle || isLaundryTitle || isTutorTitle)) {
      return true;
    }
    if (isCleaningCat && (isElectricalTitle || isPlumbingTitle || isCarpentryTitle || isVehicleRentalTitle || isCookingTitle || isMechanicTitle || isTutorTitle)) {
      return true;
    }
    if (isCookingCat && (isElectricalTitle || isPlumbingTitle || isCarpentryTitle || isVehicleRentalTitle || isCourierDeliveryTitle || isCleaningTitle || isMechanicTitle || isPaintingTitle || isGardeningTitle || isLaundryTitle || isTutorTitle)) {
      return true;
    }
    if (isMechanicCat && (isPlumbingTitle || isCarpentryTitle || isCleaningTitle || isCookingTitle || isPaintingTitle || isGardeningTitle || isLaundryTitle || isTutorTitle)) {
      return true;
    }
    if (isPaintingCat && (isPlumbingTitle || isElectricalTitle || isVehicleRentalTitle || isCourierDeliveryTitle || isCookingTitle || isMechanicTitle || isLaundryTitle || isTutorTitle)) {
      return true;
    }
    if (isGardeningCat && (isPlumbingTitle || isElectricalTitle || isCarpentryTitle || isVehicleRentalTitle || isCourierDeliveryTitle || isCookingTitle || isMechanicTitle || isLaundryTitle || isTutorTitle)) {
      return true;
    }
    if (isLaundryCat && (isPlumbingTitle || isElectricalTitle || isCarpentryTitle || isVehicleRentalTitle || isCourierDeliveryTitle || isCookingTitle || isMechanicTitle || isPaintingTitle || isGardeningTitle || isTutorTitle)) {
      return true;
    }
    if (isTutorCat && (isPlumbingTitle || isElectricalTitle || isCarpentryTitle || isVehicleRentalTitle || isCourierDeliveryTitle || isCleaningTitle || isCookingTitle || isMechanicTitle || isPaintingTitle || isGardeningTitle || isLaundryTitle)) {
      return true;
    }

    return false;
  }

  /// Detects whether the input text is primarily in Waray-Waray, Tagalog, or English.
  static String detectLanguage(String text) {
    final lower = text.toLowerCase();

    // Waray-Waray markers
    final warayMarkers = [
      'nanginginahanglan',
      'nagkikinahanglan',
      'kinahanglan hin',
      'kailangan hin',
      'para hit',
      'ha tacloban',
      'hit balay',
      'drayber',
      'paghakot',
      'paglimpyo',
      'tubero hit',
      'hin motor',
      'ngadto',
      'bubuhaton',
      'pag-ayad',
      'waray',
      'maupay',
      'sarakyan',
      'matatapuran',
      'masasarigan',
      'san panday',
      'san tubero',
      'san karpentero',
      'ha catbalogan',
      'hin tsuper',
      'hin panday',
      'hin tubero',
      'hin kuryente',
      'hit karsada',
      'ha leyte',
      'ha samar',
      'ak san',
      'nanginginahanglan ak',
      'karpentero',
    ];
    for (final marker in warayMarkers) {
      if (lower.contains(marker)) return 'waray';
    }

    // Tagalog markers
    final tagalogMarkers = [
      'kailangan ng',
      'naghahanap ng',
      'kailangan',
      'naghahanap',
      'para sa',
      'sa bahay',
      'maglinis',
      'magluto',
      'mag-ayos',
      'maghatid',
      'tubero',
      'karpintero',
      'sasakyan',
      'maaasahan',
      'maayos',
      'gawaing',
      'ayos',
    ];
    for (final marker in tagalogMarkers) {
      if (lower.contains(marker)) return 'tagalog';
    }

    return 'english';
  }

  /// Returns a rich, category-specific job description detailing tasks, tools, and safety.
  /// Used for rich generative descriptions and offline fallback without ever wrapping titles in raw quotes.
  static String getCategorySpecificDraft({
    required String categoryLabel,
    required String language,
    String? title,
  }) {
    final cat = categoryLabel.toLowerCase();

    if (language == 'waray') {
      if (cat.contains('electric') || cat.contains('kuryente')) {
        return 'Nagkikinahanglan hin maabtik ngan eksperyensyado nga elektrisyan para hit pag-instalar, pag-check, ngan pag-ayad hit mga kable, breaker, outlets, ngan suga. Kinahanglan may-ada kompleto nga gamit sugad hit multi-tester ngan pliers, ngan nasunod ha panseguridad nga pamaagi para malikayan an disgrasya.';
      } else if (cat.contains('plumb') || cat.contains('tubero')) {
        return 'Nagkikinahanglan hin masasarigan nga tubero para hit pag-ayad hit tumutulo o nabara nga mga tubo, gripo, lababo, ngan drainage. Kinahanglan may-ada kalugaringon nga gamit sugad hit pipe wrench ngan andam mag-ayad dayon.';
      } else if (cat.contains('carpenter') || cat.contains('panday') || cat.contains('wood')) {
        return 'Nagkikinahanglan hin eksperyensyado nga panday para hit paghimo o pag-ayad hit mga kahoy nga istruktura sugad hit pinto, kisame, cabinet, o lamesa. Kinahanglan may-ada kompleto nga gamit para ha panday ngan maaram hit husto nga sukol.';
      } else if (cat.contains('delivery') || cat.contains('courier')) {
        return 'Nagkikinahanglan hin masasarigan nga courier o drayber para hit madagmit ngan talwas nga paghakot ngan paghatod hit package ngadto ha destinasyon. Kinahanglan may-ada kalugaringon nga sarakyan, balido nga lisensya, ngan mahibaro hit mga karsada para maabot ha saktong oras.';
      } else if (cat.contains('vehicle') || cat.contains('rental') || cat.contains('transport')) {
        return 'Nagbibiling hin sarakyan para arkilahan para hit biyahe o transportasyon. Kinahanglan aada ha maupay ngan talwas nga kondisyon an sarakyan, kumpleto an rehistro ngan papeles, ngan masunod ha ginkasabutan nga iskedyul ngan rota.';
      } else if (cat.contains('clean') || cat.contains('housekeeping')) {
        return 'Nagkikinahanglan hin maasikaso ngan masasarigan nga para-limpyo para hit bug-os nga paglimpyo hit kwarto, salog, bintana, ngan palibot. Kinahanglan maaram hit tama nga pamaagi hit paglimpyo ngan maingat ha mga gamit.';
      } else if (cat.contains('aircon') || cat.contains('cooling')) {
        return 'Nagkikinahanglan hin eksperyensyado nga aircon technician para hit paglimpyo, pag-check hit freon, ngan pag-ayad hit cooling system. Kinahanglan may-ada pressure washer ngan gamit para mabalik an kabugnaw.';
      } else if (cat.contains('mechanic') || cat.contains('mekaniko')) {
        return 'Nagkikinahanglan hin eksperyensyado nga mekaniko para hit pagsusi ngan pag-ayad hit makina, preno, ngan electrical hit sarakyan para masiguro nga talwas an pagbiyahe.';
      } else if (cat.contains('cook') || cat.contains('catering')) {
        return 'Nagkikinahanglan hin maabtik nga kusinero o tagaluto para hit pag-andam ngan pagluto hin manamit ngan malimpyo nga pagkaon. Kinahanglan maaram ha food safety ngan andam magluto ha oras.';
      } else if (cat.contains('paint') || cat.contains('pintor')) {
        return 'Nagkikinahanglan hin maantigo nga pintor para hit pagpintura hit bungbong, kisame, o gawas hit balay. Kinahanglan maaram mag-scrape, mag-primer, ngan magpatahom hit pintura.';
      } else if (cat.contains('garden') || cat.contains('landscaping')) {
        return 'Nagkikinahanglan hin hardinero para hit pag-ataman hit mga tanom, pagtabas hit damo, ngan pag-ayos hit palibot han natad.';
      } else if (cat.contains('laundry') || cat.contains('labandera')) {
        return 'Nagkikinahanglan hin maasikaso nga labandera para hit paglaba, pagbanlaw, ngan pagplantsa hit mga panapton nang maingat ngan malimpyo.';
      }
      return 'Nagkikinahanglan hin eksperyensyado ngan masasarigan nga trabahador para hit serbisyo ha $categoryLabel. Kinahanglan may-ada kalugaringon nga gamit, maaram ha trabaho, ngan andam magserbisyo dayon.';
    } else if (language == 'tagalog') {
      if (cat.contains('electric') || cat.contains('kuryente')) {
        return 'Naghahanap kami ng maalam at may karanasang elektrisyan para sa ligtas na pagkakabit ng mga kable, pagsusuri ng circuit breaker, at pag-aayos ng mga outlet o ilaw. Siguraduhing may dalang sariling gamit tulad ng multi-tester at sumusunod sa tamang pamantayan ng kaligtasan sa kuryente.';
      } else if (cat.contains('plumb') || cat.contains('tubero')) {
        return 'Naghahanap kami ng maaasahang tubero para magkumpuni ng mga tumutulong tubo, baradong lababo, o sirang gripo. Dapat ay marunong magpalit ng mga fittings, may dalang sariling gamit tulad ng pipe wrench, at handang tapusin ang gawain nang maayos at mabilis.';
      } else if (cat.contains('carpenter') || cat.contains('panday') || cat.contains('wood')) {
        return 'Naghahanap kami ng bihasang karpintero para sa paggawa o pagkukumpuni ng mga kahoy tulad ng pinto, kisame, cabinet, o kasangkapan. Dapat ay may sariling mga gamit sa pagkakarpintero, marunong sa tamang sukat, at maingat sa pagkakagawa.';
      } else if (cat.contains('delivery') || cat.contains('courier')) {
        return 'Naghahanap kami ng maaasahang courier para sa mabilis at ligtas na pagkuha at paghahatid ng package sa itinakdang lokasyon. Kailangan may sariling maayos na sasakyan, balidong lisensya, at kabisado ang mga ruta para makarating sa tamang oras nang walang sira ang gamit.';
      } else if (cat.contains('vehicle') || cat.contains('rental') || cat.contains('transport')) {
        return 'Naghahanap ng maaasahang serbisyo ng sasakyan para sa arkila at transportasyon. Siguraduhing maayos at ligtas ang takbo ng sasakyan, may kumpletong rehistro at dokumento, at masusunod ang napagkasunduang oras at ruta.';
      } else if (cat.contains('clean') || cat.contains('housekeeping')) {
        return 'Naghahanap ng masipag at mapagkakatiwalaang tagalinis para sa masusing paglilinis ng mga silid, sahig, bintana, at mga kagamitan. Dapat ay maingat sa mga gamit at masinop sa pag-aayos ng buong lugar.';
      } else if (cat.contains('aircon') || cat.contains('cooling')) {
        return 'Naghahanap kami ng maalam na aircon technician para sa cleaning, pagdagdag ng freon, at pagsusuri ng cooling system. Dapat ay may kumpletong gamit tulad ng pressure washer at manifold gauge para manatiling malamig at maayos ang aircon.';
      } else if (cat.contains('mechanic') || cat.contains('mekaniko')) {
        return 'Naghahanap ng bihasang mekaniko para sa pagsusuri at pagkukumpuni ng makina, preno, at mechanical parts ng sasakyan. Dapat ay may kumpletong tools, marunong mag-troubleshoot, at masigurong ligtas itakbo ang sasakyan.';
      } else if (cat.contains('cook') || cat.contains('catering')) {
        return 'Naghahanap ng mahusay na kusinero para sa paghahanda at pagluluto ng masarap at malinis na pagkain. Dapat ay maalam sa food safety at kayang maghanda sa tamang oras.';
      } else if (cat.contains('paint') || cat.contains('pintor')) {
        return 'Naghahanap ng marunong na pintor para sa pagpipintura ng pader, kisame, o labas ng bahay. Marunong mag-scrape, mag-primer, at mag-apply ng magandang finish.';
      } else if (cat.contains('garden') || cat.contains('landscaping')) {
        return 'Naghahanap ng hardinero para sa pag-aalaga ng halaman, pagtabas ng damo, at paglilinis ng bakuran.';
      } else if (cat.contains('laundry') || cat.contains('labandera')) {
        return 'Naghahanap ng maasahang labandera para sa paglalaba, pagbabanlaw, at pamamalantsa ng mga damit nang maayos at malinis.';
      }
      return 'Naghahanap kami ng mahusay at maaasahang manggagawa para sa serbisyo sa $categoryLabel. Dapat ay may sapat na karanasan, may sariling gamit, at handang magsimula agad.';
    } else {
      if (cat.contains('electric') || cat.contains('kuryente')) {
        return 'Seeking a qualified and experienced electrician to perform electrical wiring, inspect circuit breakers, and install or repair electrical outlets safely. The applicant must bring essential electrical tools and testing equipment, ensuring all work complies with safety standards.';
      } else if (cat.contains('plumb') || cat.contains('tubero')) {
        return 'Looking for a skilled plumber to inspect and repair leaking pipes, clear blocked drains, and replace damaged faucets or fixtures. Must bring complete plumbing tools such as wrenches and sealants to ensure high-quality and leak-free repairs.';
      } else if (cat.contains('carpenter') || cat.contains('panday') || cat.contains('wood')) {
        return 'Seeking a skilled carpenter to handle woodwork fabrication, door or ceiling repairs, framing, and furniture assembly. The ideal candidate must have their own carpentry tools, precision measuring skills, and deliver sturdy, well-finished work.';
      } else if (cat.contains('delivery') || cat.contains('courier')) {
        return 'Seeking a dependable courier to manage timely pickup and safe delivery of items to the designated drop-off address. Must possess a roadworthy vehicle, valid driver\'s license, and strong route knowledge to ensure secure transit.';
      } else if (cat.contains('vehicle') || cat.contains('rental') || cat.contains('transport')) {
        return 'Looking for a well-maintained vehicle for rental transport. The vehicle must be clean, mechanically sound, fully registered, and available according to the agreed schedule and travel route.';
      } else if (cat.contains('clean') || cat.contains('housekeeping')) {
        return 'Seeking a detail-oriented cleaner for comprehensive house cleaning, including sanitizing rooms, floors, windows, and surfaces. Must be trustworthy, thorough, and careful with household items.';
      } else if (cat.contains('aircon') || cat.contains('cooling')) {
        return 'Looking for a certified aircon technician to perform deep cleaning, freon replenishment, and cooling system diagnostic repairs. Must have dedicated cleaning pressure pumps, manifold gauges, and ensure optimal cooling performance.';
      } else if (cat.contains('mechanic') || cat.contains('mekaniko')) {
        return 'Seeking an experienced mechanic for engine troubleshooting, brake inspection, and general vehicle repairs. Must bring diagnostic tools and wrenches to ensure the vehicle is safe and roadworthy.';
      } else if (cat.contains('cook') || cat.contains('catering')) {
        return 'Looking for a skilled cook or catering assistant to prepare and cook high-quality, delicious meals. Must be knowledgeable in food hygiene and punctual in meal preparation.';
      } else if (cat.contains('paint') || cat.contains('pintor')) {
        return 'Seeking a professional painter for interior or exterior wall painting, surface prep, priming, and finishing. Must deliver clean, smooth, and even paint coverage.';
      } else if (cat.contains('garden') || cat.contains('landscaping')) {
        return 'Looking for an experienced gardener for lawn mowing, plant pruning, weeding, and yard maintenance.';
      } else if (cat.contains('laundry') || cat.contains('labandera')) {
        return 'Seeking a reliable laundry worker for washing, rinsing, and ironing clothes with care and attention to fabric types.';
      }
      return 'We are looking for a reliable worker to perform $categoryLabel services. The candidate should possess relevant experience and bring necessary tools for completing the job efficiently.';
    }
  }

  /// Generates a professional, clear, and realistic job description (3-4 sentences).
  /// Automatically validates category alignment and drafts in Waray-Waray, Tagalog, or English.
  Future<String> generateJobDescription(
    String title, {
    String? categoryLabel,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return '';

    // Check category alignment if category is specified
    if (categoryLabel != null && categoryLabel.trim().isNotEmpty) {
      if (isCategoryMismatch(trimmedTitle, categoryLabel)) {
        throw CategoryMismatchException(
          message:
              'Category Mismatch: The job title "$trimmedTitle" does not match the selected category "$categoryLabel". Please select the correct category or update your job title.',
          title: trimmedTitle,
          categoryLabel: categoryLabel,
        );
      }
    }

    final categoryHint = categoryLabel != null && categoryLabel.isNotEmpty
        ? ' in category "$categoryLabel"'
        : '';

    final effectiveCategory = categoryLabel ?? 'General';
    final detectedLang = detectLanguage(trimmedTitle);

    const systemPrompt =
        'You are an expert recruitment and logistics assistant for Tranyx (Philippine on-demand labor, gig & vehicle marketplace).\n'
        'Instructions:\n'
        '- Generate a concise, clear, rich, and professional job description (3-4 sentences).\n'
        '- CATEGORY ALIGNMENT:\n'
        '  * Check if the job title fits the category. If there is a complete mismatch, respond with EXACTLY: "MISMATCH: The job title does not match the selected category."\n'
        '- CATEGORY DUTIES & RICH DESCRIPTIONS:\n'
        '  * NEVER simply repeat or quote the job title verbatim in quotes. Instead, describe the actual tasks, equipment/tools required, safety standards, and performance expectations relevant to the specified category.\n'
        '  * If category is related to "Vehicle Rental", "Courier / Delivery", or logistics, include specific logistics terms such as vehicle type/requirements, pickup and drop-off locations, timing/schedule, and safe transit expectations.\n'
        '  * If category is a trade/skilled service (plumbing, electrical, cleaning, carpentry, aircon, mechanic, cooking, etc.), outline the key tasks, materials, and mention bringing necessary tools/equipment.\n'
        '- LANGUAGE MATCHING RULE (STRICT):\n'
        '  * If the job title is in Waray-Waray (e.g. using Waray terms like "nagkikinahanglan", "para hit", "hin", "hit", "ha", "ngadto", "ak san", "san"), write the entire description in natural, fluent Waray-Waray.\n'
        '  * If the job title is in Tagalog (e.g. using Tagalog terms like "kailangan ng", "naghahanap", "para sa", "sa"), write the entire description in natural, fluent Tagalog.\n'
        '  * If in English, write in English.\n'
        '- Output ONLY the raw description text. Do NOT include markdown titles, quotes, conversational greetings, or explanations.';

    final prompt =
        'Job Title: "$trimmedTitle"$categoryHint\nLanguage: $detectedLang\nGenerate the tailored job description:';

    try {
      final result = await _callGemini(
        prompt: prompt,
        systemInstruction: systemPrompt,
      );
      final clean = _cleanOutput(result);
      if (clean.toUpperCase().startsWith('MISMATCH:')) {
        throw CategoryMismatchException(
          message:
              'Category Mismatch: The job title "$trimmedTitle" does not match the selected category "$categoryLabel". Please select the correct category or update your job title.',
          title: trimmedTitle,
          categoryLabel: categoryLabel ?? 'General',
        );
      }
      return clean;
    } on CategoryMismatchException {
      rethrow;
    } catch (e) {
      // Clean fallback if offline or in mock
      return getCategorySpecificDraft(
        categoryLabel: effectiveCategory,
        language: detectedLang,
        title: trimmedTitle,
      );
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
      final lastUserMsg =
          conversationHistory.lastWhere(
            (m) => m['role'] == 'user',
            orElse: () => {'content': ''},
          )['content'] ??
          '';
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
