import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tranyx_mobile/core/services/mwa_payment.dart';
import 'package:tranyx_mobile/core/services/mwa_wallet_link.dart';

const _user = 'UserWallet11111111111111111111111111111111';
const _treasury = 'Treasury1111111111111111111111111111111111';
const _treasuryAta = 'TreasuryAta11111111111111111111111111111111';
const _mint = 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB';

Map<String, dynamic> _tx({
  required List<Map<String, dynamic>> instructions,
  String signer = _user,
  bool signerFlag = true,
  Object? err,
}) => {
  'meta': {'err': err},
  'transaction': {
    'message': {
      'accountKeys': [
        {'pubkey': signer, 'signer': signerFlag, 'writable': true},
        {'pubkey': _treasury, 'signer': false, 'writable': true},
      ],
      'instructions': instructions,
    },
  },
};

Map<String, dynamic> _solIx({
  String source = _user,
  String destination = _treasury,
  Object lamports = 50000000,
}) => {
  'program': 'system',
  'parsed': {
    'type': 'transfer',
    'info': {'source': source, 'destination': destination, 'lamports': lamports},
  },
};

Map<String, dynamic> _tokenIx({
  String type = 'transferChecked',
  String authority = _user,
  String destination = _treasuryAta,
  String mint = _mint,
  String amount = '2500000',
}) => {
  'program': 'spl-token',
  'parsed': {
    'type': type,
    'info': {
      'authority': authority,
      'source': 'UserAta',
      'destination': destination,
      if (type == 'transferChecked') ...{
        'mint': mint,
        'tokenAmount': {'amount': amount},
      } else
        'amount': amount,
    },
  },
};

const _sol = MwaTransferExpectation.sol(sender: _user, treasury: _treasury, amount: 50000000);
const _usdt = MwaTransferExpectation.token(
  sender: _user,
  treasury: _treasury,
  mint: _mint,
  treasuryTokenAccount: _treasuryAta,
  amount: 2500000,
);

