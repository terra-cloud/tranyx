library;

import 'dart:math' as math;
import 'date_utils.dart';

/// Calculates the Haversine distance in kilometers between two geographic coordinates.
double calculateHaversineDistance(
  double? lat1,
  double? lon1,
  double? lat2,
  double? lon2,
) {
  if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
    return 0.0;
  }
  const double earthRadiusKm = 6371.0;
  final double dLat = _degreesToRadians(lat2 - lat1);
  final double dLon = _degreesToRadians(lon2 - lon1);

  final double a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degreesToRadians(lat1)) *
          math.cos(_degreesToRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);

  final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degreesToRadians(double degrees) {
  return degrees * (math.pi / 180.0);
}

/// Metadata holding structured summaries for active gig filters.
class FilterSummaryInfo {
  /// Category label, e.g. "Showing: All Job Types", "Showing: Recommended Gigs", "Showing: High Paying Gigs"
  final String categorySummary;

  /// Distance constraint label, e.g. "Within 30 km" or "Any Distance"
  final String distanceSummary;

  /// Modality label, e.g. "Including Remote Gigs" or "On-Site Gigs Only (No Remote)"
  final String remoteSummary;

  /// Full concatenated summary line
  final String fullSummaryText;

  /// Total count of matching gigs
  final int count;

  /// True if current filter matches platform default (All + Any Distance + Remote ON)
  final bool isDefaultState;

  const FilterSummaryInfo({
    required this.categorySummary,
    required this.distanceSummary,
    required this.remoteSummary,
    required this.fullSummaryText,
    required this.count,
    required this.isDefaultState,
  });
}

/// Pure Dart filtering engine for Tranyx Gigs/Jobs.
/// Evaluates: Match = Category Rule AND Modality/Distance Rule
class GigFilterEngine {
  /// Default platform high-paying threshold in PHP / TYXBIT
  static const double defaultHighPayingThreshold = 1000.0;

  /// Default any-distance threshold
  static const double anyDistanceThreshold = 999.0;

  /// Evaluates whether a single gig matches the combined filtering criteria.
  static bool evaluateGigMatch({
    required Map<String, dynamic> gig,
    required String categoryFilter, // 'All', 'Recommended', 'High Paying'
    required bool includeRemote, // Remote Toggle ON/OFF
    required double maxRadiusKm, // e.g. 5.0, 15.0, 30.0, 50.0, 100.0, 9999.0
    required double? userLat,
    required double? userLng,
    List<String> userSkills = const [],
    double highPayingThreshold = defaultHighPayingThreshold,
  }) {
    // ── 1. Modality / Distance Evaluation ──────────────────────────────
    final isRemote = isGigRemote(gig);

    if (isRemote) {
      // Remote gig: Excluded strictly if Remote Toggle is OFF
      if (!includeRemote) {
        return false;
      }
      // Remote gig with Remote Toggle ON: Always passes distance check!
    } else {
      // On-Site gig: Evaluate Distance Radius
      if (maxRadiusKm < anyDistanceThreshold) {
        final jobLat = (gig['latitude'] as num?)?.toDouble() ??
            (gig['pickupLat'] as num?)?.toDouble();
        final jobLng = (gig['longitude'] as num?)?.toDouble() ??
            (gig['pickupLng'] as num?)?.toDouble();

        if (jobLat == null ||
            jobLng == null ||
            userLat == null ||
            userLng == null) {
          // If distance filtering is active and coordinates are missing, exclude
          return false;
        }

        final distKm = calculateHaversineDistance(
          userLat,
          userLng,
          jobLat,
          jobLng,
        );
        if (distKm > maxRadiusKm) {
          return false; // Excluded by distance radius
        }
      }
    }

    // ── 2. Category Rule Evaluation ────────────────────────────────────
    return evaluateCategoryMatch(
      gig: gig,
      categoryFilter: categoryFilter,
      userSkills: userSkills,
      highPayingThreshold: highPayingThreshold,
    );
  }

  /// Checks if a gig is marked as remote
  static bool isGigRemote(Map<String, dynamic> gig) {
    final locationType =
        (gig['locationType'] as String?)?.toLowerCase() ?? '';
    final isRemoteBool =
        gig['isRemote'] == true ||
        gig['is_remote'] == true ||
        gig['remote'] == true;
    return locationType == 'remote' || isRemoteBool;
  }

