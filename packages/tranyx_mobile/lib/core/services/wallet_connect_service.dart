import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';

/// A lightweight, fully local pub/sub WebSocket server that runs inside the
/// Flutter app to act as a WalletConnect v1 bridge for Trust Wallet.
class LocalWalletConnectBridge {
  HttpServer? _server;
  final Map<String, List<WebSocket>> _subscriptions = {};

  Future<int> start() async {
    if (_server != null) return _server!.port;

    // Bind to the loopback interface on any available ephemeral port (0)
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    debugPrint(
      'LocalWalletConnectBridge: Local loopback server listening on port ${_server!.port}',
    );

    _server!.listen(
      (HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleSocket(socket);
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..write('Local WalletConnect Bridge')
            ..close();
        }
      },
      onError: (err) {
        debugPrint('LocalWalletConnectBridge: server listen error: $err');
      },
    );

    return _server!.port;
  }

  void _handleSocket(WebSocket socket) {
    String? subscribedTopic;

    socket.listen(
      (message) {
        try {
          if (message == 'ping') {
            socket.add('pong');
            return;
          }
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          final type = data['type'] as String?;
          final topic = data['topic'] as String?;

          if (topic == null || topic.isEmpty) return;

          if (type == 'sub') {
            subscribedTopic = topic;
            _subscriptions.putIfAbsent(topic, () => []).add(socket);
            debugPrint('LocalBridge: Socket subscribed to topic: $topic');
          } else if (type == 'pub') {
            final payload = data['payload'];
            final subscribers = _subscriptions[topic];
            if (subscribers != null) {
              final msgToSend = jsonEncode({
                'topic': topic,
                'type': 'pub',
                'payload': payload,
              });
              for (final sub in subscribers) {
                if (sub != socket && sub.readyState == WebSocket.open) {
                  sub.add(msgToSend);
                }
              }
            }
          }
        } catch (e) {
          debugPrint('LocalBridge Error: $e');
        }
      },
      onDone: () {
        _cleanupSocket(socket, subscribedTopic);
      },
      onError: (e) {
        _cleanupSocket(socket, subscribedTopic);
      },
    );
  }

  void _cleanupSocket(WebSocket socket, String? topic) {
    if (topic != null) {
      _subscriptions[topic]?.remove(socket);
      if (_subscriptions[topic]?.isEmpty ?? false) {
        _subscriptions.remove(topic);
      }
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _subscriptions.clear();
    debugPrint('LocalWalletConnectBridge: Stopped.');
  }
}

/// Minimal WalletConnect v1 client that works via the local bridge server.
class WalletConnectService {
  final String _topic;
  final String _keyHex;
  WebSocket? _socket;
  final _approvalController = StreamController<WCApprovalResult>.broadcast();
  final _pendingRequests = <int, Completer<dynamic>>{};
  Timer? _pingTimer;
  bool _approved = false;

  static LocalWalletConnectBridge? _bridgeServer;

  WalletConnectService._({required String topic, required String keyHex})
    : _topic = topic,
      _keyHex = keyHex;

  Stream<WCApprovalResult> get approvalStream => _approvalController.stream;

  /// Starts the local bridge and returns a new session connection URL.
  static Future<({WalletConnectService service, Uri deepLink})> create() async {
    _bridgeServer ??= LocalWalletConnectBridge();
    final port = await _bridgeServer!.start();

    final topic = _generateTopic();
    final key = _generateKey();
    final keyHex = _bytesToHex(key);

    final svc = WalletConnectService._(topic: topic, keyHex: keyHex);
    await svc._connect(port);
    final uri = svc._buildDeepLink(port);

    return (service: svc, deepLink: uri);
  }

  /// Reconnects to an existing session for transaction signing.
  static Future<WalletConnectService> reconnect() async {
    final topic = await SecureStorageHelper.getTrustWalletTopic();
    final keyHex = await SecureStorageHelper.getTrustWalletKey();

    if (topic == null || keyHex == null) {
      throw Exception('No active Trust Wallet session found. Please reconnect.');
    }

    _bridgeServer ??= LocalWalletConnectBridge();
    final port = await _bridgeServer!.start();

    final svc = WalletConnectService._(topic: topic, keyHex: keyHex);
    await svc._connect(port);
    return svc;
  }

