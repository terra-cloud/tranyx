// Web on-chain credit: the REST transaction in FirestoreService against an in-memory
// fake of the Firestore REST API (beginTransaction / GET / PATCH / commit / rollback).
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';
import 'package:tranyx_web/services/firebase_service.dart';

// ── in-memory Firestore REST fake ────────────────────────────────────────────
Map<String, dynamic> _enc(dynamic v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': v.toString()};
  if (v is double) return {'doubleValue': v};
  return {'stringValue': v.toString()};
}

dynamic _dec(Map v) {
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('integerValue')) return int.parse(v['integerValue'] as String);
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  return v['stringValue'];
}

class FakeFirestoreRest {
  final docs = <String, Map<String, dynamic>>{};
  final reads = <String>[]; // doc paths read inside a transaction, in order
  final commits = <Map<String, dynamic>>[];
  final deniedWrites = <String>[]; // path prefixes whose writes return 403
  final deniedReads = <String>[]; // path prefixes whose reads return 403
  void Function()? beforeNextCommit; // simulates a concurrent writer; the commit then aborts (409)
  int abortCommits = 0; // the next N commits abort with 409 (contention)
  var _txn = 0;

  String _path(String url) {
    final u = Uri.parse(url);
    final i = u.path.indexOf('/documents/');
    return Uri.decodeComponent(u.path.substring(i + '/documents/'.length));
  }