void main() {
  group('verifyMwaTransfer (SOL)', () {
    test('accepts the exact payment from the linked wallet to the treasury', () {
      expect(verifyMwaTransfer(_tx(instructions: [_solIx()]), _sol), isNull);
    });
    test('accepts when the amount arrives as a string', () {
      expect(verifyMwaTransfer(_tx(instructions: [_solIx(lamports: '50000000')]), _sol), isNull);
    });
    test('refuses a different destination', () {
      expect(verifyMwaTransfer(_tx(instructions: [_solIx(destination: 'Attacker')]), _sol), isNotNull);
    });
    test('refuses a different source', () {
      expect(verifyMwaTransfer(_tx(instructions: [_solIx(source: 'Other')]), _sol), isNotNull);
    });
    test('refuses a wrong amount (less or more)', () {
      expect(verifyMwaTransfer(_tx(instructions: [_solIx(lamports: 49999999)]), _sol), isNotNull);
      expect(verifyMwaTransfer(_tx(instructions: [_solIx(lamports: 50000001)]), _sol), isNotNull);
    });
    test('refuses when the linked wallet did not sign', () {
      expect(verifyMwaTransfer(_tx(instructions: [_solIx()], signerFlag: false), _sol), isNotNull);
      expect(verifyMwaTransfer(_tx(instructions: [_solIx()], signer: 'Other'), _sol), isNotNull);
    });
    test('refuses a failed or missing transaction', () {
      expect(verifyMwaTransfer(_tx(instructions: [_solIx()], err: {'InstructionError': [0, 'x']}), _sol), isNotNull);
      expect(verifyMwaTransfer(null, _sol), isNotNull);
    });
    test('a USDT transfer does not satisfy a SOL expectation', () {
      expect(verifyMwaTransfer(_tx(instructions: [_tokenIx()]), _sol), isNotNull);
    });
  });

  group('verifyMwaTransfer (USDT)', () {
    test('accepts transferChecked to the treasury ATA with the right mint and amount', () {
      expect(verifyMwaTransfer(_tx(instructions: [_tokenIx()]), _usdt), isNull);
    });
    test('accepts a plain transfer to the treasury ATA', () {
      expect(verifyMwaTransfer(_tx(instructions: [_tokenIx(type: 'transfer')]), _usdt), isNull);
    });
    test('finds the transfer among other instructions (ATA create)', () {
      final create = {'program': 'spl-associated-token-account', 'parsed': {'type': 'create', 'info': {}}};
      expect(verifyMwaTransfer(_tx(instructions: [create, _tokenIx()]), _usdt), isNull);
    });
    test('refuses the wrong destination account, mint, amount or authority', () {
      expect(verifyMwaTransfer(_tx(instructions: [_tokenIx(destination: 'AttackerAta')]), _usdt), isNotNull);
      expect(verifyMwaTransfer(_tx(instructions: [_tokenIx(mint: 'FakeMint')]), _usdt), isNotNull);
      expect(verifyMwaTransfer(_tx(instructions: [_tokenIx(amount: '1')]), _usdt), isNotNull);
      expect(verifyMwaTransfer(_tx(instructions: [_tokenIx(authority: 'Other')]), _usdt), isNotNull);
    });
    test('a SOL transfer does not satisfy a USDT expectation', () {
      expect(verifyMwaTransfer(_tx(instructions: [_solIx()]), _usdt), isNotNull);
    });
  });

  group('fetchFinalizedParsedTransaction', () {
    test('asks for finalized commitment and retries until the tx is available', () async {
      final bodies = <Map<String, dynamic>>[];
      var calls = 0;
      final client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        calls++;
        return http.Response(
          jsonEncode({'result': calls < 3 ? null : {'meta': {'err': null}}}),
          200,
        );
      });
      final result = await fetchFinalizedParsedTransaction(
        rpcUrl: Uri.parse('https://rpc.test'),
        signature: 'sig',
        client: client,
        pollEvery: const Duration(milliseconds: 1),
      );
      expect(result, isNotNull);
      expect(calls, 3);
      expect(bodies.first['method'], 'getTransaction');
      final opts = (bodies.first['params'] as List)[1] as Map;
      expect(opts['commitment'], 'finalized');
      expect(opts['encoding'], 'jsonParsed');
    });

    test('returns null when it never finalizes before the timeout', () async {
      final client = MockClient((_) async => http.Response(jsonEncode({'result': null}), 200));
      final result = await fetchFinalizedParsedTransaction(
        rpcUrl: Uri.parse('https://rpc.test'),
        signature: 'sig',
        client: client,
        timeout: const Duration(milliseconds: 20),
        pollEvery: const Duration(milliseconds: 5),
      );
      expect(result, isNull);
    });
  });

  group('creditMwaDeposit (atomic, idempotent per signature)', () {
    late FakeFirebaseFirestore db;
    setUp(() async {
      db = FakeFirebaseFirestore();
      await db.collection('users').doc('u1').set({'tyxBalance': 100.0});
    });

    Future<bool> credit(String sig, {double php = 50}) => creditMwaDeposit(
      firestore: db,
      uid: 'u1',
      markerId: 'deposit_sol_$sig',
      phpAmount: php,
      markerData: {'uid': 'u1', 'type': 'deposit', 'amount': php, 'solanaTxSignature': sig},
    );

    test('first credit increments the balance and writes the marker', () async {
      expect(await credit('sigA'), isTrue);
      expect((await db.collection('users').doc('u1').get()).data()!['tyxBalance'], 150.0);
      expect((await db.collection('transactions').doc('deposit_sol_sigA').get()).exists, isTrue);
    });

    test('the same signature never credits twice (retry / double tap)', () async {
      // The fake has no optimistic-concurrency retry, so replays run one after
      // another; real Firestore additionally serializes concurrent runs.
      final results = <bool>[await credit('sigB'), await credit('sigB'), await credit('sigB')];
      expect(results, [true, false, false]);
      expect((await db.collection('users').doc('u1').get()).data()!['tyxBalance'], 150.0);
    });

    test('different signatures each credit once', () async {
      await credit('s1');
      await credit('s2', php: 25);
      expect((await db.collection('users').doc('u1').get()).data()!['tyxBalance'], 175.0);
    });

    test('uses the current balance (increment), not a stale read', () async {
      await db.collection('users').doc('u1').update({'tyxBalance': 500.0});
      await credit('s3');
      expect((await db.collection('users').doc('u1').get()).data()!['tyxBalance'], 550.0);
    });
  });

  group('linkMwaWallet / unlinkWallet', () {
    late FakeFirebaseFirestore db;
    setUp(() async {
      db = FakeFirebaseFirestore();
      await db.collection('users').doc('u1').set({'tyxBalance': 0});
      await db.collection('users').doc('u2').set({'tyxBalance': 0});
    });

    Future<DocumentSnapshot<Map<String, dynamic>>> link(String key) => db.collection('walletLinks').doc(key).get();

    test('links a new wallet: link doc and profile together', () async {
      expect(await linkMwaWallet(firestore: db, uid: 'u1', publicKey: 'K1'), MwaLinkOutcome.linked);
      expect((await link('K1')).data()!['uid'], 'u1');
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(user['walletPublicKey'], 'K1');
      expect(user['connectedWalletType'], 'mwa');
    });

    test('replacing a wallet removes the previous walletLinks doc', () async {
      await linkMwaWallet(firestore: db, uid: 'u1', publicKey: 'K1');
      await linkMwaWallet(firestore: db, uid: 'u1', publicKey: 'K2');
      expect((await link('K1')).exists, isFalse);
      expect((await link('K2')).exists, isTrue);
      expect((await db.collection('users').doc('u1').get()).data()!['walletPublicKey'], 'K2');
    });

    test('a wallet owned by another account is refused and nothing changes', () async {
      await linkMwaWallet(firestore: db, uid: 'u2', publicKey: 'K1');
      final outcome = await linkMwaWallet(firestore: db, uid: 'u1', publicKey: 'K1');
      expect(outcome, MwaLinkOutcome.alreadyLinkedToAnotherAccount);
      expect((await link('K1')).data()!['uid'], 'u2');
      expect((await db.collection('users').doc('u1').get()).data()!.containsKey('walletPublicKey'), isFalse);
    });

    test('re-linking the same wallet does not re-create the link doc', () async {
      await db.collection('walletLinks').doc('K1').set({'uid': 'u1', 'linkedAt': 111});
      await linkMwaWallet(firestore: db, uid: 'u1', publicKey: 'K1');
      expect((await link('K1')).data()!['linkedAt'], 111);
    });

    test('never deletes a previous link doc that belongs to someone else', () async {
      await db.collection('users').doc('u1').update({'walletPublicKey': 'KX'});
      await db.collection('walletLinks').doc('KX').set({'uid': 'u2', 'linkedAt': 1});
      await linkMwaWallet(firestore: db, uid: 'u1', publicKey: 'K3');
      expect((await link('KX')).exists, isTrue);
    });

    test('unlinkWallet removes the link doc and clears the profile', () async {
      await linkMwaWallet(firestore: db, uid: 'u1', publicKey: 'K1');
      await unlinkWallet(firestore: db, uid: 'u1');
      expect((await link('K1')).exists, isFalse);
      final user = (await db.collection('users').doc('u1').get()).data()!;
      expect(user['walletPublicKey'], isNull);
      expect(user['connectedWalletType'], isNull);
    });
  });
}