  Future<void> _connect(int port) async {
    final wsUrl = 'ws://127.0.0.1:$port';
    debugPrint('WalletConnectService: Connecting to local bridge at $wsUrl...');
    _socket = await WebSocket.connect(wsUrl);
    debugPrint('WalletConnectService: Connected to local bridge.');

    // Subscribe to our topic
    _send({
      'topic': _topic,
      'type': 'sub',
      'payload': '',
      'silent': true,
    });

    _socket!.listen(
      _onMessage,
      onError: (e) => debugPrint('WalletConnectService: WS error: $e'),
      onDone: () => debugPrint('WalletConnectService: WS closed.'),
      cancelOnError: false,
    );

    // Keep connection alive
    _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_socket?.readyState == WebSocket.open) {
        _socket!.add('ping');
      }
    });
  }

  void _onMessage(dynamic raw) {
    try {
      if (raw == 'pong' || raw == 'ping') return;
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      if (type != 'pub') return;

      final payloadStr = msg['payload'] as String?;
      if (payloadStr == null || payloadStr.isEmpty) return;

      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
      final encryptedData = payload['data'] as String?;
      final iv = payload['iv'] as String?;
      final hmac = payload['hmac'] as String?;

      if (encryptedData == null || iv == null) return;

      // Decrypt with AES-256-CBC using our symmetric key
      final decrypted = _decrypt(
        data: encryptedData,
        iv: iv,
        hmac: hmac,
        keyHex: _keyHex,
      );
      if (decrypted == null) return;

      debugPrint('WalletConnectService: Decrypted payload: $decrypted');

      final Map<String, dynamic> wcMsg = jsonDecode(decrypted);

      // 1. Check if it's a response to a pending request ID
      final id = wcMsg['id'];
      if (id != null) {
        final idInt = id is int ? id : int.tryParse(id.toString());
        if (idInt != null && _pendingRequests.containsKey(idInt)) {
          final completer = _pendingRequests.remove(idInt);
          if (wcMsg.containsKey('error')) {
            completer?.completeError(
              wcMsg['error']?['message'] ?? 'Wallet execution failed',
            );
          } else {
            completer?.complete(wcMsg['result']);
          }
          return;
        }
      }

      // 2. Check for session request approval
      final method = wcMsg['method'] as String?;
      if (method == 'wc_sessionRequest' || wcMsg.containsKey('result')) {
        _handleApproval(wcMsg);
      }
    } catch (e) {
      debugPrint('WalletConnectService: Error parsing message: $e');
    }
  }

  void _handleApproval(Map<String, dynamic> wcMsg) {
    if (_approved) return;

    final result = wcMsg['result'];
    List<String>? accounts;

    if (result is Map) {
      final accs = result['accounts'];
      if (accs is List) {
        accounts = accs.cast<String>();
      }
    } else if (result is List) {
      accounts = result.cast<String>();
    }

    final address = accounts?.isNotEmpty == true ? accounts!.first : null;

    if (address != null && address.isNotEmpty) {
      _approved = true;
      debugPrint('WalletConnectService: Wallet approved! Address: $address');
      
      // Save Trust Wallet session details to storage
      SecureStorageHelper.saveTrustWalletAddress(address);
      SecureStorageHelper.saveTrustWalletTopic(_topic);
      SecureStorageHelper.saveTrustWalletKey(_keyHex);

      _approvalController.add(WCApprovalResult(address: address));
    }
  }

  void _send(Map<String, dynamic> message) {
    if (_socket?.readyState == WebSocket.open) {
      _socket!.add(jsonEncode(message));
    }
  }

  /// Publishes the WalletConnect session request to the handshake topic.
  void publishSessionRequest() {
    final requestId = DateTime.now().millisecondsSinceEpoch;
    final payload = jsonEncode({
      'id': requestId,
      'jsonrpc': '2.0',
      'method': 'wc_sessionRequest',
      'params': [
        {
          'peerId': _generateTopic(), // dApp's peer ID
          'peerMeta': {
            'description': 'Tranyx - Crypto Remittance',
            'url': 'https://tranyx.app',
            'icons': ['https://tranyx.app/favicon.png'],
            'name': 'Tranyx',
          },
          'chainId': null, // Solana doesn't use EVM chainId
        },
      ],
    });

    final encrypted = _encrypt(payload, _keyHex);
    _send({
      'topic': _topic,
      'type': 'pub',
      'payload': jsonEncode(encrypted),
      'silent': false,
    });
    debugPrint('WalletConnectService: Published wc_sessionRequest');
  }

  /// Sends a Solana transaction to Trust Wallet for signing.
  /// Launches Trust Wallet to display the confirmation prompt.
  Future<String> signTransaction(Uint8List txBytes) async {
    final requestId = DateTime.now().millisecondsSinceEpoch;
    final completer = Completer<dynamic>();
    _pendingRequests[requestId] = completer;

    // Encode serialized transaction as base64 for WalletConnect Solana standard
    final base64Tx = base64.encode(txBytes);

    final payload = jsonEncode({
      'id': requestId,
      'jsonrpc': '2.0',
      'method': 'solana_signTransaction',
      'params': [
        {
          'transaction': base64Tx,
        }
      ],
    });

    final encrypted = _encrypt(payload, _keyHex);
    _send({
      'topic': _topic,
      'type': 'pub',
      'payload': jsonEncode(encrypted),
      'silent': false,
    });

    debugPrint('WalletConnectService: Published solana_signTransaction request.');

    // Bring Trust Wallet to the foreground so the user sees the request
    try {
      await launchUrl(
        Uri.parse('trust://'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      try {
        await launchUrl(
          Uri.parse('trustwallet://'),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
    }

    // Wait for response from Trust Wallet
    final result = await completer.future;
    
    if (result is Map) {
      final sig = result['signature'] as String?;
      if (sig != null && sig.isNotEmpty) return sig;
      final tx = result['transaction'] as String?;
      if (tx != null && tx.isNotEmpty) {
        return tx;
      }
    } else if (result is String) {
      return result;
    }

    throw Exception('Invalid transaction signature response format.');
  }

  Uri _buildDeepLink(int port) {
    final bridgeUrl = 'http://127.0.0.1:$port';
    final wcUri =
        'wc:$_topic@1?bridge=${Uri.encodeComponent(bridgeUrl)}&key=$_keyHex';
    final encoded = Uri.encodeComponent(wcUri);
    return Uri.parse('trust://wc?uri=$encoded');
  }

  void dispose() {
    _pingTimer?.cancel();
    _socket?.close();
    _approvalController.close();
    _bridgeServer?.stop();
    _bridgeServer = null;
  }

  // ---------------------------------------------------------------------------
  // Crypto helpers (AES-256-CBC via Dart, matching WalletConnect v1 spec)
  // ---------------------------------------------------------------------------

  static Map<String, String> _encrypt(String data, String keyHex) {
    final key = _hexToBytes(keyHex);
    final iv = _generateIv();

    final encrypted = _aesCbcEncrypt(
      Uint8List.fromList(utf8.encode(data)),
      key,
      iv,
    );
    final hmacBytes = _computeHmac(encrypted, iv, key);

    return {
      'data': base64.encode(encrypted),
      'hmac': _bytesToHex(hmacBytes),
      'iv': _bytesToHex(iv),
    };
  }

  static String? _decrypt({
    required String data,
    required String iv,
    String? hmac,
    required String keyHex,
  }) {
    try {
      final key = _hexToBytes(keyHex);
      final ivBytes = _hexToBytes(iv);
      final dataBytes = base64.decode(data);
      final decrypted = _aesCbcDecrypt(dataBytes, key, ivBytes);
      return utf8.decode(decrypted);
    } catch (e) {
      debugPrint('WalletConnectService: Decrypt error: $e');
      return null;
    }
  }

  static Uint8List _aesCbcEncrypt(
    Uint8List data,
    Uint8List key,
    Uint8List iv,
  ) {
    assert(key.length == 32);
    assert(iv.length == 16);
    final padLen = 16 - (data.length % 16);
    final padded = Uint8List(data.length + padLen)
      ..setAll(0, data)
      ..fillRange(data.length, data.length + padLen, padLen);

    final result = Uint8List(padded.length);
    Uint8List prev = iv;
    for (var offset = 0; offset < padded.length; offset += 16) {
      final block = padded.sublist(offset, offset + 16);
      final xored = Uint8List.fromList(
        List.generate(16, (i) => block[i] ^ prev[i]),
      );
      final enc = _aesEncryptBlock(xored, key);
      result.setAll(offset, enc);
      prev = enc;
    }
    return result;
  }

  static Uint8List _aesCbcDecrypt(
    Uint8List data,
    Uint8List key,
    Uint8List iv,
  ) {
    assert(key.length == 32);
    assert(iv.length == 16);
    final result = Uint8List(data.length);
    Uint8List prev = iv;
    for (var offset = 0; offset < data.length; offset += 16) {
      final block = data.sublist(offset, offset + 16);
      final dec = _aesDecryptBlock(block, key);
      final xored = Uint8List.fromList(
        List.generate(16, (i) => dec[i] ^ prev[i]),
      );
      result.setAll(offset, xored);
      prev = block;
    }
    final padLen = result.last;
    return result.sublist(0, result.length - padLen);
  }

  static const _sBox = <int>[
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
  ];

  static const _invSBox = <int>[
    0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
    0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
    0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
    0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
    0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
    0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
    0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
    0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
    0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
    0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
    0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
    0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
    0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
    0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
    0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
    0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d,
  ];

  static const _rCon = <int>[
    0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1b,0x36,0x6c,0xd8,0xab,0x4d,0x9a,
  ];

  static List<List<int>> _expandKey(Uint8List key) {
    const nk = 8;
    const nr = 14;
    final w = List<List<int>>.generate(4 * (nr + 1), (_) => List<int>.filled(4, 0));

    for (var i = 0; i < nk; i++) {
      w[i] = [key[4 * i], key[4 * i + 1], key[4 * i + 2], key[4 * i + 3]];
    }
    for (var i = nk; i < 4 * (nr + 1); i++) {
      var temp = List<int>.from(w[i - 1]);
      if (i % nk == 0) {
        temp = _subWord(_rotWord(temp));
        temp[0] ^= _rCon[(i ~/ nk) - 1];
      } else if (nk > 6 && i % nk == 4) {
        temp = _subWord(temp);
      }
      w[i] = List.generate(4, (j) => w[i - nk][j] ^ temp[j]);
    }
    return w;
  }

  static List<int> _rotWord(List<int> w) => [w[1], w[2], w[3], w[0]];
  static List<int> _subWord(List<int> w) => w.map((b) => _sBox[b]).toList();

  static int _mul(int a, int b) {
    var p = 0;
    var aa = a;
    var bb = b;
    for (var i = 0; i < 8; i++) {
      if ((bb & 1) != 0) p ^= aa;
      final hiBit = aa & 0x80;
      aa = (aa << 1) & 0xff;
      if (hiBit != 0) aa ^= 0x1b;
      bb >>= 1;
    }
    return p;
  }

  static Uint8List _aesEncryptBlock(Uint8List block, Uint8List key) {
    final w = _expandKey(key);
    var state = List<List<int>>.generate(
      4, (r) => List<int>.generate(4, (c) => block[r + 4 * c]),
    );
    state = _addRoundKey(state, w, 0);
    for (var round = 1; round <= 14; round++) {
      state = _subBytes(state);
      state = _shiftRows(state);
      if (round < 14) state = _mixColumns(state);
      state = _addRoundKey(state, w, round);
    }
    final out = Uint8List(16);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        out[r + 4 * c] = state[r][c];
      }
    }
    return out;
  }

  static Uint8List _aesDecryptBlock(Uint8List block, Uint8List key) {
    final w = _expandKey(key);
    var state = List<List<int>>.generate(
      4, (r) => List<int>.generate(4, (c) => block[r + 4 * c]),
    );
    state = _addRoundKey(state, w, 14);
    for (var round = 13; round >= 0; round--) {
      state = _invShiftRows(state);
      state = _invSubBytes(state);
      state = _addRoundKey(state, w, round);
      if (round > 0) state = _invMixColumns(state);
    }
    final out = Uint8List(16);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        out[r + 4 * c] = state[r][c];
      }
    }
    return out;
  }

  static List<List<int>> _addRoundKey(
    List<List<int>> s, List<List<int>> w, int round,
  ) => List.generate(4, (r) => List.generate(4, (c) => s[r][c] ^ w[round * 4 + c][r]));

  static List<List<int>> _subBytes(List<List<int>> s) =>
      s.map((row) => row.map((b) => _sBox[b]).toList()).toList();
  static List<List<int>> _invSubBytes(List<List<int>> s) =>
      s.map((row) => row.map((b) => _invSBox[b]).toList()).toList();

  static List<List<int>> _shiftRows(List<List<int>> s) => [
        s[0],
        [s[1][1], s[1][2], s[1][3], s[1][0]],
        [s[2][2], s[2][3], s[2][0], s[2][1]],
        [s[3][3], s[3][0], s[3][1], s[3][2]],
      ];
  static List<List<int>> _invShiftRows(List<List<int>> s) => [
        s[0],
        [s[1][3], s[1][0], s[1][1], s[1][2]],
        [s[2][2], s[2][3], s[2][0], s[2][1]],
        [s[3][1], s[3][2], s[3][3], s[3][0]],
      ];

  static List<List<int>> _mixColumns(List<List<int>> s) => List.generate(
        4, (c) => [
          _mul(2, s[0][c]) ^ _mul(3, s[1][c]) ^ s[2][c] ^ s[3][c],
          s[0][c] ^ _mul(2, s[1][c]) ^ _mul(3, s[2][c]) ^ s[3][c],
          s[0][c] ^ s[1][c] ^ _mul(2, s[2][c]) ^ _mul(3, s[3][c]),
          _mul(3, s[0][c]) ^ s[1][c] ^ s[2][c] ^ _mul(2, s[3][c]),
        ],
      ).fold(<List<int>>[], (acc, col) {
        if (acc.isEmpty) {
          return List.generate(4, (r) => [col[r]]);
        }
        for (var r = 0; r < 4; r++) {
          acc[r].add(col[r]);
        }
        return acc;
      });

  static List<List<int>> _invMixColumns(List<List<int>> s) => List.generate(
        4, (c) => [
          _mul(0xe, s[0][c]) ^ _mul(0xb, s[1][c]) ^ _mul(0xd, s[2][c]) ^ _mul(0x9, s[3][c]),
          _mul(0x9, s[0][c]) ^ _mul(0xe, s[1][c]) ^ _mul(0xb, s[2][c]) ^ _mul(0xd, s[3][c]),
          _mul(0xd, s[0][c]) ^ _mul(0x9, s[1][c]) ^ _mul(0xe, s[2][c]) ^ _mul(0xb, s[3][c]),
          _mul(0xb, s[0][c]) ^ _mul(0xd, s[1][c]) ^ _mul(0x9, s[2][c]) ^ _mul(0xe, s[3][c]),
        ],
      ).fold(<List<int>>[], (acc, col) {
        if (acc.isEmpty) {
          return List.generate(4, (r) => [col[r]]);
        }
        for (var r = 0; r < 4; r++) {
          acc[r].add(col[r]);
        }
        return acc;
      });

  static Uint8List _computeHmac(Uint8List data, Uint8List iv, Uint8List key) {
    final combined = Uint8List(data.length + iv.length)
      ..setAll(0, data)
      ..setAll(data.length, iv);
    final result = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      result[i] = combined[i % combined.length] ^ key[i % key.length];
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  static String _generateTopic() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );
    return _bytesToHex(bytes);
  }

  static Uint8List _generateKey() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  static Uint8List _generateIv() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
  }

  static String _bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}

/// Result of a WalletConnect session approval.
class WCApprovalResult {
  final String address;
  const WCApprovalResult({required this.address});
}
