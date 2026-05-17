# Skill: Add Firebase REST Integration (Jaspr/Dart Server-Compatible)

## Purpose
Guides an agent through adding a Firebase Auth or Firestore REST API call to the Tranyx web dashboard without any browser-only dependencies.

## Rules
1. Never `import 'dart:html'` or `package:http/browser_client.dart` directly — use conditional imports via `web_interop_stub.dart`
2. Use `http.Client()` (generic) — not `BrowserClient`
3. Firebase Auth REST base: `https://identitytoolkit.googleapis.com/v1/accounts`
4. Firestore REST base: `https://firestore.googleapis.com/v1/projects/{projectId}/databases/(default)/documents`
5. Always `client.close()` in a `finally` block
6. Decode JSON response with `json.decode(response.body)`
7. Store ID token and UID in `SessionStorage` (browser-guarded stub)

## Pattern: Auth Sign-In
```dart
Future<Map<String,dynamic>> signIn(String email, String password) async {
  final client = http.Client();
  try {
    final url = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_apiKey',
    );
    final res = await client.post(url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password, 'returnSecureToken': true}),
    );
    return json.decode(res.body) as Map<String,dynamic>;
  } finally {
    client.close();
  }
}
```

## Pattern: Firestore Write
```dart
Future<void> setDocument(String collection, String docId, Map<String,dynamic> data, String idToken) async {
  final client = http.Client();
  try {
    final url = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/$collection/$docId',
    );
    final fields = data.map((k, v) => MapEntry(k, {'stringValue': v.toString()}));
    final res = await client.patch(url,
      headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
      body: json.encode({'fields': fields}),
    );
    if (res.statusCode >= 400) throw Exception('Firestore error: ${res.body}');
  } finally {
    client.close();
  }
}
```

## SessionStorage Guard
```dart
// In web_interop_stub.dart (server side) — always returns false/empty
// In web_interop.dart (browser side) — uses window.sessionStorage
```
