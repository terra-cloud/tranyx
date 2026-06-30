import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:pinenacl/x25519.dart';
import 'package:pinenacl/ed25519.dart';
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
    // Protocol: solflare://ul/v1/connect?dapp_encryption_public_key=...&cluster=...&redirect_link=...
    // Note: the 'ul/' prefix is required for Solflare's Android/iOS deep link routing;
    // without it the app opens but ignores the connect parameters.
    nativeScheme: 'solflare://ul/v1/connect',
    universalLink: 'https://solflare.com/ul/v1/connect',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=com.solflare.mobile',
    iosStoreUrl:
        'https://apps.apple.com/app/solflare-solana-wallet/id1580902717',
  ),
  const WalletInfo(
    id: 'trust',
    name: 'Trust Wallet',
    assetPath: 'assets/images/TrustWallet.jpeg',
    // Protocol: WalletConnect v1 via local bridge.
    // nativeScheme is used only for install detection & to open the app.
    nativeScheme: 'trust://',
    candidateConnectSchemes: [
      'trust://wc',
      'trustwallet://wc',
      'trust://open_url',
      'trustwallet://open_url',
      'trust://',
      'trustwallet://',
    ],
    useWalletConnect: true,
    universalLink: 'https://link.trustwallet.com',
    androidStoreUrl:
        'https://play.google.com/store/apps/details?id=com.wallet.crypto.trustapp',
    iosStoreUrl:
        'https://apps.apple.com/app/trust-crypto-bitcoin-wallet/id1288339409',
  ),
];

class PhantomService {
  final Ref _ref;

  PhantomService(this._ref);

  String get rpcUrl {
    switch (F.appFlavor) {
      case Flavor.production:
        return 'https://rpc.ankr.com/solana';
      case Flavor.uat:
        return 'https://api.testnet.solana.com';
      case Flavor.dev:
        return 'https://api.devnet.solana.com';
    }
  }

