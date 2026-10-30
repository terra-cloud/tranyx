// Pure rules for the global search scope and the job-details payment breakdown.
// Kept free of Jaspr / DOM imports so they are unit-testable.

enum SearchScope { jobs, vehicles, realEstate }

extension SearchScopeX on SearchScope {
  String get label => switch (this) {
        SearchScope.jobs => 'Jobs',
        SearchScope.vehicles => 'Vehicles',
        SearchScope.realEstate => 'Real Estate',
      };

  String get placeholder => switch (this) {
        SearchScope.jobs => 'Search gigs, skills, places...',
        SearchScope.vehicles => 'Search vehicles, location...',
        SearchScope.realEstate => 'Search properties, address...',
      };

  bool get isRental => this != SearchScope.jobs;
}

/// Default scope from the page the user is on: the rentals page searches the
/// active rentals category; everywhere else searches jobs.
SearchScope defaultSearchScope({required bool onRentalsTab, required bool propertiesCategory}) {
  if (!onRentalsTab) return SearchScope.jobs;
  return propertiesCategory ? SearchScope.realEstate : SearchScope.vehicles;
}

/// Who may see which estimated payment breakdown on job details.
enum JobBreakdownAudience {
  /// Nobody is logged in (guest browse): the general breakdown.
  guest,

  /// Signed-in worker: only the Nyxian earnings breakdown.
  nyxian,

  /// Signed-in job owner: only the employer cost breakdown.
  employer,

  /// Signed in, but neither the owner nor working as a Nyxian: no breakdown.
  none,
}

JobBreakdownAudience jobBreakdownAudience({
  required String? currentUid,
  required String? creatorId,
  required bool viewingAsNyxian,
}) {
  if (currentUid == null || currentUid.isEmpty) return JobBreakdownAudience.guest;
  if (creatorId != null && creatorId == currentUid) return JobBreakdownAudience.employer;
  if (viewingAsNyxian) return JobBreakdownAudience.nyxian;
  return JobBreakdownAudience.none;
}
