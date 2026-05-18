import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;
import 'dart:typed_data';
import 'dart:async';
import 'dart:js_interop';

// ── Phantom Wallet ────────────────────────────────────────────────────────────

JSObject? _getPhantom() {
  try {
    final p = web.window.getProperty<JSObject?>('phantom'.toJS);
    return p?.getProperty<JSObject?>('solana'.toJS);
  } catch (_) {
    return null;
  }
}

Future<String?> connectPhantomWallet() async {
  final sol = _getPhantom();
  if (sol == null) return null;
  try {
    final res = await sol.callMethod<JSPromise>('connect'.toJS).toDart;
    final pk = (res as JSObject).getProperty<JSObject>('publicKey'.toJS);
    return pk.callMethod<JSString>('toBase58'.toJS).toDart;
  } catch (_) {
    return null;
  }
}

bool isPhantomInstalled() => _getPhantom() != null;

Future<String?> getPhantomPublicKeyIfConnected() async {
  final sol = _getPhantom();
  if (sol == null) return null;
  try {
    final opts = JSObject();
    opts.setProperty('onlyIfTrusted'.toJS, true.toJS);
    final res = await sol.callMethod<JSPromise>('connect'.toJS, opts).toDart;
    final pk = (res as JSObject).getProperty<JSObject>('publicKey'.toJS);
    return pk.callMethod<JSString>('toBase58'.toJS).toDart;
  } catch (_) {
    return null;
  }
}

// ── Google Sign In ────────────────────────────────────────────────────────────

Future<String?> signInWithGoogleJs(Map<String, String> config) async {
  try {
    final jsConfig = JSObject();
    for (final e in config.entries) {
      jsConfig.setProperty(e.key.toJS, e.value.toJS);
    }
    final res = await web.window.callMethod<JSPromise>('signInWithGoogle'.toJS, jsConfig).toDart;
    return (res as JSString).toDart;
  } catch (_) {
    return null;
  }
}

// ── Solana balance ────────────────────────────────────────────────────────────

Future<double?> getSolanaBalance(String publicKey) async {
  try {
    const rpc = 'https://api.mainnet-beta.solana.com';
    final body = '{"jsonrpc":"2.0","id":1,"method":"getBalance","params":["$publicKey"]}';
    final headers = web.Headers();
    headers.set('Content-Type', 'application/json');
    final opts = web.RequestInit(method: 'POST', body: body.toJS, headers: headers);
    final resp = await web.window.fetch(rpc.toJS, opts).toDart;
    final json = await resp.json().toDart;
    final result = (json as JSObject).getProperty<JSObject>('result'.toJS);
    return result.getProperty<JSNumber>('value'.toJS).toDartInt / 1e9;
  } catch (_) {
    return null;
  }
}

// ── Session Storage ───────────────────────────────────────────────────────────

class SessionStorage {
  static const _uid = 'tranyx_uid';
  static const _tok = 'tranyx_token';
  static const _ref = 'tranyx_refresh';
  static const _nam = 'tranyx_name';
  static const _eml = 'tranyx_email';
  static const _act = 'tranyx_account_type';

  static void save(dynamic auth) {
    web.window.localStorage.setItem(_uid, auth.uid as String);
    web.window.localStorage.setItem(_tok, auth.idToken as String);
    if (auth.refreshToken != null) web.window.localStorage.setItem(_ref, auth.refreshToken as String);
    if (auth.displayName != null) web.window.localStorage.setItem(_nam, auth.displayName as String);
    if (auth.email != null) web.window.localStorage.setItem(_eml, auth.email as String);
  }

  static void saveProfile({String? name, String? email, String? accountType}) {
    if (name != null) web.window.localStorage.setItem(_nam, name);
    if (email != null) web.window.localStorage.setItem(_eml, email);
    if (accountType != null) web.window.localStorage.setItem(_act, accountType);
  }

  static String? get uid => web.window.localStorage.getItem(_uid);
  static String? get idToken => web.window.localStorage.getItem(_tok);
  static String? get refreshToken => web.window.localStorage.getItem(_ref);
  static String? get displayName => web.window.localStorage.getItem(_nam);
  static String? get email => web.window.localStorage.getItem(_eml);
  static String? get accountType => web.window.localStorage.getItem(_act);
  static bool get hasSession => uid != null && idToken != null;

  static void clear() {
    for (final k in [_uid, _tok, _ref, _nam, _eml, _act]) {
      web.window.localStorage.removeItem(k);
    }
  }

  static void updateIdToken(String token) {
    web.window.localStorage.setItem(_tok, token);
  }
}

String getHostname() => web.window.location.hostname;

// ── File reading ──────────────────────────────────────────────────────────────

class WebFile {
  final String name;
  final Uint8List bytes;
  WebFile(this.name, this.bytes);
}

Future<List<WebFile>> readFilesFromEvent(dynamic event) async {
  try {
    final e = event as web.Event;
    final target = e.target as web.HTMLInputElement?;
    if (target == null) return [];
    final files = target.files;
    if (files == null || files.length == 0) return [];
    final result = <WebFile>[];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;
      final completer = Completer<Uint8List>();
      final reader = web.FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoadEnd.listen((_) {
        try {
          completer.complete((reader.result as JSArrayBuffer).toDart.asUint8List());
        } catch (err) {
          completer.completeError(err);
        }
      });
      result.add(WebFile(file.name, await completer.future));
    }
    return result;
  } catch (_) {
    return [];
  }
}

void openUrl(String url) => web.window.open(url, '_blank');
