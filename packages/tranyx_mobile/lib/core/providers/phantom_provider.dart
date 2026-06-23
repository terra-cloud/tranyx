import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:pinenacl/x25519.dart';
import 'package:bs58/bs58.dart';
import 'package:http/http.dart' as http;
import 'package:tranyx_mobile/flavors.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';

// Stores the session private key generated for a connection request
final phantomSessionPrivateKeyProvider = StateProvider<Uint8List?>(
  (ref) => null,
);

// Stores the type of wallet currently being connected (e.g. phantom, solflare, backpack, trust)
final connectingWalletTypeProvider = StateProvider<String?>((ref) => null);

// Stores the pending wallet public key for new registration/linking
final pendingWalletPublicKeyProvider = StateProvider<String?>((ref) => null);

// Stores whether the device has a valid local session token
final hasLocalSolanaSessionProvider = FutureProvider<bool>((ref) async {
  final token = await SecureStorageHelper.getPhantomSessionToken();
  final pubKey = await SecureStorageHelper.getPhantomEncryptionPublicKey();
  return token != null && pubKey != null;
});

final phantomServiceProvider = Provider<PhantomService>((ref) {
  return PhantomService(ref);
});

/// Describes a supported Solana wallet and its connection protocol.
class WalletInfo {
  final String id;
  final String name;
  final String assetPath;

  /// Native deep-link scheme used on Android/iOS (e.g. `phantom://v1/connect`).
  /// For [useWalletConnect] wallets this is the scheme used to launch the app
  /// (e.g. `trust://wc`) — the actual WC URI is appended as a `?uri=` param.
  final String nativeScheme;

  /// Ordered list of alternative schemes to probe during installation detection
  /// when [nativeScheme] alone may not respond. Empty = only use [nativeScheme].
  final List<String> candidateConnectSchemes;

  /// Whether this wallet uses WalletConnect v1 instead of the Phantom/Solflare
  /// NaCl encryption deep-link protocol.
  ///
  /// - `false` (default): `<wallet>://v1/connect?dapp_encryption_public_key=...`
  /// - `true`: `trust://wc?uri=wc:TOPIC@1?bridge=...&key=...` (WalletConnect)
  final bool useWalletConnect;

  /// Universal / HTTPS fallback link if native scheme is unavailable.
  final String universalLink;

  /// Play Store URL for the "not installed" case on Android.
  final String androidStoreUrl;

  /// App Store URL for the "not installed" case on iOS.
  final String iosStoreUrl;

  const WalletInfo({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.nativeScheme,
    this.candidateConnectSchemes = const [],
    this.useWalletConnect = false,
    required this.universalLink,
    required this.androidStoreUrl,
    required this.iosStoreUrl,
  });
}

final kSupportedWallets = [
  const WalletInfo(
    id: 'phantom',
    name: 'Phantom',
    assetPath: 'assets/images/PhantomWallet.png',
    // Protocol: phantom://v1/connect?dapp_encryption_public_key=...&cluster=...&redirect_link=...
    nativeScheme: 'phantom://v1/connect',
    universalLink: 'https://phantom.app/ul/v1/connect',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=app.phantom',
    iosStoreUrl:
        'https://apps.apple.com/app/phantom-solana-wallet/id1598432977',
  ),
  const WalletInfo(
    id: 'solflare',
    name: 'Solflare',
    assetPath: 'assets/images/Solflare.png',
    // Protocol: solflare://v1/connect?dapp_encryption_public_key=...&cluster=...&redirect_link=...
    nativeScheme: 'solflare://v1/connect',
    universalLink: 'https://solflare.com/ul/v1/connect',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=com.solflare.mobile',
    iosStoreUrl:
        'https://apps.apple.com/app/solflare-solana-wallet/id1580902717',
  ),
];

class PhantomService {
  final Ref _ref;

  PhantomService(this._ref);

