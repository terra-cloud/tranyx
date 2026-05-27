import 'dart:js_interop_unsafe';
import 'dart:convert';

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

Future<void> signInWithEmailAndPasswordJs(Map<String, String> config, String email, String password) async {
  try {
    final jsConfig = JSObject();
    for (final e in config.entries) {
      jsConfig.setProperty(e.key.toJS, e.value.toJS);
    }
    await web.window.callMethod<JSPromise>(
      'signInWithEmailAndPasswordJs'.toJS,
      jsConfig,
      email.toJS,
      password.toJS,
    ).toDart;
  } catch (_) {}
}

Future<void> signOutJs() async {
  try {
    await web.window.callMethod<JSPromise>('signOutJs'.toJS).toDart;
  } catch (_) {}
}

void initFirebaseJs(Map<String, dynamic> config) {
  try {
    final jsConfig = JSObject();
    for (final e in config.entries) {
      final val = e.value;
      if (val is String) {
        jsConfig.setProperty(e.key.toJS, val.toJS);
      } else if (val is num) {
        jsConfig.setProperty(e.key.toJS, val.toJS);
      } else if (val is bool) {
        jsConfig.setProperty(e.key.toJS, val.toJS);
      }
    }
    web.window.callMethod('initFirebase'.toJS, jsConfig);
  } catch (_) {}
}

// ── Notifications ────────────────────────────────────────────────────────────

JSFunction? _notificationUnsub;

void listenToNotificationsJs(String uid, void Function(String) callback) {
  try {
    _notificationUnsub?.callAsFunction();
    final cb = callback.toJS;
    final unsub = web.window.callMethod<JSFunction>('listenToNotifications'.toJS, uid.toJS, cb);
    _notificationUnsub = unsub;
  } catch (_) {}
}

void markNotificationReadJs(String notifId) {
  try {
    web.window.callMethod('markNotificationRead'.toJS, notifId.toJS);
  } catch (_) {}
}

// ── Solana balance ────────────────────────────────────────────────────────────

String getSolanaRpcUrl() {
  const env = String.fromEnvironment('ENV', defaultValue: 'dev');
  if (env == 'prod') {
    return 'https://rpc.ankr.com/solana';
  } else {
    // Both dev and uat environments point to Devnet where faucet SOL is active
    return 'https://api.devnet.solana.com';
  }
}

String getUsdtMintAddress() {
  const env = String.fromEnvironment('ENV', defaultValue: 'dev');
  if (env == 'prod') {
    return 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB';
  } else {
    return 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB';
  }
}



@JS('JSON.stringify')
external JSString _jsStringify(JSAny? obj);