  http.Response _json(int status, Object body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  http.Response _err(int status, String message) => _json(status, {
    'error': {'message': message, 'status': status == 403 ? 'PERMISSION_DENIED' : 'ERROR'},
  });

  Map<String, dynamic> _doc(String path) => {
    'name': 'projects/p/databases/(default)/documents/$path',
    'fields': {for (final e in docs[path]!.entries) e.key: _enc(e.value)},
  };

  bool _denied(List<String> prefixes, String path) => prefixes.any(path.startsWith);

  Future<http.Response> handle(http.Request r) async {
    final url = r.url.toString();
    if (r.method == 'POST' && url.endsWith(':beginTransaction')) {
      return _json(200, {'transaction': 'txn-${++_txn}'});
    }
    if (r.method == 'POST' && url.endsWith(':rollback')) return _json(200, {});
    if (r.method == 'GET') {
      final path = _path(url);
      if (r.url.queryParameters.containsKey('transaction')) reads.add(path);
      if (_denied(deniedReads, path)) return _err(403, 'Missing or insufficient permissions.');
      if (!docs.containsKey(path)) return _err(404, 'Document not found');
      return _json(200, _doc(path));
    }
    if (r.method == 'PATCH') {
      final path = _path(url.split('?').first);
      if (_denied(deniedWrites, path)) return _err(403, 'Missing or insufficient permissions.');
      final fields = (jsonDecode(r.body)['fields'] as Map).map((k, v) => MapEntry(k as String, _dec(v as Map)));
      final mask = r.url.queryParametersAll['updateMask.fieldPaths'];
      final d = docs.putIfAbsent(path, () => {});
      if (mask == null) {
        d
          ..clear()
          ..addAll(fields);
      } else {
        for (final f in mask) {
          if (fields.containsKey(f)) {
            d[f] = fields[f];
          } else {
            d.remove(f);
          }
        }
      }
      return _json(200, _doc(path));
    }
    if (r.method == 'POST' && url.endsWith(':commit')) return _commit(jsonDecode(r.body) as Map<String, dynamic>);
    return _err(400, 'unsupported ${r.method} $url');
  }

  http.Response _commit(Map<String, dynamic> body) {
    commits.add(body);
    if (abortCommits > 0) {
      abortCommits--;
      return _err(409, 'Aborted: too much contention on these documents.');
    }
    final hook = beforeNextCommit;
    if (hook != null) {
      beforeNextCommit = null;
      hook();
      return _err(409, 'Aborted: too much contention on these documents.');
    }
    final writes = (body['writes'] as List).cast<Map<String, dynamic>>();
    // Validate everything first so the commit is atomic.
    for (final w in writes) {
      final path = (w['update']['name'] as String).split('/documents/').last;
      if (_denied(deniedWrites, path)) return _err(403, 'Missing or insufficient permissions.');
      final cur = w['currentDocument'] as Map?;
      if (cur != null && cur['exists'] == false && docs.containsKey(path)) return _err(409, 'ALREADY_EXISTS');
      if (cur != null && cur['exists'] == true && !docs.containsKey(path)) return _err(404, 'NOT_FOUND');
    }
    for (final w in writes) {
      final u = w['update'] as Map;
      final path = (u['name'] as String).split('/documents/').last;
      final fields = ((u['fields'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, _dec(v as Map)));
      final mask = (w['updateMask'] as Map?)?['fieldPaths'] as List?;
      final d = docs.putIfAbsent(path, () => {});
      if (mask == null) {
        d
          ..clear()
          ..addAll(fields);
      } else {
        for (final f in mask.cast<String>()) {
          if (fields.containsKey(f)) {
            d[f] = fields[f];
          } else {
            d.remove(f);
          }
        }
      }
      for (final t in ((w['updateTransforms'] as List?) ?? const []).cast<Map>()) {
        final inc = _dec(t['increment'] as Map) as num;
        d[t['fieldPath'] as String] = ((d[t['fieldPath']] as num?) ?? 0) + inc;
      }
    }
    return _json(200, {
      'writeResults': [for (final _ in writes) {}],
    });
  }
}

void main() {
  final fake = FakeFirestoreRest();
  late FirestoreService svc;
  const sig = '5VERv8NMvzbJMEkV8xnrLkEaWRtSz9CosKDYjCJjBRnbJLgp8uirBgmQpjKhoR4tjF3ZpRzrFmBV6UjKdiSZkQUW';
  final nowMs = DateTime.utc(2026, 10, 29, 12).millisecondsSinceEpoch;
  const day = 24 * 60 * 60 * 1000;

  setUpAll(() {
    // Must be set before the first request creates the shared HTTP client.
    SecureFirebaseHttpClient.mockClient = MockClient(fake.handle);
  });

  setUp(() {
    fake.docs
      ..clear()
      ..['users/u1'] = {'tyxBalance': 100.0, 'isPremium': false, 'accountType': 'nyxian', 'name': 'Zeus'};
    fake.reads.clear();
    fake.commits.clear();
    fake.deniedWrites.clear();
    fake.deniedReads.clear();
    fake.beforeNextCommit = null;
    fake.abortCommits = 0;
    svc = FirestoreService('token');
  });

  Map<String, dynamic> depositMarker(String s, {String uid = 'u1'}) => {
    'uid': uid,
    'title': 'Wallet Top-Up (SOL)',
    'desc': 'Crypto deposit of 0.0060 SOL via Phantom',
    'amount': 50.0,
    'status': 'Successful',
    'method': 'Solana',
    'solanaTxSignature': s,
    'solanaAmount': 0.006,
    'createdAt': nowMs,
    'type': 'deposit',
  };

  Future<OnchainCommitResult> deposit({String s = sig, String markerId = 'deposit_sol_', double php = 50}) =>
      svc.creditOnchainDeposit(
        uid: 'u1',
        signature: s,
        markerId: '$markerId$s',
        phpAmount: php,
        markerData: depositMarker(s),
      );

  Future<OnchainCommitResult> subscribe({String s = sig, String plan = 'monthly'}) => svc.activateSubscriptionOnchain(
    uid: 'u1',
    signature: s,
    plan: plan,
    phpAmount: plan == 'yearly' ? 2999.0 : 299.0,
    now: DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
    markerData: {
      'uid': 'u1',
      'title': 'Hybrid PRO Subscription (Monthly)',
      'desc': 'Subscribed via Phantom (0.0245 SOL)',
      'amount': 299.0,
      'status': 'Successful',
      'method': 'Solana',
      'solanaTxSignature': s,
      'solanaAmount': 0.0245,
      'createdAt': nowMs,
      'type': 'subscription',
      'kind': 'subscription',
    },
  );

  Future<void> pending({String s = sig, String kind = 'deposit'}) =>
      svc.writePendingOnchain(uid: 'u1', signature: s, kind: kind, phpAmount: 50, cryptoAmount: 0.006, currency: 'SOL');

  group('deposit credit', () {
    test('one commit: increments the balance, creates both markers, marks pending done', () async {
      await pending();
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!['status'], 'pending');
      expect(await deposit(), OnchainCommitResult.credited);

      expect(fake.docs['users/u1']!['tyxBalance'], 150.0);
      expect(fake.docs['users/u1']!['name'], 'Zeus', reason: 'other user fields are untouched');
      expect(fake.docs['transactions/deposit_sol_$sig'], depositMarker(sig));
      expect(fake.docs['transactions/onchain_$sig']!.keys.toSet(), kOnchainMarkerKeys);
      expect(fake.docs['transactions/onchain_$sig']!['type'], 'onchain_marker');
      expect(fake.docs['transactions/onchain_$sig']!['uid'], 'u1');
      expect(fake.docs['transactions/onchain_$sig']!['markerId'], 'deposit_sol_$sig');
      expect(fake.docs['transactions/onchain_$sig']!['solanaTxSignature'], sig);
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!['status'], 'done');
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!.containsKey('createdAt'), isFalse);
    });

    test('uses a server-side increment and create-only preconditions in a single commit', () async {
      await deposit();
      expect(fake.commits, hasLength(1));
      final writes = (fake.commits.single['writes'] as List).cast<Map<String, dynamic>>();
      expect(fake.commits.single['transaction'], isNotNull);
      final user = writes.firstWhere((w) => (w['update']['name'] as String).endsWith('/users/u1'));
      expect(user['updateTransforms'], [
        {
          'fieldPath': 'tyxBalance',
          'increment': {'doubleValue': 50.0},
        },
      ]);
      expect(user['currentDocument'], {'exists': true});
      for (final id in ['deposit_sol_$sig', 'onchain_$sig']) {
        final w = writes.firstWhere((w) => (w['update']['name'] as String).endsWith('/transactions/$id'));
        expect(w['currentDocument'], {'exists': false}, reason: '$id must be created, never upserted');
      }
    });

    test('reads onchain_<sig> first', () async {
      await deposit();
      expect(fake.reads.first, 'transactions/onchain_$sig');
      expect(fake.reads, contains('transactions/deposit_sol_$sig'));
    });

    test('USDT deposits use the same path with deposit_usdt_', () async {
      expect(await deposit(markerId: 'deposit_usdt_', php: 56.0), OnchainCommitResult.credited);
      expect(fake.docs.containsKey('transactions/deposit_usdt_$sig'), isTrue);
      expect(fake.docs['transactions/onchain_$sig']!['markerId'], 'deposit_usdt_$sig');
      expect(fake.docs['users/u1']!['tyxBalance'], 156.0);
    });

    test('a replay by the same account credits nothing', () async {
      expect(await deposit(), OnchainCommitResult.credited);
      expect(await deposit(), OnchainCommitResult.alreadyProcessed);
      expect(await deposit(markerId: 'deposit_usdt_'), OnchainCommitResult.alreadyProcessed);
      expect(fake.docs['users/u1']!['tyxBalance'], 150.0);
    });

    test('the same signature cannot be reused for a subscription', () async {
      await deposit();
      expect(await subscribe(), OnchainCommitResult.alreadyProcessed);
      expect(fake.docs['users/u1']!['isPremium'], isFalse);
    });

    test('a missing user profile is an error, nothing is written', () async {
      fake.docs.remove('users/u1');
      await expectLater(deposit(), throwsA(isA<Exception>()));
      expect(fake.docs.keys.where((k) => k.startsWith('transactions/')), isEmpty);
    });
  });

  group('marker held by another account', () {
    setUp(() {
      fake.docs['transactions/onchain_$sig'] = {
        'uid': 'u2',
        'type': 'onchain_marker',
        'solanaTxSignature': sig,
        'markerId': 'deposit_sol_$sig',
        'markedAt': 1,
      };
    });

    test('returns heldByAnotherAccount, credits nothing and never reads the per-flow marker', () async {
      fake.deniedReads.add('transactions/deposit_sol_'); // owner-only in the rules: reading it would fail
      expect(await deposit(), OnchainCommitResult.heldByAnotherAccount);
      expect(fake.docs['users/u1']!['tyxBalance'], 100.0);
      expect(fake.reads, isNot(contains('transactions/deposit_sol_$sig')));
      expect(fake.docs.containsKey('transactions/deposit_sol_$sig'), isFalse);
    });

    test('creates the caller\'s own pending record with the note', () async {
      await deposit();
      final rec = fake.docs['transactions/pending_onchain_u1_$sig']!;
      expect(rec['status'], 'pending');
      expect(rec['note'], kMarkerHeldNote);
      expect(rec['uid'], 'u1');
      expect(rec['kind'], 'deposit');
    });

    test('keeps an existing pending record open and adds the note', () async {
      await pending();
      await deposit();
      final rec = fake.docs['transactions/pending_onchain_u1_$sig']!;
      expect(rec['status'], 'pending');
      expect(rec['note'], kMarkerHeldNote);
      expect(rec['phpAmount'], 50.0, reason: 'the original fields stay');
    });

    test('the other account\'s marker is never modified', () async {
      final before = Map.of(fake.docs['transactions/onchain_$sig']!);
      await deposit();
      expect(fake.docs['transactions/onchain_$sig'], before);
    });

    test('a subscription is held the same way and the UI helper asks for support', () async {
      final r = await subscribe();
      expect(r, OnchainCommitResult.heldByAnotherAccount);
      expect(fake.docs['users/u1']!['isPremium'], isFalse);
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!['kind'], 'subscription');
      expect(
        () => r.throwIfHeldElsewhere(sig),
        throwsA(
          isA<OnchainSupportException>().having(
            (e) => e.toString(),
            'message',
            contains('Contact support with signature $sig'),
          ),
        ),
      );
    });

    test('a marker created by someone else between our read and commit re-runs and ends held', () async {
      fake.docs.remove('transactions/onchain_$sig');
      fake.beforeNextCommit = () => fake.docs['transactions/onchain_$sig'] = {'uid': 'u2', 'type': 'onchain_marker'};
      expect(await deposit(), OnchainCommitResult.heldByAnotherAccount);
      expect(fake.docs['users/u1']!['tyxBalance'], 100.0);
    });

    test('a foreign per-flow marker (legacy, no onchain_ marker) is held too', () async {
      fake.docs
        ..remove('transactions/onchain_$sig')
        ..['transactions/deposit_sol_$sig'] = {'uid': 'u2', 'type': 'deposit'};
      expect(await deposit(), OnchainCommitResult.heldByAnotherAccount);
      expect(fake.docs['users/u1']!['tyxBalance'], 100.0);
    });
  });

  group('rules refusal is not a foreign marker', () {
    test('permission-denied on the commit returns refusedByRules with its own note', () async {
      fake.deniedWrites.add('users/');
      await pending();
      final r = await deposit();
      expect(r, OnchainCommitResult.refusedByRules);
      expect(r, isNot(OnchainCommitResult.heldByAnotherAccount));
      expect(fake.docs['users/u1']!['tyxBalance'], 100.0);
      expect(fake.docs.containsKey('transactions/onchain_$sig'), isFalse);
      final rec = fake.docs['transactions/pending_onchain_u1_$sig']!;
      expect(rec['status'], 'pending');
      expect(rec['note'], 'credit refused by rules (permission-denied)');
      expect(rec['note'], kRefusedByRulesNote);
    });

    test('a refusal without an earlier pending record creates one with the note', () async {
      fake.deniedWrites.add('users/');
      await deposit();
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!['note'], kRefusedByRulesNote);
    });

    test('an unreadable legacy foreign per-flow marker is a refusal, not "held"', () async {
      fake.deniedReads.add('transactions/deposit_sol_');
      expect(await deposit(), OnchainCommitResult.refusedByRules);
      expect(fake.docs['users/u1']!['tyxBalance'], 100.0);
    });

    test('a refusal asks the user to contact support too', () async {
      fake.deniedWrites.add('users/');
      final r = await deposit();
      expect(r.needsSupport, isTrue);
      expect(() => r.throwIfHeldElsewhere(sig), throwsA(isA<OnchainSupportException>()));
    });
  });

  group('contention', () {
    test('after the final 409 retry fails: pending note, nothing credited, "Contact support with signature"', () async {
      await pending();
      fake.abortCommits = 3; // every attempt aborts
      await expectLater(
        deposit(),
        throwsA(
          isA<OnchainSupportException>().having(
            (e) => e.toString(),
            'message',
            contains('Contact support with signature $sig'),
          ),
        ),
      );
      expect(fake.docs['users/u1']!['tyxBalance'], 100.0);
      expect(fake.docs.containsKey('transactions/onchain_$sig'), isFalse);
      expect(fake.docs.containsKey('transactions/deposit_sol_$sig'), isFalse);
      final rec = fake.docs['transactions/pending_onchain_u1_$sig']!;
      expect(rec['status'], 'pending');
      expect(rec['note'], 'contention, retry');
      expect(rec['note'], kContentionNote);
      expect(
        fake.commits.where((c) => (c['writes'] as List).length > 1),
        hasLength(3),
        reason: 'three credit attempts',
      );
    });

    test('creates the pending record with the note when none existed', () async {
      fake.abortCommits = 3;
      await expectLater(deposit(), throwsA(isA<OnchainSupportException>()));
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!['note'], kContentionNote);
    });

    test('a subscription behaves the same and records kind subscription', () async {
      fake.abortCommits = 3;
      await expectLater(subscribe(), throwsA(isA<OnchainSupportException>()));
      expect(fake.docs['users/u1']!['isPremium'], isFalse);
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!['kind'], 'subscription');
    });

    test('one or two aborted attempts are retried and the credit succeeds', () async {
      await pending();
      fake.abortCommits = 2;
      expect(await deposit(), OnchainCommitResult.credited);
      expect(fake.docs['users/u1']!['tyxBalance'], 150.0);
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!['status'], 'done');
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!.containsKey('note'), isFalse);
    });
  });

  group('subscription', () {
    test('activates Hybrid PRO with the existing fields and a 30-day expiry from now', () async {
      expect(await subscribe(), OnchainCommitResult.credited);
      final u = fake.docs['users/u1']!;
      expect(u['isPremium'], isTrue);
      expect(u['accountType'], 'hybrid');
      expect(u['premiumUntil'], nowMs + 30 * day);
      expect(u['subscriptionPlan'], 'monthly');
      expect(u['subscriptionStartedAt'], nowMs);
      expect(u['subscriptionPaymentMethod'], 'Solana (SOL)');
      expect(u['subscriptionPaymentAmount'], 299.0);
      expect(u['subscriptionTxId'], sig);
      expect(u['subscriptionStatus'], 'active');
      expect(u['name'], 'Zeus');
      expect(fake.docs['transactions/sub_sol_$sig']!['title'], 'Hybrid PRO Subscription (Monthly)');
      expect(fake.docs['transactions/onchain_$sig']!.keys.toSet(), kOnchainMarkerKeys);
    });

    test('yearly runs 365 days', () async {
      await subscribe(plan: 'yearly');
      expect(fake.docs['users/u1']!['premiumUntil'], nowMs + 365 * day);
    });

    test('extends from the current expiry while still subscribed', () async {
      final until = nowMs + 10 * day;
      fake.docs['users/u1']!.addAll({'isPremium': true, 'premiumUntil': until});
      await subscribe();
      expect(fake.docs['users/u1']!['premiumUntil'], until + 30 * day);
    });

    test('an expired subscription restarts from now', () async {
      fake.docs['users/u1']!.addAll({'isPremium': true, 'premiumUntil': nowMs - 40 * day});
      await subscribe();
      expect(fake.docs['users/u1']!['premiumUntil'], nowMs + 30 * day);
    });

    test('removes a pendingSubscription marker field', () async {
      fake.docs['users/u1']!['pendingSubscription'] = 'monthly';
      await subscribe();
      expect(fake.docs['users/u1']!.containsKey('pendingSubscription'), isFalse);
    });

    test('a replay does not extend the expiry again', () async {
      await subscribe();
      expect(await subscribe(), OnchainCommitResult.alreadyProcessed);
      expect(fake.docs['users/u1']!['premiumUntil'], nowMs + 30 * day);
    });

    test('marks the pending record done', () async {
      await pending(kind: 'subscription');
      await subscribe();
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!['status'], 'done');
    });
  });

  group('pending record', () {
    test('is create-only: a second write never overwrites', () async {
      await pending();
      await svc.notePendingOnchain(uid: 'u1', signature: sig, note: 'first');
      await pending();
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!['note'], 'first');
    });

    test('is keyed by the owner uid', () async {
      await pending();
      expect(fake.docs.keys, contains('transactions/pending_onchain_u1_$sig'));
      expect(fake.docs.keys, isNot(contains('transactions/pending_onchain_$sig')));
    });

    test('a note never reopens a done record', () async {
      await pending();
      await deposit();
      await svc.notePendingOnchain(uid: 'u1', signature: sig, note: 'late');
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!['status'], 'done');
      expect(fake.docs['transactions/pending_onchain_u1_$sig']!.containsKey('note'), isFalse);
    });
  });

  group('tranyx_app.dart uses the transaction, not createOrUpdate', () {
    final src = File('lib/client/tranyx_app.dart').readAsStringSync();

    test('no createOrUpdate of the on-chain credit docs', () {
      for (final id in ['deposit_sol_', 'deposit_usdt_', 'sub_sol_', 'onchain_']) {
        expect(src.contains("createOrUpdate('transactions/$id"), isFalse, reason: id);
      }
    });

    test('SOL deposit, USDT deposit and SOL subscription go through the shared flow', () {
      expect("svc.creditOnchainDeposit(".allMatches(src).length, 2);
      expect("svc.activateSubscriptionOnchain(".allMatches(src).length, 1);
      expect("svc.writePendingOnchain(".allMatches(src).length, 3);
      expect(".throwIfHeldElsewhere(signature)".allMatches(src).length, 3);
      expect(src, contains("markerId: 'deposit_sol_\$signature'"));
      expect(src, contains("markerId: 'deposit_usdt_\$signature'"));
    });
  });
}