  /// Generates an ephemeral key pair for the connection session,
  /// saves the private key to the state provider, and returns the wallet connect URI.
  ///
  /// Uses the **native custom URI scheme** (e.g. `phantom://v1/connect`) so the
  /// OS directly opens the wallet app's connect / authorize screen.
  /// Universal links (https://) are not used because Android requires verified
  /// App Links before they deep-link; otherwise they just open a browser.
  Future<Uri> generateConnectUri({required String walletType}) async {
    // Generate ephemeral session key pair
    final localPrivateKey = PrivateKey.generate();
    final localPublicKey = localPrivateKey.publicKey;

    // Persist private key to Riverpod state provider
    _ref.read(phantomSessionPrivateKeyProvider.notifier).state =
        localPrivateKey.asTypedList;
    _ref.read(connectingWalletTypeProvider.notifier).state = walletType;

    // Also persist to secure storage so it survives potential app background termination
    await SecureStorageHelper.savePhantomSessionKey(
      localPrivateKey.asTypedList,
    );
    await SecureStorageHelper.saveConnectingWalletType(walletType);

    final localPubB58 = base58.encode(localPublicKey.asTypedList);

    // The redirect_link must use our custom scheme so Android/iOS opens the app
    const redirectLink = 'tranyx://tranyx.app/onConnect';

    final cluster = F.appFlavor == Flavor.production
        ? 'mainnet-beta'
        : F.appFlavor == Flavor.uat
        ? 'testnet'
        : 'devnet';

    final queryParams = {
      'dapp_encryption_public_key': localPubB58,
      'app_url': 'https://tranyx.app',
      'redirect_link': redirectLink,
      'cluster': cluster,
    };

    final wallet = kSupportedWallets.firstWhere(
      (w) => w.id == walletType,
      orElse: () => kSupportedWallets.first,
    );

    final baseUrl = wallet.nativeScheme;
    final queryString = Uri(queryParameters: queryParams).query;
    debugPrint('PhantomService: Launching $baseUrl?$queryString');
    return Uri.parse('$baseUrl?$queryString');
  }

  /// Returns the Play Store / App Store URL for the given wallet on this platform.
  String storeUrlFor(String walletType) {
    final wallet = kSupportedWallets.firstWhere(
      (w) => w.id == walletType,
      orElse: () => kSupportedWallets.first,
    );
    return Platform.isIOS ? wallet.iosStoreUrl : wallet.androidStoreUrl;
  }

  /// Decrypts the connect response parameters returned by the wallet app.
  Map<String, dynamic>? decryptConnectResponse({
    required String phantomPubB58,
    required String dataB58,
    required String nonceB58,
    required Uint8List sessionPrivateKeyBytes,
  }) {
    try {
      final localPrivateKey = PrivateKey(sessionPrivateKeyBytes);
      final remotePublicKey = PublicKey(
        Uint8List.fromList(base58.decode(phantomPubB58)),
      );

      final decodedNonce = base58.decode(nonceB58);
      final decodedCipherText = base58.decode(dataB58);

      final msg = EncryptedMessage(
        nonce: Uint8List.fromList(decodedNonce),
        cipherText: Uint8List.fromList(decodedCipherText),
      );

      final appBox = Box(
        myPrivateKey: localPrivateKey,
        theirPublicKey: remotePublicKey,
      );

      final decryptedBytes = appBox.decrypt(msg);
      final decryptedText = utf8.decode(decryptedBytes);

      final Map<String, dynamic> payload = jsonDecode(decryptedText);
      return payload;
    } catch (e) {
      debugPrint('PhantomService: Decryption failed: $e');
      return null;
    }
  }

