import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('DateUtils - Posting Date Formatting & Parsing Tests', () {
    final baseDate = DateTime(2026, 8, 25, 17, 5); // Aug 25, 2026 at 5:05 PM

    test('parseDateTime parses int epoch ms', () {
      final dt = parseDateTime(baseDate.millisecondsSinceEpoch);
      expect(dt, equals(baseDate));
    });

    test('parseDateTime parses ISO-8601 string', () {
      final dt = parseDateTime('2026-08-25T17:05:00.000');
      expect(dt, isNotNull);
      expect(dt!.year, 2026);
      expect(dt.month, 8);
      expect(dt.day, 25);
    });

    test('parseDateTime returns null for invalid input', () {
      expect(parseDateTime(null), isNull);
      expect(parseDateTime('invalid-date'), isNull);
    });

    test('getEpochMs safely handles valid and invalid inputs', () {
      expect(getEpochMs(baseDate), equals(baseDate.millisecondsSinceEpoch));
      expect(getEpochMs(null), equals(0));
      expect(getEpochMs('invalid'), equals(0));
    });

    test('formatPostingDate returns "Today" when posted on same calendar day', () {
      final now = DateTime(2026, 8, 25, 20, 30);
      final postedTime = DateTime(2026, 8, 25, 8, 15);
      expect(formatPostingDate(postedTime, now: now), equals('Today'));
      expect(formatPostingDate(postedTime, now: now, withPrefix: true), equals('Posted Today'));
    });

    test('formatPostingDate returns "Yesterday" when posted 1 calendar day ago', () {
      final now = DateTime(2026, 8, 26, 10, 0);
      final postedTime = DateTime(2026, 8, 25, 17, 5);
      expect(formatPostingDate(postedTime, now: now), equals('Yesterday'));
      expect(formatPostingDate(postedTime, now: now, withPrefix: true), equals('Posted Yesterday'));
    });

    test('formatPostingDate returns "2 days ago" for 2 days difference', () {
      final now = DateTime(2026, 8, 27, 10, 0);
      final postedTime = DateTime(2026, 8, 25, 17, 5);
      expect(formatPostingDate(postedTime, now: now), equals('2 days ago'));
      expect(formatPostingDate(postedTime, now: now, withPrefix: true), equals('Posted 2 days ago'));
    });

    test('formatPostingDate returns "6 days ago" for 6 days difference', () {
      final now = DateTime(2026, 8, 31, 10, 0);
      final postedTime = DateTime(2026, 8, 25, 17, 5);
      expect(formatPostingDate(postedTime, now: now), equals('6 days ago'));
      expect(formatPostingDate(postedTime, now: now, withPrefix: true), equals('Posted 6 days ago'));
    });

    test('formatPostingDate returns "Aug 25, 2026" for 7 or more days ago', () {
      final now = DateTime(2026, 9, 5, 10, 0);
      final postedTime = DateTime(2026, 8, 25, 17, 5);
      expect(formatPostingDate(postedTime, now: now), equals('Aug 25, 2026'));
      expect(formatPostingDate(postedTime, now: now, withPrefix: true), equals('Posted on Aug 25, 2026'));
    });

    test('formatPostingDateTime formats full date with time and relative info', () {
      final now = DateTime(2026, 8, 27, 10, 0);
      final postedTime = DateTime(2026, 8, 25, 17, 5); // 5:05 PM
      final result = formatPostingDateTime(postedTime, now: now);
      expect(result, equals('Posted on Aug 25, 2026 at 5:05 PM (2 days ago)'));
    });

    test('formatPostingDateTime formats Today and Yesterday with time', () {
      final now = DateTime(2026, 8, 25, 20, 0);
      final todayTime = DateTime(2026, 8, 25, 9, 30);
      expect(formatPostingDateTime(todayTime, now: now), equals('Posted Today at 9:30 AM'));

      final yesterdayTime = DateTime(2026, 8, 24, 14, 15);
      expect(formatPostingDateTime(yesterdayTime, now: now), equals('Posted Yesterday at 2:15 PM'));
    });

    test('Job model posting date getters work correctly', () {
      final job = Job(
        id: 'job-101',
        creatorId: 'user-1',
        creatorName: 'Maria Santos',
        creatorType: AccountType.employer,
        title: 'Grocery Delivery Service',
        description: 'Buy groceries at supermarket',
        category: JobCategory.groceryDelivery,
        categoryGroup: JobCategoryGroup.delivery,
        employmentType: 'Gig / One-time',
        dateRequirement: 'Flexible',
        timePreference: 'Morning',
        pricingType: 'Fixed',
        pricingValue: 500.0,
        locationType: 'On-site',
        createdAt: DateTime.now(),
      );

      expect(job.formattedPostingDate, equals('Today'));
      expect(job.postedDateLabel, equals('Posted Today'));
      expect(job.isPostedToday, isTrue);
      expect(job.isRecent, isTrue);
    });

    test('GigFilterEngine sorts by Newest and Oldest correctly', () {
      final gig1 = {'id': '1', 'title': 'Older Job', 'category': 'All', 'createdAt': 1000};
      final gig2 = {'id': '2', 'title': 'Newer Job', 'category': 'All', 'createdAt': 5000};
      final gig3 = {'id': '3', 'title': 'Newest Job', 'category': 'All', 'createdAt': 9000};

      final list = [gig2, gig1, gig3];

      final newestSorted = GigFilterEngine.filterGigList(
        gigs: list,
        categoryFilter: 'All',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        userLat: 0.0,
        userLng: 0.0,
        sortBy: 'Newest',
      );
      expect(newestSorted.map((g) => g['id']).toList(), equals(['3', '2', '1']));

      final oldestSorted = GigFilterEngine.filterGigList(
        gigs: list,
        categoryFilter: 'All',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        userLat: 0.0,
        userLng: 0.0,
        sortBy: 'Oldest',
      );
      expect(oldestSorted.map((g) => g['id']).toList(), equals(['1', '2', '3']));
    });
  });
}
