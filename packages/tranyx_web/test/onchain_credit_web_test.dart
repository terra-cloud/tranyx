// Web on-chain credit: crediting is server-side (creditOnchainPayment). The browser sends
// {signature, kind, plan?} and never writes balances or markers itself.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';
import 'package:tranyx_web/services/firebase_service.dart';

void main() {
  const sig = '5VERv8NMvzbJMEkV8xnrLkEaWRtSz9CosKDYjCJjBRnbJLgp8uirBgmQpjKhoR4tjF3ZpRzrFmBV6UjKdiSZkQUW';
  final requests = <http.Request>[];
  final responses = <(int, Map<String, dynamic>)>[]; // queued callable responses
  final pendingDocs = <String, Map<String, dynamic>>{};
  late FirestoreService svc;

  setUpAll(() {
    SecureFirebaseHttpClient.mockClient = MockClient((req) async {
      requests.add(req);
      if (req.url.path.endsWith('/creditOnchainPayment')) {
        final (code, body) = responses.isEmpty ? (200, {'result': {'status': 'credited'}}) : responses.removeAt(0);
        return http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});
      }
      // Firestore REST: reads of pending records are 404 unless seeded; writes succeed.
      final path = Uri.decodeComponent(req.url.path.split('/documents/').last);
      if (req.method == 'GET') {
        final d = pendingDocs[path];
        if (d == null) return http.Response(jsonEncode({'error': {'code': 404, 'message': 'NOT_FOUND', 'status': 'NOT_FOUND'}}), 404);
        return http.Response(
          jsonEncode({'name': 'x/documents/$path', 'fields': d.map((k, v) => MapEntry(k, {'stringValue': '$v'}))}),
          200,
        );
      }
      return http.Response('{}', 200);
    });
  });

  setUp(() {
    requests.clear();
    responses.clear();
    pendingDocs.clear();
    svc = FirestoreService('token');
  });

  Map<String, dynamic> lastCall() =>
      (jsonDecode(requests.lastWhere((r) => r.url.path.endsWith('/creditOnchainPayment')).body) as Map)['data'] as Map<String, dynamic>;
  List<http.Request> firestoreWrites() => requests.where((r) => r.url.host.contains('firestore') && r.method != 'GET').toList();

  group('deposit credit', () {
    test('sends only signature and kind; credits without any browser write to balance or markers', () async {
      responses.add((200, {'result': {'status': 'credited', 'phpAmount': 4000}}));
      expect(await svc.creditOnchainDeposit(uid: 'u1', signature: sig, isUsdt: false), OnchainCommitResult.credited);
      expect(lastCall(), {'signature': sig, 'kind': 'deposit_sol'});
      expect(firestoreWrites(), isEmpty);
      final call = requests.firstWhere((r) => r.url.path.endsWith('/creditOnchainPayment'));
      expect(call.headers['Authorization'], 'Bearer token');
    });

    test('USDT uses deposit_usdt', () async {
      await svc.creditOnchainDeposit(uid: 'u1', signature: sig, isUsdt: true);
      expect(lastCall()['kind'], 'deposit_usdt');
    });

    test('a replay is alreadyProcessed and needs no support', () async {
      responses.add((200, {'result': {'status': 'already_processed'}}));
      final r = await svc.creditOnchainDeposit(uid: 'u1', signature: sig, isUsdt: false);
      expect(r, OnchainCommitResult.alreadyProcessed);
      expect(r.needsSupport, isFalse);
    });

    test('polls while the transaction is not finalized', () async {
      responses
        ..add((200, {'result': {'status': 'not_finalized'}}))
        ..add((200, {'result': {'status': 'not_finalized'}}))
        ..add((200, {'result': {'status': 'credited'}}));
      final waits = <Duration>[];
      final r = await svc.creditOnchainOnServer(
        uid: 'u1',
        signature: sig,
        kind: OnchainCreditKind.depositSol,
        sleep: (d) async => waits.add(d),
      );
      expect(r, OnchainCommitResult.credited);
      expect(waits, hasLength(2));
    });

    test('never finalizing leaves the pending record open with a note and asks for support', () async {
      for (var i = 0; i < 20; i++) {
        responses.add((200, {'result': {'status': 'not_finalized'}}));
      }
      await expectLater(
        svc.creditOnchainOnServer(
          uid: 'u1',
          signature: sig,
          kind: OnchainCreditKind.depositSol,
          timeout: Duration.zero,
          sleep: (_) async {},
        ),
        throwsA(isA<OnchainSupportException>().having((e) => e.message, 'message', contains('Contact support with signature $sig'))),
      );
      final w = firestoreWrites();
      expect(w, isNotEmpty);
      expect(w.map((r) => r.body).join(), contains('not finalized in time'));
    });
  });

  group('refusals send the user to support', () {
    test('a marker held by another account: pending note, throwIfHeldElsewhere', () async {
      responses.add((200, {'result': {'status': 'held_by_another_account'}}));
      final r = await svc.creditOnchainDeposit(uid: 'u1', signature: sig, isUsdt: false);
      expect(r, OnchainCommitResult.heldByAnotherAccount);
      expect(() => r.throwIfHeldElsewhere(sig), throwsA(isA<OnchainSupportException>()));
      expect(firestoreWrites().map((r) => r.body).join(), contains(kMarkerHeldNote));
    });

    test('a server rejection needs support', () async {
      responses.add((200, {'result': {'status': 'rejected', 'reason': 'NOT_SIGNED_BY_LINKED_WALLET'}}));
      final r = await svc.creditOnchainDeposit(uid: 'u1', signature: sig, isUsdt: false);
      expect(r, OnchainCommitResult.rejectedByServer);
      expect(r.needsSupport, isTrue);
    });

    test('a hard error is surfaced as CloudFunctionException (not a silent success)', () async {
      responses.add((401, {'error': {'status': 'UNAUTHENTICATED', 'message': 'Sign in to continue.'}}));
      responses.add((401, {'error': {'status': 'UNAUTHENTICATED', 'message': 'Sign in to continue.'}}));
      await expectLater(
        svc.creditOnchainDeposit(uid: 'u1', signature: sig, isUsdt: false),
        throwsA(isA<CloudFunctionException>().having((e) => e.status, 'status', 'UNAUTHENTICATED')),
      );
    });
  });

  group('subscription', () {
    test('sends the plan only', () async {
      responses.add((200, {'result': {'status': 'credited', 'plan': 'yearly'}}));
      expect(await svc.activateSubscriptionOnchain(uid: 'u1', signature: sig, plan: 'yearly'), OnchainCommitResult.credited);
      expect(lastCall(), {'signature': sig, 'kind': 'subscription_sol', 'plan': 'yearly'});
    });
  });

  group('pending record (bookkeeping the browser still writes)', () {
    test('writePendingOnchain is create-only and owner-bound', () async {
      await svc.writePendingOnchain(uid: 'u1', signature: sig, kind: 'deposit', phpAmount: 50, cryptoAmount: 0.006, currency: 'SOL');
      final w = firestoreWrites().single;
      final body = jsonDecode(w.body) as Map;
      final write = (body['writes'] as List).single as Map;
      expect((write['update'] as Map)['name'], endsWith('/transactions/pending_onchain_u1_$sig'));
      expect(write['currentDocument'], {'exists': false});
    });
  });

  group('tranyx_app.dart no longer credits from the browser', () {
    final src = File('lib/client/tranyx_app.dart').readAsStringSync();
    final svcSrc = File('lib/services/firebase_service.dart').readAsStringSync();

    test('no createOrUpdate of the on-chain credit docs', () {
      for (final id in ['deposit_sol_', 'deposit_usdt_', 'sub_sol_', 'onchain_']) {
        expect(src.contains("createOrUpdate('transactions/$id"), isFalse, reason: id);
      }
    });

    test('SOL deposit, USDT deposit and SOL subscription go through the server', () {
      expect("svc.creditOnchainDeposit(".allMatches(src).length, 2);
      expect("svc.activateSubscriptionOnchain(".allMatches(src).length, 1);
      expect("svc.writePendingOnchain(".allMatches(src).length, 3);
      expect(".throwIfHeldElsewhere(signature)".allMatches(src).length, 3);
      expect(src, isNot(contains('markerId:')));
    });

    test('the browser client has no on-chain balance/marker transaction code left', () {
      for (final gone in ['commitOnchainOnce', '_commitOnchainAttempt', 'OnchainUserUpdate', 'increments: {']) {
        expect(svcSrc.contains(gone), isFalse, reason: gone);
      }
    });
  });
}