  /// Construct a Solana transfer transaction and serialize it for Phantom.
  Uint8List serializeTransferTransaction({
    required String senderPubkey,
    required String receiverPubkey,
    required String blockhash,
    required int lamports,
  }) {
    final senderBytes = Uint8List.fromList(base58.decode(senderPubkey));
    final receiverBytes = Uint8List.fromList(base58.decode(receiverPubkey));
    final blockhashBytes = Uint8List.fromList(base58.decode(blockhash));
    final systemProgramBytes = Uint8List(32); // System Program is all 0s

    final builder = BytesBuilder();

    // --- Message ---
    // Header: [numRequiredSignatures, numReadonlySignedAccounts, numReadonlyUnsignedAccounts]
    builder.addByte(1); // 1 signature required (sender)
    builder.addByte(0);
    builder.addByte(1); // 1 readonly unsigned account (System Program)

    // Account Keys Length (Compact-u16)
    builder.addByte(3); // 3 accounts
    // Account Keys
    builder.add(senderBytes);
    builder.add(receiverBytes);
    builder.add(systemProgramBytes);

    // Recent Blockhash (32 bytes)
    builder.add(blockhashBytes);

    // Instructions Length (Compact-u16)
    builder.addByte(1); // 1 instruction

    // Instruction: System Program Transfer
    builder.addByte(2); // Program ID index (System Program is at index 2)

    // Account indices length (Compact-u16)
    builder.addByte(2); // 2 accounts
    builder.addByte(0); // Sender (index 0)
    builder.addByte(1); // Receiver (index 1)

    // Data length (Compact-u16)
    // Data size is 4 bytes (instruction index) + 8 bytes (lamports) = 12 bytes
    builder.addByte(12);

    // Instruction index for Transfer is 2 (32-bit integer, little-endian: [2, 0, 0, 0])
    builder.add(Uint8List.fromList([2, 0, 0, 0]));

    // Lamports (64-bit integer, little-endian)
    final lamportsData = ByteData(8);
    lamportsData.setUint64(0, lamports, Endian.little);
    builder.add(lamportsData.buffer.asUint8List());

    final messageBytes = builder.toBytes();

    // --- Transaction ---
    final txBuilder = BytesBuilder();
    // Signatures length (Compact-u16)
    txBuilder.addByte(1); // 1 signature
    // Signature placeholder (64 bytes of 0s)
    txBuilder.add(Uint8List(64));
    // Message
    txBuilder.add(messageBytes);

    return txBuilder.toBytes();
  }