Future<List<Map<String, dynamic>>?> getSolanaTokenCollectibles(String publicKey) async {
  try {
    final rpc = getSolanaRpcUrl();
    final headers = web.Headers();
    headers.set('Content-Type', 'application/json');

    // 1. Legacy Token accounts
    final bodyLegacy = jsonEncode({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "getTokenAccountsByOwner",
      "params": [
        publicKey,
        {"programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"},
        {"encoding": "jsonParsed"}
      ]
    });
    final optsLegacy = web.RequestInit(method: 'POST', body: bodyLegacy.toJS, headers: headers);
    final respLegacy = await web.window.fetch(rpc.toJS, optsLegacy).toDart;
    final jsonLegacy = await respLegacy.json().toDart;
    final jsonStrLegacy = _jsStringify(jsonLegacy).toDart;
    final decodedLegacy = jsonDecode(jsonStrLegacy) as Map<String, dynamic>;

    // 2. Token-2022 accounts
    final body2022 = jsonEncode({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "getTokenAccountsByOwner",
      "params": [
        publicKey,
        {"programId": "TokenzQdBNbMcHuCxQC6YYeeTJHGDLXci3jTF5tk726V"},
        {"encoding": "jsonParsed"}
      ]
    });
    final opts2022 = web.RequestInit(method: 'POST', body: body2022.toJS, headers: headers);
    final resp2022 = await web.window.fetch(rpc.toJS, opts2022).toDart;
    final json2022 = await resp2022.json().toDart;
    final jsonStr2022 = _jsStringify(json2022).toDart;
    final decoded2022 = jsonDecode(jsonStr2022) as Map<String, dynamic>;

    final parsedTokens = <Map<String, dynamic>>[];

    void parseAndAdd(Map<String, dynamic> decoded) {
      final result = decoded['result'] as Map<String, dynamic>?;
      if (result == null) return;
      final value = result['value'] as List<dynamic>?;
      if (value == null) return;

      for (final item in value) {
        if (item is Map<String, dynamic>) {
          final account = item['account'] as Map<String, dynamic>?;
          if (account == null) continue;
          final data = account['data'] as Map<String, dynamic>?;
          if (data == null) continue;
          final parsed = data['parsed'] as Map<String, dynamic>?;
          if (parsed == null) continue;
          final info = parsed['info'] as Map<String, dynamic>?;
          if (info == null) continue;
          
          final mint = info['mint'] as String? ?? '';
          final tokenAmount = info['tokenAmount'] as Map<String, dynamic>?;
          if (tokenAmount == null) continue;
          
          final amountStr = tokenAmount['uiAmountString'] as String? ?? '0';
          final decimals = tokenAmount['decimals'] as int? ?? 0;
          final amount = double.tryParse(amountStr) ?? 0.0;
          
          if (amount > 0) {
            parsedTokens.add({
              'mint': mint,
              'amount': amount,
              'decimals': decimals,
            });
          }
        }
      }
    }

    parseAndAdd(decodedLegacy);
    parseAndAdd(decoded2022);

    final list = <Map<String, dynamic>>[];
    await Future.wait(parsedTokens.map((token) async {
      final mint = token['mint'] as String;
      String? symbol;
      String? name;
      try {
        final promise = web.window.callMethod<JSPromise>(
          'getTokenMetadata'.toJS,
          mint.toJS,
          rpc.toJS,
        );
        final res = await promise.toDart;
        if (res != null) {
          final resStr = (res as JSString).toDart;
          final meta = jsonDecode(resStr) as Map<String, dynamic>;
          symbol = meta['symbol'] as String?;
          name = meta['name'] as String?;
        }
      } catch (_) {}

      list.add({
        'mint': mint,
        'amount': token['amount'],
        'decimals': token['decimals'],
        'symbol': symbol ?? '',
        'name': name ?? '',
      });
    }));

    return list;
  } catch (_) {
    return null;
  }
}

Future<String?> connectEthereumWallet() async {
  try {
    final res = await web.window.callMethod<JSPromise>('connectEthereumWallet'.toJS).toDart;
    if (res == null) return null;
    return (res as JSString).toDart;
  } catch (_) {
    return null;
  }
}

Future<String?> connectSuiWallet() async {
  try {
    final res = await web.window.callMethod<JSPromise>('connectSuiWallet'.toJS).toDart;
    if (res == null) return null;
    return (res as JSString).toDart;
  } catch (_) {
    return null;
  }
}

Future<String?> getEthereumAddressIfConnected() async {
  try {
    final res = await web.window.callMethod<JSPromise>('getEthereumAddressIfConnected'.toJS).toDart;
    if (res == null) return null;
    return (res as JSString).toDart;
  } catch (_) {
    return null;
  }
}

Future<String?> getSuiAddressIfConnected() async {
  try {
    final res = await web.window.callMethod<JSPromise>('getSuiAddressIfConnected'.toJS).toDart;
    if (res == null) return null;
    return (res as JSString).toDart;
  } catch (_) {
    return null;
  }
}

String getEthereumRpcUrl() {
  const env = String.fromEnvironment('ENV', defaultValue: 'dev');
  if (env == 'prod') {
    return 'https://rpc.ankr.com/eth';
  } else {
    return 'https://rpc.ankr.com/eth_sepolia';
  }
}

