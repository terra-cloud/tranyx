import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bs58/bs58.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';
import 'package:tranyx_mobile/core/services/mwa_service.dart';
import 'package:tranyx_mobile/core/services/onchain_credit.dart';

/// What an MWA payment to the treasury must look like on-chain.
class MwaTransferExpectation {
  const MwaTransferExpectation.sol({
    required this.sender,
    required this.treasury,
    required this.amount,
  }) : mint = null,
       treasuryTokenAccount = null;

  const MwaTransferExpectation.token({
    required this.sender,
    required this.treasury,
    required String this.mint,
    required String this.treasuryTokenAccount,
    required this.amount,
  });

  /// The wallet linked to the Tranyx account.
  final String sender;
  final String treasury;

  /// Lamports (SOL) or token base units (USDT, 6 decimals).
  final int amount;

  /// null = native SOL transfer.
  final String? mint;
  final String? treasuryTokenAccount;

  bool get isSol => mint == null;
}

/// Checks a `getTransaction` (jsonParsed) result against [e]. Returns null when
/// the transaction is exactly the expected payment, or a human-readable reason
/// to refuse it.
String? verifyMwaTransfer(Map<String, dynamic>? txResult, MwaTransferExpectation e) {
  if (txResult == null) return 'Transaction not found on-chain.';
  final meta = txResult['meta'];
  if (meta is! Map || meta['err'] != null) {
    return 'Transaction failed on-chain.';
  }
  final message = (txResult['transaction'] as Map?)?['message'];
  if (message is! Map) return 'Transaction has no message.';

  final keys = (message['accountKeys'] as List?) ?? const [];
  final senderSigned = keys.any(
    (k) => k is Map && k['pubkey'] == e.sender && k['signer'] == true,
  );
  if (!senderSigned) {
    return 'The payment was not signed by your linked wallet.';
  }

  final instructions = (message['instructions'] as List?) ?? const [];
  for (final ix in instructions) {
    if (ix is! Map) continue;
    final parsed = ix['parsed'];
    if (parsed is! Map) continue;
    final info = parsed['info'];
    if (info is! Map) continue;
    final type = parsed['type'];
    final program = ix['program'];

    if (e.isSol) {
      if (program == 'system' &&
          type == 'transfer' &&
          info['source'] == e.sender &&
          info['destination'] == e.treasury &&
          _asInt(info['lamports']) == e.amount) {
        return null;
      }
    } else if (program == 'spl-token' &&
        (type == 'transfer' || type == 'transferChecked')) {
      final authority = info['authority'] ?? info['multisigAuthority'];
      final amount = type == 'transferChecked'
          ? _asInt((info['tokenAmount'] as Map?)?['amount'])
          : _asInt(info['amount']);
      // The treasury token account is derived from (treasury, mint), so a
      // matching destination also pins the mint for a plain `transfer`.
      if (authority == e.sender &&
          info['destination'] == e.treasuryTokenAccount &&
          amount == e.amount &&
          (type == 'transfer' || info['mint'] == e.mint)) {
        return null;
      }
    }
  }
  return e.isSol
      ? 'The transaction does not send the expected SOL amount to the treasury.'
      : 'The transaction does not send the expected USDT amount to the treasury.';
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Polls `getTransaction` at **finalized** commitment until the transaction
/// is available or [timeout] passes (then returns null).
Future<Map<String, dynamic>?> fetchFinalizedParsedTransaction({
  required Uri rpcUrl,
  required String signature,
  http.Client? client,
  Duration timeout = const Duration(seconds: 120),
  Duration pollEvery = const Duration(seconds: 3),
}) async {
  final c = client ?? http.Client();
  final deadline = DateTime.now().add(timeout);
  try {
    while (true) {
      try {
        final res = await c.post(
          rpcUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'getTransaction',
            'params': [
              signature,
              {
                'encoding': 'jsonParsed',
                'commitment': 'finalized',
                'maxSupportedTransactionVersion': 0,
              },
            ],
          }),
        );
        if (res.statusCode == 200) {
          final result = (jsonDecode(res.body) as Map)['result'];
          if (result is Map) return Map<String, dynamic>.from(result);
        }
      } catch (_) {
        // transient RPC error: keep polling until the deadline
      }
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(pollEvery);
    }
  } finally {
    if (client == null) c.close();
  }
}

