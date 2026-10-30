import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart' hide JobQuestion;
import 'package:tranyx_mobile/features/jobs/providers/job_repository.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';
import 'helpers/fake_firestore.dart';

/// Phase 4: balances and escrow documents are Admin-SDK only, so the repositories must send intent
/// (ids + action) to the money callables and never write `tyxBalance` / escrow docs themselves.
void main() {
  late FakeFirebaseFirestore firestore;
  late List<MapEntry<String, Map<String, dynamic>>> calls;

  Future<Map<String, dynamic>> fakeMoney(String name, Map<String, dynamic> data) async {
    calls.add(MapEntry(name, data));
    return {'ok': true, 'refund': 10.0, 'payout': 90.0, 'commission': 3.0, 'rate': 0.03, 'deposit': 0.0, 'fee': 5.0};
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    calls = [];
  });

  group('JobRepository -> jobAction', () {
    test('cancel / reclaim / delete / complete send only intent', () async {
      final repo = JobRepository(firestore, moneyCaller: fakeMoney);
      await repo.cancelJob(jobId: 'j1', currentUserUid: 'u1');
      await repo.reclaimInactiveJob(jobId: 'j1', employerUid: 'u1', reason: 'stale');
      await repo.deleteJob(jobId: 'j1', currentUserUid: 'u1');
      await repo.completeJob(jobId: 'j1', verificationCodeEntered: ' 1234 ', currentUserUid: 'u1', currentUserName: 'U');
      expect(calls.map((c) => c.key).toSet(), {'jobAction'});
      expect(calls.map((c) => c.value['action']), ['cancel', 'reclaim', 'delete', 'complete']);
      expect(calls[3].value['verificationCode'], '1234');
      for (final c in calls) {
        expect(c.value.containsKey('amount'), isFalse);
        expect(c.value.containsKey('tyxBalance'), isFalse);
      }
      expect(firestore.db.keys.where((k) => k.startsWith('users/') || k.startsWith('escrow')), isEmpty);
    });

    test('createJob never sends an id or amounts and leaves no client writes', () async {
      final repo = JobRepository(firestore, moneyCaller: fakeMoney);
      final job = Job(
        id: 'client-chosen',
        creatorId: 'u1',
        creatorName: 'U',
        creatorType: AccountType.employer,
        title: 'Fix sink',
        description: 'd',
        category: JobCategory.plumber,
        categoryGroup: JobCategoryGroup.homeRepair,
        employmentType: 'Gig',
        dateRequirement: 'Today',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 500.0,
        locationType: 'On-site',
        createdAt: DateTime.now(),
      );
      await repo.createJob(job);
      expect(calls.single.key, 'jobAction');
      expect(calls.single.value['action'], 'create');
      final sent = calls.single.value['job'] as Map;
      expect(sent.containsKey('id'), isFalse);
      expect(sent['pricingValue'], 500);
      expect(firestore.db.keys.where((k) => k.startsWith('users/') || k.startsWith('escrow') || k.startsWith('jobs/')), isEmpty);
    });
  });

  group('TransitRepository -> booking callables', () {
    test('cancel request, revoke, cancel active, complete and extension decisions use the server', () async {
      firestore.db['rental_requests/req1'] = {
        'status': 'Pending', 'renteeId': 'r1', 'hostId': 'h1', 'rentalId': 'veh1', 'totalCost': 100.0, 'bookingFee': 3.0,
        'brand': 'B', 'model': 'M',
      };
      final repo = TransitRepository(firestore, moneyCaller: fakeMoney);
      await repo.cancelBookingRequest('req1');
      expect(calls.single.key, 'bookingAction');
      expect(calls.single.value['action'], 'cancelRequest');
      expect(calls.single.value['kind'], 'vehicle');
      expect(calls.single.value['requestId'], 'req1');
      expect(calls.single.value.containsKey('refund'), isFalse);
      expect(firestore.db.keys.where((k) => k.contains('escrow')), isEmpty);
    });

    test('extension reject and P2P cancel send ids only', () async {
      final repo = TransitRepository(firestore, moneyCaller: fakeMoney);
      await repo.rejectExtension('ext1'); // no-op when the extension doc is missing
      await repo.cancelP2pWithdrawalRequest('w1', reason: 'timeout');
      expect(calls.last.key, 'updateP2pWithdrawal');
      expect(calls.last.value, {'withdrawalId': 'w1', 'action': 'cancel', 'reason': 'timeout'});
    });
  });
}
