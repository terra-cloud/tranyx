import 'package:test/test.dart';
import 'package:tranyx_web/components/job_selection_guards.dart';

void main() {
  group('isStaleJobSelection', () {
    test('same job is not stale', () => expect(isStaleJobSelection('a', 'a'), isFalse));
    test('different job is stale', () => expect(isStaleJobSelection('b', 'a'), isTrue));
    test('closed selection is stale', () => expect(isStaleJobSelection(null, 'a'), isTrue));
  });

  group('applicationsBelongToJob', () {
    test('accepts apps for the selected job', () {
      expect(applicationsBelongToJob('a', 'a', [{'jobId': 'a'}, {}]), isTrue);
    });
    test('drops when selection moved', () {
      expect(applicationsBelongToJob('b', 'a', [{'jobId': 'a'}]), isFalse);
    });
    test('drops foreign records', () {
      expect(applicationsBelongToJob('a', 'a', [{'jobId': 'x'}]), isFalse);
    });
  });

  group('findApplicationFor', () {
    final apps = [
      {'applicantUid': 'u1', 'proposalRate': 100},
      {'applicantUid': 'u2'},
    ];
    test('finds an existing applicant', () => expect(findApplicationFor(apps, 'u1')?['proposalRate'], 100));
    test('null for unknown applicant', () => expect(findApplicationFor(apps, 'u9'), isNull));
    test('null for empty uid', () => expect(findApplicationFor(apps, ''), isNull));
  });

  group('isJobCreator', () {
    test('creator', () => expect(isJobCreator({'creatorId': 'u1'}, 'u1'), isTrue));
    test('other user', () => expect(isJobCreator({'creatorId': 'u1'}, 'u2'), isFalse));
    test('missing creator / uid / job', () {
      expect(isJobCreator({}, 'u1'), isFalse);
      expect(isJobCreator({'creatorId': 'u1'}, null), isFalse);
      expect(isJobCreator(null, 'u1'), isFalse);
    });
  });

  group('chatEventIsCurrent', () {
    test('same chat', () => expect(chatEventIsCurrent('c1', 'c1'), isTrue));
    test('other chat', () => expect(chatEventIsCurrent('c2', 'c1'), isFalse));
    test('closed chat', () => expect(chatEventIsCurrent('', 'c1'), isFalse));
  });
}
