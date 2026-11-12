import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';
import 'package:web/web.dart' as web;

import 'firebase_service.dart';
import 'web_interop.dart';

/// Firebase AI Logic (Gemini Developer API through the Firebase project).
/// Uses the public Firebase web apiKey plus an App Check token. There is no Gemini API key.
class TranyxFirebaseAi {
  static const model = 'gemini-flash-latest';

  Future<String> reply({
    required String message,
    List<Map<String, String>> history = const [],
    required bool signedIn,
    String? idToken,
    int? nowMs,
    http.Client? httpClient,
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
    final appCheck = await getAppCheckTokenJs(config.toMap(), tranyxAppCheckSiteKey);
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
      final response = await client.post(
        Uri.parse(
          'https://firebasevertexai.googleapis.com/v1beta/projects/${config.projectId}'
          '/publishers/google/models/$model:generateContent',
        ),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': config.apiKey,
          if (appCheck != null && appCheck.isNotEmpty) 'X-Firebase-AppCheck': appCheck,
          if (idToken != null && idToken.isNotEmpty) 'Authorization': 'Firebase $idToken',
        },
        body: jsonEncode({
          'systemInstruction': {
            'parts': [
              {'text': kTranyxAssistantSystemInstruction},
            ],
          },
          'contents': contents,
          'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 512, 'topP': 0.9},
        }),
      );
      if (response.statusCode != 200) {
        return 'Nyx couldn’t answer just now. Please try again in a moment.';
      }
      final decoded = jsonDecode(response.body);
      final text = _firstText(decoded);
      final clean = TranyxTopicGuard.sanitizeReply(text);
      _writeStamps(userKey, [...TranyxAssistantQuota.prune(stamps, now), now]);
      return clean;
    } catch (_) {
      return 'Nyx couldn’t answer just now. Please try again in a moment.';
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
      final raw = web.window.localStorage.getItem('tranyx.nyx.hits.$userKey');
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<num>().map((n) => n.toInt()).toList();
    } catch (_) {
      return [];
    }
  }

  void _writeStamps(String userKey, List<int> stamps) {
    try {
      web.window.localStorage.setItem('tranyx.nyx.hits.$userKey', jsonEncode(stamps));
    } catch (_) {}
  }
}
