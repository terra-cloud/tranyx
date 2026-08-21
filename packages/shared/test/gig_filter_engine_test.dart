import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('GigFilterEngine Acceptance Criteria Tests (Scenarios 1-10)', () {
    const userLat = 14.5995; // Manila coordinates
    const userLng = 120.9842;

    final mockRemoteGig = {
      'id': 'gig-remote-1',
      'title': 'Flutter Frontend Bug Fix',
      'category': 'IT',
      'categoryLabel': 'Information Technology',
      'description': 'Remote bug fix for Jaspr and Flutter web UI',
      'pricingValue': 1500.0,
      'locationType': 'remote',
      'isRemote': true,
      'createdAt': 1000,
    };

    final mockNearOnSiteGig = {
      'id': 'gig-near-1',
      'title': 'Emergency Kitchen Plumbing',
      'category': 'Plumbing',
      'categoryLabel': 'Plumbing Services',
      'description': 'Fix leaking sink in BGC Taguig',
      'pricingValue': 800.0,
      'locationType': 'on-site',
      'latitude': 14.5547, // BGC (~6.5 km from Manila)
      'longitude': 121.0244,
      'createdAt': 2000,
    };

    final mockFarOnSiteGig = {
      'id': 'gig-far-1',
      'title': 'High Voltage Electrical Rewiring',
      'category': 'Electrical',
      'categoryLabel': 'Electrical Services',
      'description': 'Industrial warehouse electrical repairs in San Fernando Pampanga',
      'pricingValue': 3500.0,
      'locationType': 'on-site',
      'latitude': 15.0285, // San Fernando (~65 km from Manila)
      'longitude': 120.6896,
      'createdAt': 3000,
    };

    final mockLowPayingGig = {
      'id': 'gig-low-1',
      'title': 'Small Grocery Item Pickup',
      'category': 'Delivery',
      'description': 'Pick up snacks from local store',
      'pricingValue': 300.0,
      'locationType': 'on-site',
      'latitude': 14.5995,
      'longitude': 120.9842,
      'createdAt': 4000,
    };

    test('Scenario 1: Recommended Filter matches user skills & preferences', () {
      final userSkills = ['IT', 'Plumbing'];

      // Should match IT (remote) and Plumbing (near on-site)
      final matchRemote = GigFilterEngine.evaluateGigMatch(
        gig: mockRemoteGig,
        categoryFilter: 'Recommended',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        userLat: userLat,
        userLng: userLng,
        userSkills: userSkills,
      );
      expect(matchRemote, isTrue);

      final matchPlumbing = GigFilterEngine.evaluateGigMatch(
        gig: mockNearOnSiteGig,
        categoryFilter: 'Recommended',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        userLat: userLat,
        userLng: userLng,
        userSkills: userSkills,
      );
      expect(matchPlumbing, isTrue);

      // Should NOT match Delivery (since not in userSkills)
      final matchDelivery = GigFilterEngine.evaluateGigMatch(
        gig: mockLowPayingGig,
        categoryFilter: 'Recommended',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        userLat: userLat,
        userLng: userLng,
        userSkills: userSkills,
      );
      expect(matchDelivery, isFalse);

      final summary = GigFilterEngine.buildSummaryInfo(
        categoryFilter: 'Recommended',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        resultCount: 2,
      );
      expect(summary.categorySummary, equals('Showing: Recommended Gigs'));
    });

    test('Scenario 2: High Paying Filter (payout >= 1000) excludes lower-paying gigs', () {
      final matchHigh1 = GigFilterEngine.evaluateGigMatch(
        gig: mockRemoteGig, // ₱1500
        categoryFilter: 'High Paying',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        userLat: userLat,
        userLng: userLng,
      );
      expect(matchHigh1, isTrue);

      final matchHigh2 = GigFilterEngine.evaluateGigMatch(
        gig: mockFarOnSiteGig, // ₱3500
        categoryFilter: 'High Paying',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        userLat: userLat,
        userLng: userLng,
      );
      expect(matchHigh2, isTrue);

      final matchLow = GigFilterEngine.evaluateGigMatch(
        gig: mockLowPayingGig, // ₱300
        categoryFilter: 'High Paying',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        userLat: userLat,
        userLng: userLng,
      );
      expect(matchLow, isFalse);

      final summary = GigFilterEngine.buildSummaryInfo(
        categoryFilter: 'High Paying',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        resultCount: 2,
      );
      expect(summary.categorySummary, equals('Showing: High Paying Gigs (₱1,000+)'));
    });

    test('Scenario 3: "All" Filter matches all gig categories without dropping', () {
      final gigs = [mockRemoteGig, mockNearOnSiteGig, mockFarOnSiteGig, mockLowPayingGig];
      final filtered = GigFilterEngine.filterGigList(
        gigs: gigs,
        categoryFilter: 'All',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        userLat: userLat,
        userLng: userLng,
      );

      expect(filtered.length, equals(4));
      final summary = GigFilterEngine.buildSummaryInfo(
        categoryFilter: 'All',
        includeRemote: true,
        maxRadiusKm: 9999.0,
        resultCount: 4,
      );
      expect(summary.categorySummary, equals('Showing: All Job Types'));
      expect(summary.isDefaultState, isTrue);
    });

    test('Scenario 4: Remote Gigs Enabled (ON) allows remote gigs regardless of coordinates', () {
      // Even if radius is tight (e.g. 5 km), remote gig is included
      final match = GigFilterEngine.evaluateGigMatch(
        gig: mockRemoteGig,
        categoryFilter: 'All',
        includeRemote: true,
        maxRadiusKm: 5.0,
        userLat: userLat,
        userLng: userLng,
      );
      expect(match, isTrue);

      final summary = GigFilterEngine.buildSummaryInfo(
        categoryFilter: 'All',
        includeRemote: true,
        maxRadiusKm: 5.0,
        resultCount: 1,
      );
      expect(summary.remoteSummary, equals('Including Remote Gigs'));
    });

    test('Scenario 5: Remote Gigs Disabled (OFF) strictly excludes all remote gigs', () {
      final matchRemote = GigFilterEngine.evaluateGigMatch(
        gig: mockRemoteGig,
        categoryFilter: 'All',
        includeRemote: false, // Remote toggle OFF
        maxRadiusKm: 9999.0,
        userLat: userLat,
        userLng: userLng,
      );
      expect(matchRemote, isFalse);

      final matchOnSite = GigFilterEngine.evaluateGigMatch(
        gig: mockNearOnSiteGig,
        categoryFilter: 'All',
        includeRemote: false,
        maxRadiusKm: 9999.0,
        userLat: userLat,
        userLng: userLng,
      );
      expect(matchOnSite, isTrue);

      final summary = GigFilterEngine.buildSummaryInfo(
        categoryFilter: 'All',
        includeRemote: false,
        maxRadiusKm: 9999.0,
        resultCount: 1,
      );
      expect(summary.remoteSummary, equals('On-Site Gigs Only (No Remote)'));
    });

    test('Scenario 6: Distance Radius on Physical vs. Remote Gigs (Within 30 km + Remote ON)', () {
      final gigs = [mockRemoteGig, mockNearOnSiteGig, mockFarOnSiteGig];

      final filtered = GigFilterEngine.filterGigList(
        gigs: gigs,
        categoryFilter: 'All',
        includeRemote: true,
        maxRadiusKm: 30.0,
        userLat: userLat,
        userLng: userLng,
      );

      // mockRemoteGig: included because Remote is ON
      // mockNearOnSiteGig: ~6.5 km <= 30 km -> included
      // mockFarOnSiteGig: ~65 km > 30 km -> excluded
      expect(filtered.map((g) => g['id']).toList(), containsAll(['gig-remote-1', 'gig-near-1']));
      expect(filtered.map((g) => g['id']).toList(), isNot(contains('gig-far-1')));
    });

    test('Scenario 7: Combined Filters Resolution (High Paying + Within 30 km + Remote ON)', () {
      final gigs = [mockRemoteGig, mockNearOnSiteGig, mockFarOnSiteGig, mockLowPayingGig];

      final filtered = GigFilterEngine.filterGigList(
        gigs: gigs,
        categoryFilter: 'High Paying',
        includeRemote: true,
        maxRadiusKm: 30.0,
        userLat: userLat,
        userLng: userLng,
      );

      // mockRemoteGig: ₱1500 (High Paying) + Remote ON -> Included
      // mockNearOnSiteGig: ₱800 -> Excluded (not high paying)
      // mockFarOnSiteGig: ₱3500 (High Paying) -> Excluded (65 km > 30 km)
      // mockLowPayingGig: ₱300 -> Excluded (not high paying)
      expect(filtered.length, equals(1));
      expect(filtered.first['id'], equals('gig-remote-1'));
    });

    test('Scenario 8: Active Filter Summary Strip provides comprehensive human-readable status', () {
      final summary = GigFilterEngine.buildSummaryInfo(
        categoryFilter: 'High Paying',
        includeRemote: true,
        maxRadiusKm: 30.0,
        resultCount: 5,
      );

      expect(summary.categorySummary, equals('Showing: High Paying Gigs (₱1,000+)'));
      expect(summary.distanceSummary, equals('Within 30 km'));
      expect(summary.remoteSummary, equals('Including Remote Gigs'));
      expect(summary.fullSummaryText, equals('Showing: High Paying Gigs (₱1,000+) • Within 30 km • Including Remote Gigs (5 gigs found)'));
      expect(summary.isDefaultState, isFalse);
    });

    test('Scenario 9: Zero Results State produces 0 matches correctly', () {
      final gigs = [mockLowPayingGig]; // ₱300, on-site

      final filtered = GigFilterEngine.filterGigList(
        gigs: gigs,
        categoryFilter: 'High Paying', // Requires ₱1000
        includeRemote: false,
        maxRadiusKm: 5.0,
        userLat: userLat,
        userLng: userLng,
      );

      expect(filtered.isEmpty, isTrue);

      final summary = GigFilterEngine.buildSummaryInfo(
        categoryFilter: 'High Paying',
        includeRemote: false,
        maxRadiusKm: 5.0,
        resultCount: 0,
      );

      expect(summary.count, equals(0));
      expect(summary.fullSummaryText, contains('(0 gigs found)'));
    });

    test('Scenario 10: Clear All / Reset restores default state', () {
      // Default state
      const defaultCategory = 'All';
      const defaultRadius = 9999.0;
      const defaultRemote = true;

      final summary = GigFilterEngine.buildSummaryInfo(
        categoryFilter: defaultCategory,
        includeRemote: defaultRemote,
        maxRadiusKm: defaultRadius,
        resultCount: 10,
      );

      expect(summary.isDefaultState, isTrue);
      expect(summary.categorySummary, equals('Showing: All Job Types'));
      expect(summary.distanceSummary, equals('Any Distance'));
      expect(summary.remoteSummary, equals('Including Remote Gigs'));
    });
  });
}