String getSuiRpcUrl() {
  const env = String.fromEnvironment('ENV', defaultValue: 'dev');
  if (env == 'prod') {
    return 'https://fullnode.mainnet.sui.io';
  } else {
    return 'https://fullnode.testnet.sui.io';
  }
}

Future<double?> getEthereumBalance(String address) async {
  try {
    final rpc = getEthereumRpcUrl();
    final body = jsonEncode({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "eth_getBalance",
      "params": [address, "latest"]
    });
    final headers = web.Headers();
    headers.set('Content-Type', 'application/json');
    final opts = web.RequestInit(method: 'POST', body: body.toJS, headers: headers);
    final resp = await web.window.fetch(rpc.toJS, opts).toDart;
    final json = await resp.json().toDart;
    final jsonStr = _jsStringify(json).toDart;
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final result = decoded['result'] as String?;
    if (result == null) return 0.0;
    final cleanHex = result.startsWith('0x') ? result.substring(2) : result;
    final wei = BigInt.parse(cleanHex, radix: 16);
    return wei.toDouble() / 1e18;
  } catch (_) {
    return null;
  }
}

Future<double?> getSuiBalance(String address) async {
  try {
    final rpc = getSuiRpcUrl();
    final body = jsonEncode({
      "jsonrpc": "2.0",
      "id": 1,
      "method": "suix_getBalance",
      "params": [address, "0x2::sui::SUI"]
    });
    final headers = web.Headers();
    headers.set('Content-Type', 'application/json');
    final opts = web.RequestInit(method: 'POST', body: body.toJS, headers: headers);
    final resp = await web.window.fetch(rpc.toJS, opts).toDart;
    final json = await resp.json().toDart;
    final jsonStr = _jsStringify(json).toDart;
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final result = decoded['result'] as Map<String, dynamic>?;
    if (result == null) return 0.0;
    final totalBalance = result['totalBalance'] as String?;
    if (totalBalance == null) return 0.0;
    final mist = double.tryParse(totalBalance) ?? 0.0;
    return mist / 1e9;
  } catch (_) {
    return null;
  }
}