  /// Returns the USDT (SPL Token) mint address for the current network flavor.
  ///
  /// - **Mainnet**: Official Tether USDT on Solana.
  /// - **Testnet (UAT)**: No official USDT testnet mint — falls back to mainnet
  ///   address. Transactions will still work for testing the serialization flow.
  /// - **Devnet**: Circle USDC devnet proxy token used as a stand-in for USDT
  ///   since no official Tether devnet mint exists. Decimals are 6 (same as USDT).
  String get usdtMintAddress {
    switch (F.appFlavor) {
      case Flavor.production:
        return 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB'; // Tether USDT mainnet
      case Flavor.uat:
        return 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB'; // No official testnet USDT — use mainnet mint
      case Flavor.dev:
        return '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU'; // Circle USDC devnet proxy (6 decimals)
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SPL Token (USDT) helpers
  // ─────────────────────────────────────────────────────────────────────────

  // Well-known Solana program IDs (as raw 32-byte arrays for message building)
  static final _tokenProgramId = base58.decode(
    'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
  );
  static final _ataProgramId = base58.decode(
    'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJe1bS',
  );
  static final _systemProgramId = Uint8List(32); // all zeros
  static final _sysvarRentId = base58.decode(
    'SysvarRent111111111111111111111111111111111',
  );

  /// Derives the Associated Token Account (ATA) address for [walletPubkey]
  /// and [mintPubkey] using Solana's `findProgramAddress` algorithm.
  ///
  /// Seeds: `[walletBytes, tokenProgramId, mintBytes]`
  /// Program: `ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJe1bS`
  ///
  /// Returns the base58-encoded ATA public key.
  String deriveATA({
    required String walletPubkey,
    required String mintPubkey,
  }) {
    final walletBytes = Uint8List.fromList(base58.decode(walletPubkey));
    final mintBytes = Uint8List.fromList(base58.decode(mintPubkey));
    final tokenProgramBytes = Uint8List.fromList(_tokenProgramId);
    final ataProgramBytes = Uint8List.fromList(_ataProgramId);

    // Try nonces 255 → 0 until we find a valid off-curve point
    for (int nonce = 255; nonce >= 0; nonce--) {
      final seeds = _buildSeeds([
        walletBytes,
        tokenProgramBytes,
        mintBytes,
        Uint8List.fromList([nonce]),
      ]);
      final hash = _sha256ProgramAddress(seeds, ataProgramBytes);
      if (!_isOnCurve(hash)) {
        return base58.encode(hash);
      }
    }
    throw Exception('deriveATA: could not find valid off-curve point');
  }

  /// Concatenates seed arrays for SHA-256 hashing with a "ProgramDerivedAddress" suffix.
  Uint8List _buildSeeds(List<Uint8List> parts) {
    final builder = BytesBuilder();
    for (final part in parts) {
      builder.add(part);
    }
    return builder.toBytes();
  }

  /// Computes SHA-256("ProgramDerivedAddress" + seeds + programId).
  Uint8List _sha256ProgramAddress(Uint8List seeds, Uint8List programId) {
    final builder = BytesBuilder();
    builder.add(seeds);
    builder.add(programId);
    builder.add(utf8.encode('ProgramDerivedAddress'));
    final digest = _sha256(builder.toBytes());
    return Uint8List.fromList(digest);
  }

  /// Computes SHA-256 of [data] using dart:io or the pinenacl hash.
  List<int> _sha256(Uint8List data) {
    // Use dart:io's SHA-256 via the crypto package is not available here,
    // so we use a manual 2-pass compression approach through pinenacl's hash.
    // pinenacl exposes SHA-512 (Hash.blake2b is not SHA-256).
    // Use dart:io's HttpClient-free hash via the `crypto` Dart package which
    // IS available transitively. Fall back to computing it directly.
    //
    // Actually, we call dart:io indirectly via the existing `_sha256Impl`.
    return _sha256Impl(data);
  }

  /// SHA-256 implemented via 64-byte block processing (FIPS 180-4).
  /// This is a pure-Dart implementation since dart:crypto is not guaranteed
  /// to be available in all Flutter flavors without explicit dependency.
  static List<int> _sha256Impl(List<int> data) {
    // SHA-256 constants
    const k = [
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
      0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
      0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
      0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
      0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
      0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];

    int h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
    int h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

    // Pre-processing: padding
    final msgLen = data.length;
    final bitLen = msgLen * 8;
    final padded = <int>[...data, 0x80];
    while (padded.length % 64 != 56) {
      padded.add(0);
    }
    // Append length as 64-bit big-endian
    for (int i = 7; i >= 0; i--) {
      padded.add((bitLen >> (i * 8)) & 0xFF);
    }

    // Process each 512-bit chunk
    for (int chunkStart = 0; chunkStart < padded.length; chunkStart += 64) {
      final w = List<int>.filled(64, 0);
      for (int i = 0; i < 16; i++) {
        w[i] = (padded[chunkStart + i * 4] << 24) |
            (padded[chunkStart + i * 4 + 1] << 16) |
            (padded[chunkStart + i * 4 + 2] << 8) |
            (padded[chunkStart + i * 4 + 3]);
        w[i] = w[i].toSigned(32).toUnsigned(32);
      }
      for (int i = 16; i < 64; i++) {
        final s0 = (_rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)).toUnsigned(32);
        final s1 = (_rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)).toUnsigned(32);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1).toUnsigned(32);
      }

      int a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

      for (int i = 0; i < 64; i++) {
        final s1 = (_rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)).toUnsigned(32);
        final ch = ((e & f) ^ (~e & g)).toUnsigned(32);
        final temp1 = (h + s1 + ch + k[i] + w[i]).toUnsigned(32);
        final s0 = (_rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)).toUnsigned(32);
        final maj = ((a & b) ^ (a & c) ^ (b & c)).toUnsigned(32);
        final temp2 = (s0 + maj).toUnsigned(32);