  /// Generates the launch URI for Phantom/Solflare/Trust to sign a transfer transaction.
  Future<Uri> generateSignTransactionUri({
    required String walletType,
    required String senderPubkey,
    required String receiverPubkey,
    required double amountInSol,
  }) async {
    if (walletType == 'trust') {
      throw UnsupportedError(
        'Trust Wallet signing is handled via WalletConnectService.',
      );
    }

    // 1. Fetch recent blockhash
    final blockhash = await fetchRecentBlockhash();
    final lamports = (amountInSol * 1e9).round();

    // 2. Serialize transaction
    final txBytes = serializeTransferTransaction(
      senderPubkey: senderPubkey,
      receiverPubkey: receiverPubkey,
      blockhash: blockhash,
      lamports: lamports,
    );

    // 3. Load or generate persistent session key pair
    final savedKeyBytes = await SecureStorageHelper.getPhantomSessionKey();
    final PrivateKey localPrivateKey;
    if (savedKeyBytes != null) {
      localPrivateKey = PrivateKey(savedKeyBytes);
    } else {
      localPrivateKey = PrivateKey.generate();
      await SecureStorageHelper.savePhantomSessionKey(
        localPrivateKey.asTypedList,
      );
    }
    final localPublicKey = localPrivateKey.publicKey;

    // 4. Persist to StateProvider and SecureStorage for redirection/state context
    _ref.read(phantomSessionPrivateKeyProvider.notifier).state =
        localPrivateKey.asTypedList;
    _ref.read(connectingWalletTypeProvider.notifier).state = walletType;

    await SecureStorageHelper.saveConnectingWalletType(walletType);

    // 5. Retrieve saved session token and remote encryption public key
    final sessionToken = await SecureStorageHelper.getPhantomSessionToken();
    final remotePubB58 =
        await SecureStorageHelper.getPhantomEncryptionPublicKey();

    if (sessionToken == null || remotePubB58 == null) {
      throw Exception(
        'Solana Wallet is not connected or session token is missing. Please reconnect.',
      );
    }

    final remotePublicKey = PublicKey(
      Uint8List.fromList(base58.decode(remotePubB58)),
    );

    // 6. Build and encrypt payload
    final payload = {
      'transaction': base58.encode(txBytes),
      'session': sessionToken,
    };
    final payloadString = jsonEncode(payload);

    final appBox = Box(
      myPrivateKey: localPrivateKey,
      theirPublicKey: remotePublicKey,
    );

    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
    final encryptedMessage = appBox.encrypt(
      Uint8List.fromList(utf8.encode(payloadString)),
      nonce: nonce,
    );

    final payloadB58 = base58.encode(
      Uint8List.fromList(encryptedMessage.cipherText),
    );
    final nonceB58 = base58.encode(nonce);

    // 7. Redirect link
    const redirectLink = 'tranyx://tranyx.app/onSignTransaction';

    final queryParams = {
      'dapp_encryption_public_key': base58.encode(localPublicKey.asTypedList),
      'nonce': nonceB58,
      'redirect_link': redirectLink,
      'payload': payloadB58,
    };

    final wallet = kSupportedWallets.firstWhere(
      (w) => w.id == walletType,
      orElse: () => kSupportedWallets.first,
    );

    // Construct the signTransaction URL for this specific wallet
    final baseUrl = wallet.nativeScheme.replaceFirst(
      '/connect',
      '/signTransaction',
    );
    final queryString = Uri(queryParameters: queryParams).query;

    debugPrint(
      'PhantomService: Launching transaction signing link: $baseUrl?$queryString',
    );
    return Uri.parse('$baseUrl?$queryString');
  }

  /// Sends a signed transaction in base58 to the Solana cluster via JSON-RPC.
  Future<String> sendTransaction(String base58Tx) async {
    final rpcUrl = F.appFlavor == Flavor.production
        ? 'https://rpc.ankr.com/solana'
        : F.appFlavor == Flavor.uat
        ? 'https://api.testnet.solana.com'
        : 'https://api.devnet.solana.com';

    // Decode base58 transaction and encode to base64 for JSON-RPC
    final txBytes = base58.decode(base58Tx);
    final base64Tx = base64.encode(txBytes);

    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'sendTransaction',
        'params': [
          base64Tx,
          {'encoding': 'base64', 'skipPreflight': false},
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final signature = data['result'] as String?;
      if (signature != null) {
        return signature;
      }
      final error = data['error']?['message'] as String?;
      if (error != null) {
        throw Exception(error);
      }
    }
    throw Exception('Failed to send raw transaction to Solana RPC');
  }

  Future<String> fetchRecentBlockhash() async {
    final rpcUrl = F.appFlavor == Flavor.production
        ? 'https://rpc.ankr.com/solana'
        : 'https://api.devnet.solana.com';

    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'getLatestBlockhash',
        'params': [
          {'commitment': 'finalized'},
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final blockhash = data['result']?['value']?['blockhash'] as String?;
      if (blockhash != null) {
        return blockhash;
      }
    }
    throw Exception('Failed to fetch recent blockhash from Solana RPC');
  }

  Future<String> requestAirdrop(String walletPubkey, int lamports) async {
    final rpcUrl = F.appFlavor == Flavor.production
        ? 'https://rpc.ankr.com/solana'
        : 'https://api.devnet.solana.com';

    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'requestAirdrop',
        'params': [walletPubkey, lamports],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final signature = data['result'] as String?;
      if (signature != null) {
        return signature;
      }
      final error = data['error']?['message'] as String?;
      if (error != null) {
        throw Exception(error);
      }
    }
    throw Exception('Failed to request airdrop from Solana RPC');
  }
}
