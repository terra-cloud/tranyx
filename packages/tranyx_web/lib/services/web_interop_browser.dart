import 'package:web/web.dart' as web;
import 'dart:typed_data';
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// ── Phantom Wallet JS Interop ─────────────────────────────────────────────────

/// Returns the Phantom `window.phantom.solana` JSObject if Phantom is installed.
JSObject? _getPhantom() {
  try {
    final phantom = web.window.getProperty<JSObject?>('phantom'.toJS);
    if (phantom == null) return null;
    return phantom.getProperty<JSObject?>('solana'.toJS);
  } catch (_) {
    return null;
  }
}

/// Connects to Phantom wallet and returns the wallet public key (base58 string).
/// Returns null if Phantom is not installed or the user rejects the connection.
Future<String?> connectPhantomWallet() async {
  final solana = _getPhantom();
  if (solana == null) return null;

  try {
    final promise = solana.callMethod<JSPromise>('connect'.toJS);
    final result = await promise.toDart;
    final resultObj = result as JSObject;
    final publicKeyObj = resultObj.getProperty<JSObject>('publicKey'.toJS);
    final base58 = publicKeyObj.callMethod<JSString>('toBase58'.toJS);
    return base58.toDart;
  } catch (_) {
    return null;
  }
}

/// Returns true if Phantom Wallet extension is installed in the browser.
bool isPhantomInstalled() => _getPhantom() != null;

/// Returns the already-connected wallet public key without prompting.
/// Uses `connect({ onlyIfTrusted: true })` so it never shows a popup.
Future<String?> getPhantomPublicKeyIfConnected() async {
  final solana = _getPhantom();
  if (solana == null) return null;
  try {
    // Build { onlyIfTrusted: true } JS object
    final opts = JSObject();
    opts.setProperty('onlyIfTrusted'.toJS, true.toJS);
    final promise = solana.callMethod<JSPromise>('connect'.toJS, opts);
    final result = await promise.toDart;
    final resultObj = result as JSObject;
    final publicKeyObj = resultObj.getProperty<JSObject>('publicKey'.toJS);
    final base58 = publicKeyObj.callMethod<JSString>('toBase58'.toJS);
    return base58.toDart;
  } catch (_) {
    return null; // Not trusted yet — user hasn't connected before
  }
}

// ── Google Sign In JS Interop ──────────────────────────────────────────────────

Future<String?> signInWithGoogleJs(Map<String, String> config) async {
  try {
    final jsConfig = JSObject();
    for (final e in config.entries) {
      jsConfig.setProperty(e.key.toJS, e.value.toJS);
    }
    final promise = web.window.callMethod<JSPromise>('signInWithGoogle'.toJS, jsConfig);
    final result = await promise.toDart;
    return (result as JSString).toDart;
  } catch (e) {
    return null;
  }
}

/// Fetches the SOL balance for a given Solana public key via the public Mainnet RPC.
/// Returns the balance in SOL (lamports / 1e9), or null on failure.
Future<double?> getSolanaBalance(String publicKey) async {
  try {
    const rpcUrl = 'https://api.mainnet-beta.solana.com';
    final body = '{"jsonrpc":"2.0","id":1,"method":"getBalance","params":["$publicKey"]}';

    final headers = JSObject();
    headers.setProperty('Content-Type'.toJS, 'application/json'.toJS);

    final fetchOpts = JSObject();
    fetchOpts.setProperty('method'.toJS, 'POST'.toJS);
    fetchOpts.setProperty('headers'.toJS, headers);
    fetchOpts.setProperty('body'.toJS, body.toJS);

    final fetchFn = web.window.getProperty<JSFunction>('fetch'.toJS);
    final response = await (fetchFn.callAsFunction(null, rpcUrl.toJS, fetchOpts) as JSPromise).toDart;
    final responseObj = response as JSObject;
    final jsonFn = responseObj.getProperty<JSFunction>('json'.toJS);
    final jsonResult = await (jsonFn.callAsFunction(responseObj) as JSPromise).toDart;
    final jsonObj = jsonResult as JSObject;
    final resultProp = jsonObj.getProperty<JSObject>('result'.toJS);
    final lamports = resultProp.getProperty<JSNumber>('value'.toJS).toDartInt;
    return lamports / 1000000000.0; // convert lamports → SOL
  } catch (_) {
    return null;
  }
}

class SessionStorage {
  static const _uidKey = 'tranyx_uid';
  static const _tokenKey = 'tranyx_token';
  static const _refreshKey = 'tranyx_refresh';
  static const _nameKey = 'tranyx_name';
  static const _emailKey = 'tranyx_email';
  static const _accountTypeKey = 'tranyx_account_type';

  static void save(dynamic auth) {
    web.window.localStorage.setItem(_uidKey, auth.uid as String);
    web.window.localStorage.setItem(_tokenKey, auth.idToken as String);
    if (auth.refreshToken != null) {
      web.window.localStorage.setItem(_refreshKey, auth.refreshToken as String);
    }
    if (auth.displayName != null) {
      web.window.localStorage.setItem(_nameKey, auth.displayName as String);
    }
    if (auth.email != null) {
      web.window.localStorage.setItem(_emailKey, auth.email as String);
    }
  }

  static void saveProfile({String? name, String? email, String? accountType}) {
    if (name != null) web.window.localStorage.setItem(_nameKey, name);
    if (email != null) web.window.localStorage.setItem(_emailKey, email);
    if (accountType != null) web.window.localStorage.setItem(_accountTypeKey, accountType);
  }

  static String? get uid => web.window.localStorage.getItem(_uidKey);
  static String? get idToken => web.window.localStorage.getItem(_tokenKey);
  static String? get refreshToken => web.window.localStorage.getItem(_refreshKey);
  static String? get displayName => web.window.localStorage.getItem(_nameKey);
  static String? get email => web.window.localStorage.getItem(_emailKey);
  static String? get accountType => web.window.localStorage.getItem(_accountTypeKey);

  static bool get hasSession =>
      web.window.localStorage.getItem(_uidKey) != null && web.window.localStorage.getItem(_tokenKey) != null;

  static void clear() {
    web.window.localStorage.removeItem(_uidKey);
    web.window.localStorage.removeItem(_tokenKey);
    web.window.localStorage.removeItem(_refreshKey);
    web.window.localStorage.removeItem(_nameKey);
    web.window.localStorage.removeItem(_emailKey);
    web.window.localStorage.removeItem(_accountTypeKey);
  }
}

String getHostname() => web.window.location.hostname;

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
    for (int i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;

      final completer = Completer<Uint8List>();
      final reader = web.FileReader();
      reader.readAsArrayBuffer(file);

      reader.onLoadEnd.listen((_) {
        try {
          if (reader.result != null) {
            final res = reader.result as JSArrayBuffer;
            completer.complete(res.toDart.asUint8List());
          } else {
            completer.completeError('Failed to read file');
          }
        } catch (err) {
          completer.completeError(err);
        }
      });

      final bytes = await completer.future;
      result.add(WebFile(file.name, bytes));
    }

    return result;
  } catch (err, stack) {
    print('readFilesFromEvent error: $err');
    print(stack);
    return [];
  }
}

void openUrl(String url) {
  web.window.open(url, '_blank');
}