        h = g; g = f; f = e;
        e = (d + temp1).toUnsigned(32);
        d = c; c = b; b = a;
        a = (temp1 + temp2).toUnsigned(32);
      }

      h0 = (h0 + a).toUnsigned(32);
      h1 = (h1 + b).toUnsigned(32);
      h2 = (h2 + c).toUnsigned(32);
      h3 = (h3 + d).toUnsigned(32);
      h4 = (h4 + e).toUnsigned(32);
      h5 = (h5 + f).toUnsigned(32);
      h6 = (h6 + g).toUnsigned(32);
      h7 = (h7 + h).toUnsigned(32);
    }

    final result = <int>[];
    for (final val in [h0, h1, h2, h3, h4, h5, h6, h7]) {
      result.addAll([(val >> 24) & 0xFF, (val >> 16) & 0xFF, (val >> 8) & 0xFF, val & 0xFF]);
    }
    return result;
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))).toUnsigned(32);

  /// Returns `true` if [bytes] represents a point on the Ed25519 curve.
  ///
  /// Uses the Ed25519 curve equation: -x² + y² ≡ 1 + d·x²·y² (mod p)
  /// where p = 2^255 - 19 and d = -121665/121666 (mod p).
  ///
  /// For PDA/ATA derivation we need OFF-curve points (i.e. this returns false).
  bool _isOnCurve(List<int> bytes) {
    if (bytes.length != 32) return false;

    // Ed25519 field prime: p = 2^255 - 19
    final p = (BigInt.one << 255) - BigInt.from(19);

    // Decode y from little-endian bytes (clear the sign bit)
    final bytesCopy = List<int>.from(bytes);
    final signBit = (bytesCopy[31] & 0x80) != 0;
    bytesCopy[31] &= 0x7F;
    BigInt y = BigInt.zero;
    for (int i = 31; i >= 0; i--) {
      y = (y << 8) | BigInt.from(bytesCopy[i]);
    }

    if (y >= p) return false;

    // d = -121665 * modInverse(121666, p) mod p
    final BigInt d = (BigInt.from(-121665) *
            _modInverse(BigInt.from(121666), p)) %
        p;

    // Recover x² from the curve equation:
    // y² - 1 = x²(d·y² + 1)  →  x² = (y² - 1) * modInverse(d·y² + 1, p)
    final y2 = (y * y) % p;
    final u = (y2 - BigInt.one) % p;
    final v = (d * y2 + BigInt.one) % p;
    final vInv = _modInverse(v, p);
    BigInt x2 = (u * vInv) % p;

    if (x2 == BigInt.zero) {
      // x = 0; valid only when sign bit is 0
      return !signBit;
    }

    // Compute x = x2^((p+3)/8) mod p  (candidate square root)
    final exp = (p + BigInt.from(3)) ~/ BigInt.from(8);
    BigInt x = x2.modPow(exp, p);

    // Verify x²
    if ((x * x) % p == x2 % p) {
      // Adjust sign
      if (signBit != (x % BigInt.two != BigInt.zero)) {
        x = (p - x) % p;
      }
      return true; // Valid on-curve point
    }

    // Try multiplying by sqrt(-1) = 2^((p-1)/4) mod p
    final sqrtM1 = BigInt.two.modPow((p - BigInt.one) ~/ BigInt.from(4), p);
    x = (x * sqrtM1) % p;
    if ((x * x) % p == x2 % p) {
      if (signBit != (x % BigInt.two != BigInt.zero)) {
        x = (p - x) % p;
      }
      return true; // Valid on-curve point
    }

    return false; // Off-curve — valid for PDA/ATA
  }

  /// Computes the modular inverse of [a] modulo [m] using the extended
  /// Euclidean algorithm. Throws if [a] and [m] are not coprime.
  BigInt _modInverse(BigInt a, BigInt m) {
    a = a % m;
    if (a < BigInt.zero) a += m;
    BigInt t = BigInt.zero, newT = BigInt.one;
    BigInt r = m, newR = a;
    while (newR != BigInt.zero) {
      final q = r ~/ newR;
      final tmpT = t - q * newT;
      t = newT;
      newT = tmpT;
      final tmpR = r - q * newR;
      r = newR;
      newR = tmpR;
    }
    if (r > BigInt.one) throw Exception('_modInverse: not invertible');
    if (t < BigInt.zero) t += m;
    return t;
  }

  /// Checks on-chain whether the [ataAddress] account exists (has non-zero
  /// data length). Returns `true` if the ATA already exists.
  Future<bool> _ataExists(String ataAddress) async {
    try {
      final res = await http.post(
        Uri.parse(rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'getAccountInfo',
          'params': [ataAddress, {'encoding': 'base64'}],
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['result']?['value'] != null;
      }
    } catch (_) {}
    return false;
  }

  /// Builds and returns the full serialized (unsigned) Solana transaction for an
  /// SPL token transfer (USDT or any SPL token with 6 decimals).
  ///
  /// If the recipient's ATA does not exist on-chain, a
  /// `createAssociatedTokenAccount` instruction is prepended automatically.
  ///
  /// [senderPubkey]    — the sender's base58 wallet public key
  /// [receiverPubkey]  — the recipient's base58 wallet public key (treasury)
  /// [mintPubkey]      — the SPL token mint address (e.g. USDT)
  /// [blockhash]       — recent blockhash
  /// [microUnits]      — amount in the token's smallest unit (for USDT: 1 USDT = 1,000,000)
  Future<Uint8List> serializeTokenTransferTransaction({
    required String senderPubkey,
    required String receiverPubkey,
    required String mintPubkey,
    required String blockhash,
    required int microUnits,
  }) async {
    final senderBytes = Uint8List.fromList(base58.decode(senderPubkey));
    final receiverBytes = Uint8List.fromList(base58.decode(receiverPubkey));
    final mintBytes = Uint8List.fromList(base58.decode(mintPubkey));
    final blockhashBytes = Uint8List.fromList(base58.decode(blockhash));

    // Derive Associated Token Accounts
    final senderAta = deriveATA(walletPubkey: senderPubkey, mintPubkey: mintPubkey);
    final receiverAta = deriveATA(walletPubkey: receiverPubkey, mintPubkey: mintPubkey);

    final senderAtaBytes = Uint8List.fromList(base58.decode(senderAta));
    final receiverAtaBytes = Uint8List.fromList(base58.decode(receiverAta));

    final receiverAtaExists = await _ataExists(receiverAta);
    debugPrint('PhantomService: Receiver ATA $receiverAta exists: $receiverAtaExists');

    // ── Build account list ─────────────────────────────────────────────────
    // SPL Transfer instruction accounts:
    //   0: senderATA     (writable)
    //   1: receiverATA   (writable)
    //   2: sender wallet (signer)
    //   3: Token Program  (program, readonly)
    //
    // createATA instruction accounts (only if needed):
    //   0: sender wallet (signer/payer)
    //   1: receiverATA   (writable)
    //   2: receiver wallet (readonly)
    //   3: mint           (readonly)
    //   4: System Program
    //   5: Token Program
    //   6: SysvarRent
    //   7: ATA Program    (program)

    // All unique accounts needed
    final tokenProgramBytes = Uint8List.fromList(_tokenProgramId);
    final ataProgramBytes = Uint8List.fromList(_ataProgramId);
    final systemProgramBytes = _systemProgramId;
    final sysvarRentBytes = Uint8List.fromList(_sysvarRentId);

    // Compose account list:
    // Index: 0=sender, 1=senderATA, 2=receiverATA, 3=receiverWallet, 4=mint,
    //        5=SystemProgram, 6=TokenProgram, [7=SysvarRent, 8=ATAProgram] (createATA only)
    final accounts = <Uint8List>[
      senderBytes,      // 0 — signer, writable
      senderAtaBytes,   // 1 — writable
      receiverAtaBytes, // 2 — writable
      receiverBytes,    // 3 — readonly (receiver wallet, for createATA)
      mintBytes,        // 4 — readonly
      systemProgramBytes, // 5 — program
      tokenProgramBytes,  // 6 — program
    ];
    if (!receiverAtaExists) {
      accounts.add(sysvarRentBytes); // 7 — SysvarRent
      accounts.add(ataProgramBytes); // 8 — ATA Program
    }

    // ── Message header ─────────────────────────────────────────────────────
    // numRequiredSignatures = 1 (sender)
    // numReadonlySignedAccounts = 0
    // numReadonlyUnsignedAccounts = depends on createATA:

    // Precise count:
    // Writable non-signer: senderATA(1), receiverATA(2)
    // Readonly non-signer: receiverWallet(3), mint(4), SystemProgram(5), TokenProgram(6)
    //                      [+ sysvarRent(7), ATAProgram(8) if creating]
    final numReadonlyUnsignedPrecise = receiverAtaExists ? 4 : 6;

    final builder = BytesBuilder();
    builder.addByte(1); // numRequiredSignatures
    builder.addByte(0); // numReadonlySignedAccounts
    builder.addByte(numReadonlyUnsignedPrecise);

    // Account keys
    builder.addByte(accounts.length); // compact-u16
    for (final acct in accounts) {
      builder.add(acct);
    }

    // Recent blockhash
    builder.add(blockhashBytes);

    // ── Instructions ───────────────────────────────────────────────────────
    final instructions = <List<int>>[];

    if (!receiverAtaExists) {
      // createAssociatedTokenAccount instruction
      // Program: ATAProgram (index 8)
      // Accounts: payer(0), newATA(2), owner(3), mint(4), SystemProg(5), TokenProg(6), SysvarRent(7)
      final createAtaAccts = [0, 2, 3, 4, 5, 6, 7];
      final createAtaInstr = BytesBuilder();
      createAtaInstr.addByte(8); // program index: ATAProgram
      createAtaInstr.addByte(createAtaAccts.length);
      for (final idx in createAtaAccts) {
        createAtaInstr.addByte(idx);
      }
      createAtaInstr.addByte(0); // no instruction data for createATA
      instructions.add(createAtaInstr.toBytes());
    }

    // SPL token Transfer instruction
    // Program: TokenProgram (index 6 if no createATA, else 6)
    // Accounts: sourceATA(1), destATA(2), authority/owner(0)
    final transferAccts = [1, 2, 0];
    // Instruction data: opcode 3 (Transfer) + u64 amount LE
    final transferData = BytesBuilder();
    transferData.addByte(3); // Transfer opcode
    final amountBytes = ByteData(8);
    amountBytes.setUint64(0, microUnits, Endian.little);
    transferData.add(amountBytes.buffer.asUint8List());

    final transferInstr = BytesBuilder();
    transferInstr.addByte(6); // program index: TokenProgram
    transferInstr.addByte(transferAccts.length);
    for (final idx in transferAccts) {
      transferInstr.addByte(idx);
    }
    final tData = transferData.toBytes();
    transferInstr.addByte(tData.length); // data length (compact-u16; fits in 1 byte)
    transferInstr.add(tData);
    instructions.add(transferInstr.toBytes());

    // Number of instructions (compact-u16)
    builder.addByte(instructions.length);
    for (final instr in instructions) {
      builder.add(instr);
    }

    final messageBytes = builder.toBytes();

    // ── Full transaction: [sig count=1][64-byte placeholder sig][message] ──
    final txBuilder = BytesBuilder();
    txBuilder.addByte(1);
    txBuilder.add(Uint8List(64)); // placeholder signature
    txBuilder.add(messageBytes);

    return txBuilder.toBytes();
  }

  /// Generates the launch URI for Phantom/Solflare to sign an SPL token
  /// transfer transaction (e.g. USDT).
  ///
  /// This mirrors [generateSignTransactionUri] but builds a token transfer
  /// transaction instead of a SOL System Program transfer.
  ///
  /// Trust Wallet uses WalletConnect v2 directly (see payment_pane.dart) and
  /// should NOT call this method.
  Future<Uri> generateSignTokenTransferUri({
    required String walletType,
    required String senderPubkey,
    required String receiverPubkey,
    required double amountInUsdt,
  }) async {
    if (walletType == 'trust') {
      throw UnsupportedError(
        'Trust Wallet USDT signing is handled via WalletConnect in payment_pane.',
      );
    }

    final mintPubkey = usdtMintAddress;
    final blockhash = await fetchRecentBlockhash();
    // USDT has 6 decimal places: 1 USDT = 1,000,000 micro-USDT
    final microUnits = (amountInUsdt * 1e6).round();

    final txBytes = await serializeTokenTransferTransaction(
      senderPubkey: senderPubkey,
      receiverPubkey: receiverPubkey,
      mintPubkey: mintPubkey,
      blockhash: blockhash,
      microUnits: microUnits,
    );

    // Simulate before signing
    await simulateTransaction(base58.encode(txBytes));

    // Load or generate persistent session key pair
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

    // Persist to StateProvider and SecureStorage for redirect state context
    _ref.read(phantomSessionPrivateKeyProvider.notifier).state =
        localPrivateKey.asTypedList;
    _ref.read(connectingWalletTypeProvider.notifier).state = walletType;
    await SecureStorageHelper.saveConnectingWalletType(walletType);

    // Retrieve saved session token and remote encryption public key
    final sessionToken = await SecureStorageHelper.getPhantomSessionToken();
    final remotePubB58 = await SecureStorageHelper.getPhantomEncryptionPublicKey();

    if (sessionToken == null || remotePubB58 == null) {
      throw Exception(
        'Solana Wallet is not connected or session token is missing. Please reconnect.',
      );
    }

    final remotePublicKey = PublicKey(
      Uint8List.fromList(base58.decode(remotePubB58)),
    );

    // Build and encrypt payload
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

    final baseUrl = wallet.nativeScheme.replaceFirst(
      '/connect',
      '/signTransaction',
    );
    final queryString = Uri(queryParameters: queryParams).query;

    debugPrint(
      'PhantomService: Launching USDT sign URI: $baseUrl?$queryString',
    );
    return Uri.parse('$baseUrl?$queryString');
  }

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

    // Simulate before signing
    await simulateTransaction(base58.encode(txBytes));

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

  Future<void> simulateTransaction(String base58Tx) async {
    final txBytes = base58.decode(base58Tx);
    final base64Tx = base64.encode(txBytes);

    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'simulateTransaction',
        'params': [
          base64Tx,
          {'encoding': 'base64', 'sigVerify': false},
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final value = data['result']?['value'];
      if (value != null) {
        final error = value['err'];
        if (error != null) {
          throw Exception('Transaction simulation failed: ${jsonEncode(error)}');
        }
        return;
      }
      final errorMsg = data['error']?['message'] as String?;
      if (errorMsg != null) {
        throw Exception(errorMsg);
      }
    }
    throw Exception('Failed to simulate transaction on Solana RPC');
  }

  /// Sends a signed transaction in base58 to the Solana cluster via JSON-RPC.
  Future<String> sendTransaction(String base58Tx) async {
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

  /// Waits for a transaction signature to be confirmed or finalized.
  Future<bool> confirmTransaction(String signature) async {
    final url = Uri.parse(rpcUrl);
    for (int i = 0; i < 30; i++) {
      try {
        final res = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'getSignatureStatuses',
            'params': [
              [signature],
              {'searchTransactionHistory': true},
            ],
          }),
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final value = data['result']?['value'];
          if (value is List && value.isNotEmpty && value[0] != null) {
            final status = value[0];
            final confirmationStatus = status['confirmationStatus'];
            final err = status['err'];
            if (err != null) {
              throw Exception('Transaction failed on-chain: $err');
            }
            if (confirmationStatus == 'confirmed' ||
                confirmationStatus == 'finalized') {
              return true;
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking transaction status: $e');
        if (e.toString().contains('failed on-chain')) {
          rethrow;
        }
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  /// Signs a SOL transfer transaction using [treasuryPrivKeyBase58] (the
  /// treasury wallet's Ed25519 private key stored in Firestore) and broadcasts
  /// it directly to the Solana RPC.  Returns the transaction signature.
  ///
  /// [treasuryPrivKeyBase58] — 87–88 char Base58-encoded 64-byte Ed25519 key.
  /// [recipientPubkey]       — destination wallet public key (Base58).
  /// [lamports]              — amount in lamports (1 SOL = 1,000,000,000).
  Future<String> signAndBroadcastTransfer({
    required String treasuryPrivKeyBase58,
    required String recipientPubkey,
    required int lamports,
  }) async {
    // 1. Decode the treasury private key (64 bytes: seed || public key)
    final keyBytes = Uint8List.fromList(base58.decode(treasuryPrivKeyBase58));
    if (keyBytes.length != 64) {
      throw Exception(
        'Invalid treasury private key length: expected 64 bytes, got ${keyBytes.length}.',
      );
    }

    // pinenacl SigningKey takes the 32-byte seed (first half of the 64-byte key)
    final seed = keyBytes.sublist(0, 32);
    final signingKey = SigningKey(seed: seed);
    final senderPubkey = base58.encode(signingKey.verifyKey.asTypedList);

    // 2. Fetch recent blockhash
    final blockhash = await fetchRecentBlockhash();

    // 3. Build the unsigned transaction message
    final messageBytes = _buildTransferMessage(
      senderPubkey: senderPubkey,
      recipientPubkey: recipientPubkey,
      blockhash: blockhash,
      lamports: lamports,
    );

    // 4. Sign the message with Ed25519
    final signedMessage = signingKey.sign(messageBytes);
    // SignedMessage layout: [64-byte signature][message]
    final signature = Uint8List.fromList(signedMessage.sublist(0, 64));

    // 5. Assemble the full transaction:
    //    [compact-u16 sig count=1][64-byte signature][message bytes]
    final txBuilder = BytesBuilder();
    txBuilder.addByte(1); // 1 signature
    txBuilder.add(signature);
    txBuilder.add(messageBytes);
    final txBytes = txBuilder.toBytes();

    // 6. Broadcast via sendTransaction (base64 encoded)
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
      final sig = data['result'] as String?;
      if (sig != null) return sig;
      final err = data['error']?['message'] as String?;
      if (err != null) throw Exception('Solana RPC error: $err');
    }
    throw Exception('Failed to broadcast treasury transfer transaction.');
  }

  /// Signs a USDT (SPL Token) transfer transaction using [treasuryPrivKeyBase58]
  /// and broadcasts it directly to the Solana RPC. Returns the transaction signature.
  Future<String> signAndBroadcastTokenTransfer({
    required String treasuryPrivKeyBase58,
    required String recipientPubkey,
    required double amountInUsdt,
  }) async {
    // 1. Decode the treasury private key (64 bytes: seed || public key)
    final keyBytes = Uint8List.fromList(base58.decode(treasuryPrivKeyBase58));
    if (keyBytes.length != 64) {
      throw Exception(
        'Invalid treasury private key length: expected 64 bytes, got ${keyBytes.length}.',
      );
    }

    final seed = keyBytes.sublist(0, 32);
    final signingKey = SigningKey(seed: seed);
    final senderPubkey = base58.encode(signingKey.verifyKey.asTypedList);

    // 2. Fetch recent blockhash
    final blockhash = await fetchRecentBlockhash();

    // 3. Serialize the transaction using serializeTokenTransferTransaction
    final mintPubkey = usdtMintAddress;
    final microUnits = (amountInUsdt * 1e6).round();
    final serialized = await serializeTokenTransferTransaction(
      senderPubkey: senderPubkey,
      receiverPubkey: recipientPubkey,
      mintPubkey: mintPubkey,
      blockhash: blockhash,
      microUnits: microUnits,
    );

    // 4. Extract message bytes (after 1 byte sig count and 64 bytes placeholder sig)
    if (serialized.length < 65) {
      throw Exception('Serialized transaction is too short.');
    }
    final messageBytes = serialized.sublist(65);

    // 5. Sign the message with Ed25519
    final signedMessage = signingKey.sign(messageBytes);
    final signature = Uint8List.fromList(signedMessage.sublist(0, 64));

    // 6. Assemble the full transaction:
    //    [compact-u16 sig count=1][64-byte signature][message bytes]
    final txBuilder = BytesBuilder();
    txBuilder.addByte(1); // 1 signature
    txBuilder.add(signature);
    txBuilder.add(messageBytes);
    final txBytes = txBuilder.toBytes();

    // 7. Broadcast via sendTransaction (base64 encoded)
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
      final sig = data['result'] as String?;
      if (sig != null) return sig;
      final err = data['error']?['message'] as String?;
      if (err != null) throw Exception('Solana RPC error: $err');
    }
    throw Exception('Failed to broadcast treasury token transfer transaction.');
  }


  /// Builds the raw Solana message bytes for a System Program Transfer
  /// instruction (does NOT include the signature prefix).
  Uint8List _buildTransferMessage({
    required String senderPubkey,
    required String recipientPubkey,
    required String blockhash,
    required int lamports,
  }) {
    final senderBytes = Uint8List.fromList(base58.decode(senderPubkey));
    final receiverBytes = Uint8List.fromList(base58.decode(recipientPubkey));
    final blockhashBytes = Uint8List.fromList(base58.decode(blockhash));
    final systemProgram = Uint8List(32); // all zeros

    final builder = BytesBuilder();

    // Message header
    builder.addByte(1); // numRequiredSignatures
    builder.addByte(0); // numReadonlySignedAccounts
    builder.addByte(1); // numReadonlyUnsignedAccounts (System Program)

    // Account keys: [sender, recipient, System Program]
    builder.addByte(3);
    builder.add(senderBytes);
    builder.add(receiverBytes);
    builder.add(systemProgram);

    // Recent blockhash
    builder.add(blockhashBytes);

    // One instruction
    builder.addByte(1);
    // Program ID index = 2 (System Program)
    builder.addByte(2);
    // Accounts: sender(0), recipient(1)
    builder.addByte(2);
    builder.addByte(0);
    builder.addByte(1);
    // Instruction data: transfer opcode (4 bytes LE) + lamports (8 bytes LE)
    builder.addByte(12); // data length
    builder.add(Uint8List.fromList([2, 0, 0, 0])); // Transfer opcode
    final lamportsData = ByteData(8);
    lamportsData.setUint64(0, lamports, Endian.little);
    builder.add(lamportsData.buffer.asUint8List());

    return builder.toBytes();
  }
}