/// Has the wallet pay the treasury over MWA, waits for the transaction to be
/// confirmed and then FINALIZED, and verifies it really is the expected
/// payment from the linked wallet. Returns the signature, or throws.
/// Nothing is credited here; the caller commits with [commitOnceByMarker].
Future<String> payTreasuryViaMwa({
  required MwaService mwa,
  required PhantomService phantom,
  required String linkedPubkey,
  required String treasuryPublicKey,
  required bool isSol,
  required double cryptoAmount,
  required FirebaseFirestore firestore,
  required String uid,
  required String kind, // 'deposit' | 'subscription'
  required double phpAmount,
}) async {
  final int baseUnits = isSol
      ? (cryptoAmount * 1e9).round()
      : (cryptoAmount * 1e6).round();

  final signature = await mwa.signAndSend(
    expectedPublicKey: linkedPubkey,
    buildTransaction: (sender) async {
      final blockhash = await phantom.fetchRecentBlockhash();
      final Uint8List txBytes;
      if (isSol) {
        txBytes = phantom.serializeTransferTransaction(
          senderPubkey: sender,
          receiverPubkey: treasuryPublicKey,
          blockhash: blockhash,
          lamports: baseUnits,
        );
      } else {
        txBytes = await phantom.serializeTokenTransferTransaction(
          senderPubkey: sender,
          receiverPubkey: treasuryPublicKey,
          mintPubkey: phantom.usdtMintAddress,
          blockhash: blockhash,
          microUnits: baseUnits,
        );
      }
      await phantom.simulateTransaction(base58.encode(txBytes));
      return txBytes;
    },
    broadcastSigned: (signed) => phantom.sendTransaction(base58.encode(signed)),
  );

  // The money has left the wallet: record it as pending BEFORE waiting, so
  // support can reconcile if the app dies or finalization never arrives.
  await writePendingOnchain(
    firestore: firestore,
    uid: uid,
    signature: signature,
    kind: kind,
    phpAmount: phpAmount,
    cryptoAmount: cryptoAmount,
    currency: isSol ? 'SOL' : 'USDT',
  );

  try {
    final confirmed = await phantom.confirmTransaction(signature);
    if (!confirmed) {
      throw Exception(
        'Transaction was sent but is not confirmed yet, so nothing was credited. '
        'Contact support with signature $signature.',
      );
    }

    final expectation = isSol
        ? MwaTransferExpectation.sol(
            sender: linkedPubkey,
            treasury: treasuryPublicKey,
            amount: baseUnits,
          )
        : MwaTransferExpectation.token(
            sender: linkedPubkey,
            treasury: treasuryPublicKey,
            mint: phantom.usdtMintAddress,
            treasuryTokenAccount: phantom.deriveATA(
              walletPubkey: treasuryPublicKey,
              mintPubkey: phantom.usdtMintAddress,
            ),
            amount: baseUnits,
          );

    final tx = await fetchFinalizedParsedTransaction(
      rpcUrl: Uri.parse(phantom.rpcUrl),
      signature: signature,
    );
    if (tx == null) {
      throw Exception(
        'The payment is not finalized yet, so nothing was credited. '
        'Contact support with signature $signature.',
      );
    }
    final problem = verifyMwaTransfer(tx, expectation);
    if (problem != null) {
      throw Exception('Payment refused: $problem Signature $signature.');
    }
    return signature;
  } catch (e) {
    // Leave the record pending, with the reason, for support.
    await notePendingOnchain(firestore: firestore, uid: uid, signature: signature, note: '$e');
    rethrow;
  }
}
