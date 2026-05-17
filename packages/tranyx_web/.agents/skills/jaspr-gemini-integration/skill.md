# Skill: Integrate Gemini API (Exponential Backoff)

## Purpose
Guides an agent through calling Gemini 2.5 Flash from the Tranyx Jaspr web dashboard for AI-assisted content generation (job descriptions, cover notes).

## Endpoint
`POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={API_KEY}`

## Request Body
```json
{
  "contents": [{"parts": [{"text": "Your prompt here"}]}],
  "generationConfig": {"temperature": 0.7, "maxOutputTokens": 300}
}
```

## Full Service Pattern
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  final String _apiKey;
  GeminiService(this._apiKey);

  static const _delays = [1, 2, 4, 8, 16]; // seconds

  Future<String> generate(String prompt) async {
    for (int attempt = 0; attempt < _delays.length; attempt++) {
      try {
        final client = http.Client();
        try {
          final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey',
          );
          final res = await client.post(url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'contents': [{'parts': [{'text': prompt}]}],
              'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 300},
            }),
          );
          if (res.statusCode == 429 || res.statusCode >= 500) {
            throw Exception('Retryable: ${res.statusCode}');
          }
          final data = json.decode(res.body) as Map<String, dynamic>;
          return data['candidates'][0]['content']['parts'][0]['text'] as String;
        } finally {
          client.close();
        }
      } catch (_) {
        if (attempt == _delays.length - 1) rethrow;
        await Future.delayed(Duration(seconds: _delays[attempt]));
      }
    }
    throw Exception('Gemini unreachable after retries');
  }
}
```

## Job Description Prompt Template
```
Write a professional job description for a "${category}" role titled "${title}". 
Keep it concise (3-4 sentences), friendly, and focused on tasks and requirements.
```

## Cover Note Prompt Template
```
Write a professional cover note for a gig application as a "${category}" worker.
${isCounterOffer ? "The applicant is counter-offering at ${rate}." : ""}
Keep it warm, confident, and under 100 words.
```

## UI Integration
- Set `isGeneratingDesc = true` before call, `false` in finally
- Show `lIcon('loader-2', cls: 'w-4 h-4 animate-spin')` + `Component.text(' Generating...')` while loading
- Update `newJobDesc` or `coverNote` state field on success