  /// Evaluates category preset rules
  static bool evaluateCategoryMatch({
    required Map<String, dynamic> gig,
    required String categoryFilter,
    List<String> userSkills = const [],
    double highPayingThreshold = defaultHighPayingThreshold,
  }) {
    final normalized = categoryFilter.trim();

    if (normalized == 'All' || normalized.isEmpty) {
      // Scenario 3: All - match all gig types without restrictions
      return true;
    }

    if (normalized == 'Recommended') {
      // Scenario 1: Recommended - matches user skills / preferences
      var skills = userSkills.where((s) => s.trim().isNotEmpty).toList();
      if (skills.isEmpty) {
        skills = const [
          'Electrical',
          'Plumbing',
          'Painting',
          'Carpentry',
          'Cleaning',
          'IT',
          'Delivery',
          'General',
        ];
      }

      final cat = (gig['category'] is String
              ? gig['category'] as String
              : (gig['category']?.toString() ?? ''))
          .toLowerCase();
      final catLabel = (gig['categoryLabel'] as String?)?.toLowerCase() ?? '';
      final desc = (gig['description'] as String?)?.toLowerCase() ?? '';
      final title = (gig['title'] as String?)?.toLowerCase() ?? '';

      final combined = '$cat $catLabel $title $desc';
      return skills.any((skill) {
        final sTrim = skill.trim();
        if (sTrim.isEmpty) return false;
        final pattern = RegExp(
          r'(^|\W)' + RegExp.escape(sTrim) + r'(\W|$)',
          caseSensitive: false,
        );
        return pattern.hasMatch(combined);
      });
    }

    if (normalized == 'High Paying') {
      // Scenario 2: High Paying - payout >= highPayingThreshold
      final payout = (gig['pricingValue'] as num?)?.toDouble() ??
          (gig['payout'] as num?)?.toDouble() ??
          (gig['price'] as num?)?.toDouble() ??
          0.0;
      return payout >= highPayingThreshold;
    }

    return true;
  }

  /// Filters a list of raw gig maps against all active constraints and returns matching list
  static List<Map<String, dynamic>> filterGigList({
    required List<Map<String, dynamic>> gigs,
    required String categoryFilter,
    required bool includeRemote,
    required double maxRadiusKm,
    required double? userLat,
    required double? userLng,
    List<String> userSkills = const [],
    double highPayingThreshold = defaultHighPayingThreshold,
    String sortBy = 'Newest', // 'Newest' or 'Oldest'
  }) {
    final matches = gigs.where((gig) {
      return evaluateGigMatch(
        gig: gig,
        categoryFilter: categoryFilter,
        includeRemote: includeRemote,
        maxRadiusKm: maxRadiusKm,
        userLat: userLat,
        userLng: userLng,
        userSkills: userSkills,
        highPayingThreshold: highPayingThreshold,
      );
    }).toList();

    // Sort by latest or oldest
    matches.sort((a, b) {
      final aTime = getEpochMs(a['createdAt']);
      final bTime = getEpochMs(b['createdAt']);
      if (sortBy == 'Oldest') {
        return aTime.compareTo(bTime);
      }
      return bTime.compareTo(aTime);
    });

    return matches;
  }

  /// Generates the structured active filter summary strip info
  static FilterSummaryInfo buildSummaryInfo({
    required String categoryFilter,
    required bool includeRemote,
    required double maxRadiusKm,
    required int resultCount,
  }) {
    // 1. Category Summary
    String catText;
    final normalized = categoryFilter.trim();
    if (normalized == 'Recommended') {
      catText = 'Showing: Recommended Gigs';
    } else if (normalized == 'High Paying') {
      catText = 'Showing: High Paying Gigs (₱1,000+)';
    } else {
      catText = 'Showing: All Job Types';
    }

    // 2. Distance Summary
    String distText;
    if (maxRadiusKm >= anyDistanceThreshold) {
      distText = 'Any Distance';
    } else {
      distText = 'Within ${maxRadiusKm.toInt()} km';
    }

    // 3. Remote Modality Summary
    String remoteText;
    if (includeRemote) {
      remoteText = 'Including Remote Gigs';
    } else {
      remoteText = 'On-Site Gigs Only (No Remote)';
    }

    final isDefault =
        (normalized == 'All' || normalized.isEmpty) &&
        maxRadiusKm >= anyDistanceThreshold &&
        includeRemote == true;

    final countStr = resultCount == 1 ? '1 gig found' : '$resultCount gigs found';
    final full = '$catText • $distText • $remoteText ($countStr)';

    return FilterSummaryInfo(
      categorySummary: catText,
      distanceSummary: distText,
      remoteSummary: remoteText,
      fullSummaryText: full,
      count: resultCount,
      isDefaultState: isDefault,
    );
  }
}
