import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  const sig = 'S1gnature';

  test('sends only signature, kind and (for subscriptions) plan', () async {
    final sent = <Map<String, dynamic>>[];
    Future<Map<String, dynamic>> invoke(Map<String, dynamic> d) async {
      sent.add(d);
      return {'status': 'credited', 'phpAmount': 4000};
    }

    await creditOnchainViaServer(invoke: invoke, signature: sig, kind: OnchainCreditKind.depositSol);
    await creditOnchainViaServer(invoke: invoke, signature: sig, kind: OnchainCreditKind.depositUsdt, plan: 'yearly');
    await creditOnchainViaServer(invoke: invoke, signature: sig, kind: OnchainCreditKind.subscriptionSol, plan: 'yearly');
    await creditOnchainViaServer(invoke: invoke, signature: sig, kind: OnchainCreditKind.subscriptionSol, plan: 'weird');
    expect(sent[0], {'signature': sig, 'kind': 'deposit_sol'});
    expect(sent[1], {'signature': sig, 'kind': 'deposit_usdt'});
    expect(sent[2], {'signature': sig, 'kind': 'subscription_sol', 'plan': 'yearly'});
    expect(sent[3]['plan'], 'monthly');
  });

  test('polls while not finalized, then returns the credit', () async {
    var calls = 0;
    final waits = <Duration>[];
    final res = await creditOnchainViaServer(
      invoke: (_) async => ++calls < 3 ? {'status': 'not_finalized'} : {'status': 'credited', 'phpAmount': 80.5, 'currency': 'SOL'},
      signature: sig,
      kind: OnchainCreditKind.depositSol,
      sleep: (d) async => waits.add(d),
    );
    expect(calls, 3);
    expect(waits, hasLength(2));
    expect(res.result, OnchainCommitResult.credited);
    expect(res.phpAmount, 80.5);
  });

  test('gives up with a support error when it never finalizes', () async {
    var t = DateTime.utc(2026, 1, 1);
    await expectLater(
      creditOnchainViaServer(
        invoke: (_) async => {'status': 'not_finalized'},
        signature: sig,
        kind: OnchainCreditKind.depositSol,
        timeout: const Duration(seconds: 9),
        pollEvery: const Duration(seconds: 3),
        sleep: (d) async => t = t.add(d),
        clock: () => t,
      ),
      throwsA(isA<OnchainSupportException>().having((e) => e.message, 'message', contains('Contact support with signature $sig'))),
    );
  });

  test('status mapping: held and rejected need support, replay and credit do not', () {
    OnchainCommitResult r(String s) => OnchainCreditResponse.fromMap({'status': s}).result;
    expect(r('credited'), OnchainCommitResult.credited);
    expect(r('already_processed'), OnchainCommitResult.alreadyProcessed);
    expect(r('held_by_another_account').needsSupport, isTrue);
    expect(r('rejected').needsSupport, isTrue);
    expect(r('something_new').needsSupport, isTrue);
    expect(r('credited').needsSupport, isFalse);
    expect(r('already_processed').needsSupport, isFalse);
    expect(() => r('rejected').throwIfHeldElsewhere(sig), throwsA(isA<OnchainSupportException>()));
  });

  test('hard failures are rethrown, not swallowed', () async {
    await expectLater(
      creditOnchainViaServer(
        invoke: (_) async => throw const CloudFunctionException('RESOURCE_EXHAUSTED', 'Too many attempts.'),
        signature: sig,
        kind: OnchainCreditKind.depositSol,
      ),
      throwsA(isA<CloudFunctionException>().having((e) => e.isIndeterminate, 'indeterminate', isFalse)),
    );
    expect(const CloudFunctionException('NETWORK', 'x').isIndeterminate, isTrue);
  });
}
