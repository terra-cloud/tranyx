import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

import 'firebase_service.dart';
import 'web_interop.dart';

/// Firebase AI Logic (Gemini Developer API through the Firebase project).
/// Uses the public Firebase web apiKey plus an App Check token. There is no Gemini API key.
class TranyxFirebaseAi {
  static const model = 'gemini-flash-latest';
  static const unavailable = 'Nyx couldn’t answer just now. Please try again in a moment.';

  /// Browser console only. Status and a short API message, never the key or the App Check token.
  static void Function(String message) log = _log;

  static void _log(String message) {
    // ignore: avoid_print
    print(message);
  }

  /// Gemini Developer API path. `publishers/google/models` is the Vertex route and 404s here.
  static Uri endpoint(String projectId, {String modelName = model}) {
    return Uri.parse(
      'https://firebasevertexai.googleapis.com/v1beta/projects/$projectId/models/$modelName:generateContent',
    );
  }

  /// Console line for a non-200 response. Keys, bearer tokens, and URLs are stripped.
  static String failureLog(int status, String body) {
    var message = body;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        message = '${error['status'] ?? ''} ${error['message'] ?? ''}'.trim();
      }
    } catch (_) {
      message = 'non-json body';
    }
    if (message.trimLeft().startsWith('<')) message = 'non-json body';
    message = message
        .replaceAll(RegExp(r'https?:\/\/\S+', caseSensitive: false), '[url]')
        .replaceAll(RegExp(r'AIza[0-9A-Za-z_\-]{10,}'), '[key]')
        .replaceAll(RegExp(r'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'), '[token]');
    if (message.length > 180) message = message.substring(0, 180);
    return 'Nyx generateContent failed status=$status $message';
  }

  static bool shouldRetry(int status) =>
      status == 401 || status == 429 || status == 500 || status == 502 || status == 503 || status == 504;

  Future<String> reply({
    required String message,
    List<Map<String, String>> history = const [],
    required bool signedIn,
    String? idToken,
    int? nowMs,
    http.Client? httpClient,
    Future<String?> Function(Map<String, String> config, String siteKey)? appCheck,
    Duration retryDelay = const Duration(milliseconds: 400),
  }) async {
    final decision = TranyxTopicGuard.classify(message);
    final refusal = TranyxTopicGuard.refusalFor(decision);
    if (refusal != null) return refusal;

    final userKey = signedIn ? (SessionStorage.uid ?? 'user') : 'guest';
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final stamps = _readStamps(userKey);
    if (!TranyxAssistantQuota.canSend(stamps, now, signedIn: signedIn)) {
      return kTranyxAssistantQuotaRefusal;
    }

    final config = currentFirebaseConfig;
    final readAppCheck = appCheck ?? getAppCheckTokenJs;
    final client = httpClient ?? http.Client();
    final closeClient = httpClient == null;
    try {
      final contents = <Map<String, dynamic>>[
        for (final turn in history.take(8))
          if ((turn['content'] ?? '').trim().isNotEmpty)
            {
              'role': turn['role'] == 'assistant' || turn['role'] == 'model' ? 'model' : 'user',
              'parts': [
                {'text': turn['content']!.trim()},
              ],
            },
        {
          'role': 'user',
          'parts': [
            {'text': message.trim()},
          ],
        },
      ];
      final body = jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': kTranyxAssistantSystemInstruction},
          ],
        },
        'contents': contents,
        'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 512, 'topP': 0.9},
      });
      var appCheckToken = await readAppCheck(config.toMap(), tranyxAppCheckSiteKey);
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await client.post(
            endpoint(config.projectId),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': config.apiKey,
              if (appCheckToken != null && appCheckToken.isNotEmpty) 'X-Firebase-AppCheck': appCheckToken,
              if (idToken != null && idToken.isNotEmpty) 'Authorization': 'Firebase $idToken',
            },
            body: body,
          );
          if (response.statusCode == 200) {
            final decoded = jsonDecode(response.body);
            final text = _firstText(decoded);
            final clean = TranyxTopicGuard.sanitizeReply(text);
            _writeStamps(userKey, [...TranyxAssistantQuota.prune(stamps, now), now]);
            return clean;
          }
          final missing = appCheckToken == null || appCheckToken.isEmpty ? ' appCheck=missing' : '';
          log('${failureLog(response.statusCode, response.body)}$missing');
          if (attempt == 1 || !shouldRetry(response.statusCode)) break;
          if (response.statusCode == 401) {
            appCheckToken = await readAppCheck(config.toMap(), tranyxAppCheckSiteKey);
          }
          if (retryDelay > Duration.zero) await Future<void>.delayed(retryDelay);
        } catch (error) {
          final detail = error.toString().replaceAll(RegExp(r'https?:\/\/\S+'), '[url]');
          log('Nyx generateContent failed network ${detail.length > 180 ? detail.substring(0, 180) : detail}');
          if (attempt == 1) break;
          if (retryDelay > Duration.zero) await Future<void>.delayed(retryDelay);
        }
      }
      return unavailable;
    } finally {
      if (closeClient) client.close();
    }
  }

  String _firstText(Object? decoded) {
    if (decoded is! Map) return '';
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final content = candidates.first;
    if (content is! Map) return '';
    final parts = (content['content'] as Map?)?['parts'];
    if (parts is! List || parts.isEmpty) return '';
    final first = parts.first;
    if (first is! Map) return '';
    return first['text'] as String? ?? '';
  }

  List<int> _readStamps(String userKey) {
    try {
      final raw = readNyxHits(userKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<num>().map((n) => n.toInt()).toList();
    } catch (_) {
      return [];
    }
  }

  void _writeStamps(String userKey, List<int> stamps) {
    writeNyxHits(userKey, jsonEncode(stamps));
  }
}