Future<double?> getSolanaBalance(String publicKey) async {
  try {
    final rpc = getSolanaRpcUrl();
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

Future<String?> sendSolanaPayment(String fromAddress, String toAddress, double amountInSol) async {
  try {
    final rpcUrl = getSolanaRpcUrl();
    final res = await web.window
        .callMethod<JSPromise>(
          'sendSolPayment'.toJS,
          fromAddress.toJS,
          toAddress.toJS,
          amountInSol.toJS,
          rpcUrl.toJS,
        )
        .toDart;
    return (res as JSString).toDart;
  } catch (e) {
    print("sendSolanaPayment exception: $e");
    rethrow;
  }
}

Future<String?> sendUsdtPayment(String fromAddress, String toAddress, double amountInUsdt, {String? usdtMint}) async {
  try {
    final rpcUrl = getSolanaRpcUrl();
    final mint = usdtMint ?? getUsdtMintAddress();
    final promise = web.window.callMethodVarArgs(
      'sendUsdtPayment'.toJS,
      [
        fromAddress.toJS,
        toAddress.toJS,
        amountInUsdt.toJS,
        rpcUrl.toJS,
        mint.toJS,
      ],
    ) as JSPromise;
    final res = await promise.toDart;
    return (res as JSString).toDart;
  } catch (e) {
    print("sendUsdtPayment exception: $e");
    rethrow;
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
  static const _qrJobId = 'tranyx_pending_qr_job_id';
  static const _qrCode = 'tranyx_pending_qr_code';

  static const _xenditInvoiceId = 'tranyx_pending_xendit_invoice_id';
  static const _xenditInvoiceAmount = 'tranyx_pending_xendit_invoice_amount';
  static const _pendingPropertyBooking = 'tranyx_pending_property_booking';
  static const _pendingVehicleBooking = 'tranyx_pending_vehicle_booking';
  static const _pendingJobId = 'tranyx_pending_job_id';
  static const _pendingApplicantData = 'tranyx_pending_applicant_data';
  static const _locationBuffer = 'tranyx_offline_location_buffer';

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

  static String? get pendingQrJobId => web.window.localStorage.getItem(_qrJobId);
  static set pendingQrJobId(String? val) {
    if (val != null) {
      web.window.localStorage.setItem(_qrJobId, val);
    } else {
      web.window.localStorage.removeItem(_qrJobId);
    }
  }

  static String? get pendingQrCode => web.window.localStorage.getItem(_qrCode);
  static set pendingQrCode(String? val) {
    if (val != null) {
      web.window.localStorage.setItem(_qrCode, val);
    } else {
      web.window.localStorage.removeItem(_qrCode);
    }
  }

  static String? get pendingXenditInvoiceId => web.window.localStorage.getItem(_xenditInvoiceId);
  static set pendingXenditInvoiceId(String? val) {
    if (val != null) {
      web.window.localStorage.setItem(_xenditInvoiceId, val);
    } else {
      web.window.localStorage.removeItem(_xenditInvoiceId);
    }
  }

  static double get pendingXenditInvoiceAmount {
    final s = web.window.localStorage.getItem(_xenditInvoiceAmount);
    return s != null ? (double.tryParse(s) ?? 0.0) : 0.0;
  }

  static set pendingXenditInvoiceAmount(double val) {
    web.window.localStorage.setItem(_xenditInvoiceAmount, val.toString());
  }

  static Map<String, dynamic>? get pendingPropertyBookingData {
    final s = web.window.localStorage.getItem(_pendingPropertyBooking);
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static set pendingPropertyBookingData(Map<String, dynamic>? val) {
    if (val != null) {
      web.window.localStorage.setItem(_pendingPropertyBooking, jsonEncode(val));
    } else {
      web.window.localStorage.removeItem(_pendingPropertyBooking);
    }
  }

  static Map<String, dynamic>? get pendingVehicleBookingData {
    final s = web.window.localStorage.getItem(_pendingVehicleBooking);
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static set pendingVehicleBookingData(Map<String, dynamic>? val) {
    if (val != null) {
      web.window.localStorage.setItem(_pendingVehicleBooking, jsonEncode(val));
    } else {
      web.window.localStorage.removeItem(_pendingVehicleBooking);
    }
  }

  static String? get pendingJobId => web.window.localStorage.getItem(_pendingJobId);
  static set pendingJobId(String? val) {
    if (val != null) {
      web.window.localStorage.setItem(_pendingJobId, val);
    } else {
      web.window.localStorage.removeItem(_pendingJobId);
    }
  }

  static Map<String, dynamic>? get pendingApplicantData {
    final s = web.window.localStorage.getItem(_pendingApplicantData);
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static set pendingApplicantData(Map<String, dynamic>? val) {
    if (val != null) {
      web.window.localStorage.setItem(_pendingApplicantData, jsonEncode(val));
    } else {
      web.window.localStorage.removeItem(_pendingApplicantData);
    }
  }

  static void clear() {
    for (final k in [
      _uid,
      _tok,
      _ref,
      _nam,
      _eml,
      _act,
      _xenditInvoiceId,
      _xenditInvoiceAmount,
      _pendingPropertyBooking,
      _pendingVehicleBooking,
      _pendingJobId,
      _pendingApplicantData,
    ]) {
      web.window.localStorage.removeItem(k);
    }
  }

  static void updateIdToken(String token) {
    web.window.localStorage.setItem(_tok, token);
  }

  static String? get offlineLocationBuffer => web.window.localStorage.getItem(_locationBuffer);
  static set offlineLocationBuffer(String? val) {
    if (val != null) {
      web.window.localStorage.setItem(_locationBuffer, val);
    } else {
      web.window.localStorage.removeItem(_locationBuffer);
    }
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
    final targetObj = e.target as JSObject?;
    if (targetObj == null) return [];
    if (!targetObj.hasProperty('files'.toJS).toDart) return [];
    final filesObj = targetObj.getProperty<JSObject?>('files'.toJS);
    if (filesObj == null) return [];
    if (!filesObj.hasProperty('length'.toJS).toDart) return [];
    final length = (filesObj.getProperty('length'.toJS) as JSNumber).toDartInt;
    if (length == 0) return [];
    final result = <WebFile>[];
    for (var i = 0; i < length; i++) {
      final fileObj = filesObj.callMethod<JSObject?>('item'.toJS, i.toJS);
      if (fileObj == null) continue;
      final name = (fileObj.getProperty('name'.toJS) as JSString).toDart;
      final completer = Completer<Uint8List>();
      final reader = web.FileReader();
      reader.readAsArrayBuffer(fileObj as web.Blob);
      reader.onLoadEnd.listen((_) {
        try {
          final jsBuffer = reader.result as JSArrayBuffer;
          final jsUint8Array = JSUint8Array(jsBuffer);
          completer.complete(jsUint8Array.toDart);
        } catch (err) {
          completer.completeError(err);
        }
      });
      result.add(WebFile(name, await completer.future));
    }
    return result;
  } catch (_) {
    return [];
  }
}

void openUrl(String url) => web.window.open(url, '_blank');

bool confirmDialog(String message) {
  return web.window.confirm(message);
}

JSFunction? _jobsUnsub;

void listenToJobsJs(String uid, void Function(String) callback) {
  try {
    _jobsUnsub?.callAsFunction();
    final cb = callback.toJS;
    final unsub = web.window.callMethod<JSFunction>('listenToJobs'.toJS, uid.toJS, cb);
    _jobsUnsub = unsub;
  } catch (_) {}
}

void stopListeningToJobsJs() {
  try {
    _jobsUnsub?.callAsFunction();
    _jobsUnsub = null;
  } catch (_) {}
}

// ── Chat Interop ─────────────────────────────────────────────────────────────

void listenToChatJs(String chatId, void Function(String) callback) {
  try {
    final cb = callback.toJS;
    web.window.callMethod('listenToChat'.toJS, chatId.toJS, cb);
  } catch (_) {}
}

void unlistenChatJs(String chatId) {
  try {
    web.window.callMethod('unlistenChat'.toJS, chatId.toJS);
  } catch (_) {}
}

String sendChatMessageJs(String chatId, String senderId, String senderName, String text, {String? photoUrl}) {
  try {
    final msgObj = JSObject();
    msgObj.setProperty('senderId'.toJS, senderId.toJS);
    msgObj.setProperty('senderName'.toJS, senderName.toJS);
    msgObj.setProperty('text'.toJS, text.toJS);
    msgObj.setProperty('photoUrl'.toJS, (photoUrl ?? '').toJS);

    final result = web.window.callMethod<JSString>(
      'sendChatMessage'.toJS,
      chatId.toJS,
      msgObj,
    );
    return result.toDart;
  } catch (_) {
    return 'error';
  }
}

Future<String?> uploadChatPhotoJs(String chatId, String base64Data, String mimeType) async {
  try {
    final result = await web.window
        .callMethod<JSPromise>(
          'uploadChatPhoto'.toJS,
          chatId.toJS,
          base64Data.toJS,
          mimeType.toJS,
        )
        .toDart;
    if (result == null) return null;
    return (result as JSString).toDart;
  } catch (_) {
    return null;
  }
}

JSFunction? _jobDetailsUnsub;

void listenToJobDetailsJs(String jobId, void Function(String) callback) {
  try {
    _jobDetailsUnsub?.callAsFunction();
    final cb = callback.toJS;
    final unsub = web.window.callMethod<JSFunction>('listenToJobDetails'.toJS, jobId.toJS, cb);
    _jobDetailsUnsub = unsub;
  } catch (_) {}
}

void stopListeningToJobDetailsJs() {
  try {
    _jobDetailsUnsub?.callAsFunction();
    _jobDetailsUnsub = null;
  } catch (_) {}
}

JSFunction? _rentalsUnsub;

void listenToRentalsJs(void Function(String) callback) {
  try {
    _rentalsUnsub?.callAsFunction();
    final cb = callback.toJS;
    final unsub = web.window.callMethod<JSFunction>('listenToRentals'.toJS, cb);
    _rentalsUnsub = unsub;
  } catch (_) {}
}

void stopListeningToRentalsJs() {
  try {
    _rentalsUnsub?.callAsFunction();
    _rentalsUnsub = null;
  } catch (_) {}
}

JSFunction? _rentalDetailsUnsub;

void listenToRentalDetailsJs(String rentalId, void Function(String) callback) {
  try {
    _rentalDetailsUnsub?.callAsFunction();
    final cb = callback.toJS;
    final unsub = web.window.callMethod<JSFunction>('listenToRentalDetails'.toJS, rentalId.toJS, cb);
    _rentalDetailsUnsub = unsub;
  } catch (_) {}
}

void stopListeningToRentalDetailsJs() {
  try {
    _rentalDetailsUnsub?.callAsFunction();
    _rentalDetailsUnsub = null;
  } catch (_) {}
}

// ── Signature Pad ─────────────────────────────────────────────────────────────

void initSignaturePadJs(String canvasId) {
  try {
    web.window.callMethod('initSignaturePad'.toJS, canvasId.toJS);
  } catch (_) {}
}

void clearSignaturePadJs(String canvasId) {
  try {
    web.window.callMethod('clearSignaturePad'.toJS, canvasId.toJS);
  } catch (_) {}
}

bool isSignaturePadEmptyJs(String canvasId) {
  try {
    final result = web.window.callMethod<JSBoolean>('isSignaturePadEmpty'.toJS, canvasId.toJS);
    return result.toDart;
  } catch (_) {
    return true;
  }
}

String getSignatureDataUrlJs(String canvasId) {
  try {
    final result = web.window.callMethod<JSString>('getSignatureDataUrl'.toJS, canvasId.toJS);
    return result.toDart;
  } catch (_) {
    return '';
  }
}

// ── Rental Q&A Interop ────────────────────────────────────────────────────────

void listenToRentalQAJs(String rentalId, void Function(String) callback) {
  try {
    final cb = callback.toJS;
    web.window.callMethod('listenToRentalQA'.toJS, rentalId.toJS, cb);
  } catch (_) {}
}

void unlistenRentalQAJs(String rentalId) {
  try {
    web.window.callMethod('unlistenRentalQA'.toJS, rentalId.toJS);
  } catch (_) {}
}

void postRentalQuestionJs(String rentalId, String uid, String name, String photoUrl, String text) {
  try {
    web.window.callMethodVarArgs(
      'postRentalQuestion'.toJS,
      [rentalId.toJS, uid.toJS, name.toJS, photoUrl.toJS, text.toJS],
    );
  } catch (_) {}
}

void answerRentalQuestionJs(String rentalId, String questionId, String answerText) {
  try {
    web.window.callMethod(
      'answerRentalQuestion'.toJS,
      rentalId.toJS,
      questionId.toJS,
      answerText.toJS,
    );
  } catch (_) {}
}

// ── Property Q&A Interop ────────────────────────────────────────────────────────

void listenToPropertyQAJs(String propertyId, void Function(String) callback) {
  try {
    final cb = callback.toJS;
    web.window.callMethod('listenToPropertyQA'.toJS, propertyId.toJS, cb);
  } catch (_) {}
}

void unlistenPropertyQAJs(String propertyId) {
  try {
    web.window.callMethod('unlistenPropertyQA'.toJS, propertyId.toJS);
  } catch (_) {}
}

void postPropertyQuestionJs(String propertyId, String uid, String name, String photoUrl, String text) {
  try {
    web.window.callMethodVarArgs(
      'postPropertyQuestion'.toJS,
      [propertyId.toJS, uid.toJS, name.toJS, photoUrl.toJS, text.toJS],
    );
  } catch (_) {}
}

void answerPropertyQuestionJs(String propertyId, String questionId, String answerText) {
  try {
    web.window.callMethod(
      'answerPropertyQuestion'.toJS,
      propertyId.toJS,
      questionId.toJS,
      answerText.toJS,
    );
  } catch (_) {}
}

// ── Properties List Interop ──────────────────────────────────────────────────

JSFunction? _propertiesUnsub;

void listenToPropertiesJs(void Function(String) callback) {
  try {
    _propertiesUnsub?.callAsFunction();
    final cb = callback.toJS;
    final unsub = web.window.callMethod<JSFunction>('listenToProperties'.toJS, cb);
    _propertiesUnsub = unsub;
  } catch (_) {}
}

void stopListeningToPropertiesJs() {
  try {
    _propertiesUnsub?.callAsFunction();
    _propertiesUnsub = null;
  } catch (_) {}
}

JSFunction? _propertyDetailsUnsub;

void listenToPropertyDetailsJs(String propertyId, void Function(String) callback) {
  try {
    _propertyDetailsUnsub?.callAsFunction();
    final cb = callback.toJS;
    final unsub = web.window.callMethod<JSFunction>('listenToPropertyDetails'.toJS, propertyId.toJS, cb);
    _propertyDetailsUnsub = unsub;
  } catch (_) {}
}

void stopListeningToPropertyDetailsJs() {
  try {
    _propertyDetailsUnsub?.callAsFunction();
    _propertyDetailsUnsub = null;
  } catch (_) {}
}

String getUrlOrigin() => web.window.location.origin;

Map<String, String> getUrlQueryParams() {
  try {
    final href = web.window.location.href;
    final queryStart = href.indexOf('?');
    if (queryStart != -1) {
      final queryString = href.substring(queryStart + 1);
      final cleanQuery = queryString.contains('#') ? queryString.substring(0, queryString.indexOf('#')) : queryString;
      return Uri.splitQueryString(cleanQuery);
    }
    return const {};
  } catch (_) {
    return const {};
  }
}

void clearUrlParams() {
  try {
    final href = web.window.location.href;
    final queryStart = href.indexOf('?');
    if (queryStart != -1) {
      final newUrl = href.substring(0, queryStart);
      web.window.history.replaceState(null, '', newUrl);
    }
  } catch (_) {}
}

String getInputValue(dynamic target) {
  if (target == null) return '';
  try {
    final jsObj = target as JSAny?;
    if (jsObj != null && jsObj.isA<JSObject>()) {
      final obj = jsObj as JSObject;
      if (obj.hasProperty('value'.toJS).toDart) {
        final val = obj.getProperty('value'.toJS);
        if (val.isA<JSString>()) {
          return (val as JSString).toDart;
        }
        return val.toString();
      }
    }
  } catch (_) {}
  return '';
}

void setInputValue(dynamic target, String value) {
  if (target == null) return;
  try {
    final jsObj = target as JSAny?;
    if (jsObj != null && jsObj.isA<JSObject>()) {
      (jsObj as JSObject).setProperty('value'.toJS, value.toJS);
    }
  } catch (_) {}
}

bool getInputChecked(dynamic target) {
  if (target == null) return false;
  try {
    final jsObj = target as JSAny?;
    if (jsObj != null && jsObj.isA<JSObject>()) {
      final obj = jsObj as JSObject;
      if (obj.hasProperty('checked'.toJS).toDart) {
        final val = obj.getProperty('checked'.toJS);
        if (val.isA<JSBoolean>()) {
          return (val as JSBoolean).toDart;
        }
      }
    }
  } catch (_) {}
  return false;
}

void setInputChecked(dynamic target, bool checked) {
  if (target == null) return;
  try {
    final jsObj = target as JSAny?;
    if (jsObj != null && jsObj.isA<JSObject>()) {
      (jsObj as JSObject).setProperty('checked'.toJS, checked.toJS);
    }
  } catch (_) {}
}
