import 'package:test/test.dart';
import 'package:tranyx_web/components/search_and_breakdown_rules.dart';

void main() {
  group('defaultSearchScope', () {
    test('non-rentals pages search jobs', () {
      expect(defaultSearchScope(onRentalsTab: false, propertiesCategory: false), SearchScope.jobs);
      expect(defaultSearchScope(onRentalsTab: false, propertiesCategory: true), SearchScope.jobs);
    });
    test('rentals page follows the active category', () {
      expect(defaultSearchScope(onRentalsTab: true, propertiesCategory: false), SearchScope.vehicles);
      expect(defaultSearchScope(onRentalsTab: true, propertiesCategory: true), SearchScope.realEstate);
    });
    test('only vehicles and real estate are rental scopes', () {
      expect(SearchScope.jobs.isRental, isFalse);
      expect(SearchScope.vehicles.isRental, isTrue);
      expect(SearchScope.realEstate.isRental, isTrue);
    });
  });

  group('jobBreakdownAudience', () {
    test('no logged-in account -> guest breakdown', () {
      expect(jobBreakdownAudience(currentUid: null, creatorId: 'e1', viewingAsNyxian: true), JobBreakdownAudience.guest);
      expect(jobBreakdownAudience(currentUid: '', creatorId: 'e1', viewingAsNyxian: false), JobBreakdownAudience.guest);
    });
    test('signed-in Nyxian (not the owner) -> nyxian only', () {
      expect(jobBreakdownAudience(currentUid: 'n1', creatorId: 'e1', viewingAsNyxian: true), JobBreakdownAudience.nyxian);
    });
    test('job owner -> employer only, even for a hybrid in Nyxian mode', () {
      expect(jobBreakdownAudience(currentUid: 'e1', creatorId: 'e1', viewingAsNyxian: false), JobBreakdownAudience.employer);
      expect(jobBreakdownAudience(currentUid: 'e1', creatorId: 'e1', viewingAsNyxian: true), JobBreakdownAudience.employer);
    });
    test("signed-in employer on someone else's job -> none", () {
      expect(jobBreakdownAudience(currentUid: 'e2', creatorId: 'e1', viewingAsNyxian: false), JobBreakdownAudience.none);
    });
  });
}
