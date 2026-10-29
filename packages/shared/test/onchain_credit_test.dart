import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  test('ids', () {
    expect(onchainMarkerId('S'), 'onchain_S');
    expect(pendingOnchainId('u1', 'S'), 'pending_onchain_u1_S');
    expect(pendingOnchainId('u1', 'S'), isNot(pendingOnchainId('u2', 'S')));
  });

  test('notes', () {
    expect(kMarkerHeldNote, 'marker held by another account');
    expect(kRefusedByRulesNote, 'credit refused by rules (permission-denied)');
    expect(kContentionNote, 'contention, retry');
  });

  test('onchain marker has exactly the keys the rules allow', () {
    final m = onchainMarkerData(
      uid: 'u1',
      signature: 'S',
      markerId: 'deposit_sol_S',
      markedAt: 5,
    );
    expect(m.keys.toSet(), kOnchainMarkerKeys);
    expect(m['type'], 'onchain_marker');
  });

  test('pending record has no createdAt and carries the optional note', () {
    final p = pendingOnchainData(
      uid: 'u1',
      signature: 'S',
      kind: 'deposit',
      startedAt: 1,
      note: 'n',
    );
    expect(p['status'], 'pending');
    expect(p.containsKey('createdAt'), isFalse);
    expect(p['note'], 'n');
    expect(
      pendingOnchainData(
        uid: 'u1',
        signature: 'S',
        kind: 'deposit',
        startedAt: 1,
      ).containsKey('note'),
      isFalse,
    );
  });

  test('premium extends from max(now, current)', () {
    const day = 86400000;
    expect(
      nextPremiumUntilMs(
        currentPremiumUntilMs: null,
        nowMs: 1000,
        plan: 'monthly',
      ),
      1000 + 30 * day,
    );
    expect(
      nextPremiumUntilMs(
        currentPremiumUntilMs: 500,
        nowMs: 1000,
        plan: 'yearly',
      ),
      1000 + 365 * day,
    );
    expect(
      nextPremiumUntilMs(
        currentPremiumUntilMs: 5000,
        nowMs: 1000,
        plan: 'monthly',
      ),
      5000 + 30 * day,
    );
  });

  test('results: refusal and held both need support, others do not', () {
    expect(OnchainCommitResult.heldByAnotherAccount.needsSupport, isTrue);
    expect(OnchainCommitResult.refusedByRules.needsSupport, isTrue);
    expect(OnchainCommitResult.credited.needsSupport, isFalse);
    expect(OnchainCommitResult.alreadyProcessed.needsSupport, isFalse);
    expect(OnchainCommitResult.refusedByRules.pendingNote, kRefusedByRulesNote);
    expect(
      OnchainCommitResult.heldByAnotherAccount.pendingNote,
      kMarkerHeldNote,
    );
    expect(
      () => OnchainCommitResult.refusedByRules.throwIfHeldElsewhere('S'),
      throwsA(isA<OnchainSupportException>()),
    );
    OnchainCommitResult.credited.throwIfHeldElsewhere('S');
  });
}
