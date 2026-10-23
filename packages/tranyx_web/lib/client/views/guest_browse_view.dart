import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import '../utils/geo_helper.dart';

/// W05/W10 Top Services chips — same keywords as W20 browse filters (live tallies).
const _kTopServiceChips = [
  'Cleaning',
  'Plumbing',
  'Electrical',
  'Carpentry',
  'Laundry',
  'Delivery',
];

const _kTopServiceIcons = {
  'Cleaning': 'sparkles',
  'Plumbing': 'wrench',
  'Electrical': 'zap',
  'Carpentry': 'hammer',
  'Laundry': 'refresh-cw',
  'Delivery': 'truck',
};

List<({String chip, int count})> _liveTopServiceChips(List<Map<String, dynamic>> jobs) {
  return [
    for (final chip in _kTopServiceChips)
      (
        chip: chip,
        count: jobs
            .where(
              (g) => GigFilterEngine.evaluateCategoryMatch(
                gig: g,
                categoryFilter: chip,
              ),
            )
            .length,
      ),
  ];
}

String _jobTitle(Map<String, dynamic> j) {
  var title = j['title'] as String? ?? '';
  if (title.isEmpty || title == 'Untitled') {
    final category = j['category'] as String? ?? '';
    final categoryLabel = j['categoryLabel'] as String? ?? '';
    final nameToNormalize = categoryLabel.isNotEmpty ? categoryLabel : category;
    title = nameToNormalize.isNotEmpty ? normalizeCategoryName(nameToNormalize) : 'Untitled Gig';
  }
  return title;
}

String _jobRate(Map<String, dynamic> j) {
  final pricingValue = (j['pricingValue'] as num?)?.toDouble() ?? 0.0;
  final pricingType = j['pricingType'] as String? ?? '';
  if (pricingValue <= 0) return 'Rate on join';
  final typeSuffix = pricingType.isNotEmpty ? ' / $pricingType' : '';
  return 'Php ${pricingValue.toStringAsFixed(2)}$typeSuffix';
}

List<String> _jobTags(Map<String, dynamic> j, TranyxAppState s) {
  final tags = <String>[];
  final category = j['category'] as String? ?? '';
  final categoryLabel = j['categoryLabel'] as String? ?? '';
  final cat = normalizeCategoryName(categoryLabel.isNotEmpty ? categoryLabel : category);
  if (cat.isNotEmpty) tags.add(cat);

  final locationType = (j['locationType'] as String? ?? '').trim();
  if (locationType.toLowerCase() == 'remote') {
    tags.add('Remote');
  } else {
    final jobLat = (j['latitude'] as num?)?.toDouble() ?? (j['pickupLat'] as num?)?.toDouble();
    final jobLng = (j['longitude'] as num?)?.toDouble() ?? (j['pickupLng'] as num?)?.toDouble();
    if (jobLat != null && jobLng != null) {
      final dist = calculateDistance(s.userLatitude, s.userLongitude, jobLat, jobLng);
      tags.add('${dist.toStringAsFixed(1)} km');
    } else if (locationType.isNotEmpty) {
      tags.add(locationType);
    }
  }
  return tags;
}

String _approxAreaLabel({
  required double? lat,
  required double? lng,
  required TranyxAppState s,
  String? cityHint,
}) {
  final parts = <String>['Approx. area'];
  final city = (cityHint ?? '').trim();
  if (city.isNotEmpty) {
    // Keep city/area tokens only — strip street-like fragments when possible.
    final first = city.split(',').first.trim();
    if (first.isNotEmpty && first.length < 48) parts.add(first);
  }
  if (lat != null && lng != null) {
    final dist = calculateDistance(s.userLatitude, s.userLongitude, lat, lng);
    parts.add('${dist.toStringAsFixed(1)} km');
  }
  return parts.join(' · ');
}

/// W05 Guest · Browse home — live public listings + signup CTAs (light & dark).
class GuestBrowseViewComponent extends StatelessComponent {
  final TranyxAppState state;
  const GuestBrowseViewComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textSecondary = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    final textMuted = isDark ? 'text-zinc-500' : 'text-[#71717a]';
    final card = isDark
        ? 'bg-zinc-900 border border-zinc-800'
        : 'bg-white border border-[#e4e4e7] shadow-[0px_4px_12px_0px_rgba(9,9,11,0.04)]';
    final link = 'text-[#4f46e5]';

    final openJobs = List<Map<String, dynamic>>.from(s.availableJobs)
      ..sort((jobA, jobB) {
        final aTime = jobA['createdAt'] as int? ?? 0;
        final bTime = jobB['createdAt'] as int? ?? 0;
        return bTime.compareTo(aTime);
      });
    final topGroups = _liveTopServiceChips(openJobs);
    final gigPreview = openJobs.take(3).toList();
    final jobsLoading = s.isLoadingJobs && openJobs.isEmpty;

    final availableVehicles = s.realtimeRentals.where((r) {
      final status = (r['status'] ?? '').toString();
      if (status != 'Available' && status.toLowerCase() != 'available') return false;
      if (r['isDeleted'] == true) return false;
      return true;
    }).toList()
      ..sort((vehA, vehB) {
        final aLat = (vehA['pickupLat'] as num?)?.toDouble();
        final aLng = (vehA['pickupLng'] as num?)?.toDouble();
        final bLat = (vehB['pickupLat'] as num?)?.toDouble();
        final bLng = (vehB['pickupLng'] as num?)?.toDouble();
        final distA = (aLat != null && aLng != null)
            ? calculateDistance(s.userLatitude, s.userLongitude, aLat, aLng)
            : double.infinity;
        final distB = (bLat != null && bLng != null)
            ? calculateDistance(s.userLatitude, s.userLongitude, bLat, bLng)
            : double.infinity;
        return distA.compareTo(distB);
      });

    final availableProperties = s.realtimeProperties.where((prop) {
      final status = prop.status;
      if (status == 'Inactive' ||
          status == 'Unpublished' ||
          status == 'Archived' ||
          status == 'Deleted' ||
          status == 'Not Accepting Bookings') {
        return false;
      }
      if (prop.isDeleted) return false;
      if (status != 'Available' && status.toLowerCase() != 'available') return false;
      return true;
    }).toList()
      ..sort((propA, propB) {
        final distA = calculateDistance(s.userLatitude, s.userLongitude, propA.latitude, propA.longitude);
        final distB = calculateDistance(s.userLatitude, s.userLongitude, propB.latitude, propB.longitude);
        return distA.compareTo(distB);
      });

    // Interleave vehicles + properties by distance for the nearby strip (max 3).
    final nearbyRentals = <({bool isProperty, dynamic item, double dist})>[];
    for (final v in availableVehicles) {
      final lat = (v['pickupLat'] as num?)?.toDouble();
      final lng = (v['pickupLng'] as num?)?.toDouble();
      final dist = (lat != null && lng != null)
          ? calculateDistance(s.userLatitude, s.userLongitude, lat, lng)
          : double.infinity;
      nearbyRentals.add((isProperty: false, item: v, dist: dist));
    }
    for (final p in availableProperties) {
      final dist = calculateDistance(s.userLatitude, s.userLongitude, p.latitude, p.longitude);
      nearbyRentals.add((isProperty: true, item: p, dist: dist));
    }
    nearbyRentals.sort((rA, rB) => rA.dist.compareTo(rB.dist));
    final rentalPreview = nearbyRentals.take(3).toList();

    return div(classes: 'w05-guest space-y-10 animate-fade-up font-dm-sans', [
      // Hero
      div(classes: 'flex flex-col gap-3 max-w-3xl', [
        p(classes: 'm-0 text-sm font-semibold $link', [Component.text('Guest browse.')]),
        h1(
          classes: 'm-0 text-3xl md:text-4xl font-bold tracking-tight $textPrimary',
          [Component.text('Find Jobs. Hire Services. Rent Anything.')],
        ),
        p(
          classes: 'm-0 text-base leading-6 $textSecondary max-w-2xl',
          [
            Component.text(
              'Public listings near you. Exact address and contact unlock after you join and get hired.',
            ),
          ],
        ),
      ]),

      // CTA banner
      div(
        classes:
            'rounded-2xl p-5 md:p-6 flex flex-col md:flex-row md:items-center gap-4 md:gap-6 '
            '${isDark ? "bg-gradient-to-r from-indigo-950/80 to-violet-950/60 border border-indigo-500/20" : "bg-gradient-to-r from-[#eef2ff] to-[#e0e7ff]"}',
        [
          div(classes: 'flex-1', [
            p(
              classes: 'm-0 font-semibold text-base $textPrimary',
              [Component.text('Create a free account to apply, chat, and rent.')],
            ),
          ]),
          div(classes: 'flex flex-wrap items-center gap-2', [
            button(
              classes:
                  'h-11 px-5 rounded-xl font-semibold text-sm text-white bg-[#4f46e5] border-0 cursor-pointer hover:opacity-90',
              attributes: {'type': 'button'},
              events: {'click': (_) => s.promptGuestSignUp()},
              [Component.text('Create account')],
            ),
            button(
              classes:
                  'h-11 px-5 rounded-xl font-semibold text-sm border cursor-pointer '
                  '${isDark ? "bg-zinc-900 border-zinc-700 text-zinc-100 hover:bg-zinc-800" : "bg-white border-[#d4d4d8] text-[#18181b] hover:bg-zinc-50"}',
              attributes: {'type': 'button'},
              events: {'click': (_) => s.promptGuestSignIn()},
              [Component.text('Sign In')],
            ),
            button(
              classes: 'h-11 px-3 font-semibold text-sm $link bg-transparent border-0 cursor-pointer hover:underline',
              attributes: {'type': 'button'},
              events: {'click': (_) {}},
              [Component.text('Continue browsing')],
            ),
          ]),
        ],
      ),

      // Top Services (live category tallies)
      _sectionHeader(
        title: 'Top Services',
        action: 'See All',
        onAction: () => s.openJobsBrowse(),
        textPrimary: textPrimary,
        link: link,
      ),
      if (jobsLoading)
        div(classes: 'grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3', [
          for (var i = 0; i < 6; i++)
            div(
              classes: '$card rounded-2xl p-4 h-[88px] animate-pulse',
              [div(classes: 'size-10 rounded-xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', [])],
            ),
        ])
      else if (openJobs.isEmpty)
        _emptyCard(
          card: card,
          textMuted: textMuted,
          message: 'No open services right now. Check back soon or create an account to post a gig.',
        )
      else
        div(classes: 'grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3', [
          for (final item in topGroups)
            div(
              classes:
                  '$card rounded-2xl p-4 flex flex-col gap-3 cursor-pointer hover:border-[#4f46e5]/40 transition-colors',
              events: {
                'click': (_) => s.openJobsBrowse(filter: item.chip),
              },
              [
                div(
                  classes:
                      'size-10 rounded-xl flex items-center justify-center ${isDark ? "bg-indigo-500/15" : "bg-[#eef2ff]"}',
                  [lIcon(_kTopServiceIcons[item.chip] ?? 'briefcase', cls: 'w-5 h-5 text-[#4f46e5]')],
                ),
                div([
                  p(classes: 'm-0 font-semibold text-sm $textPrimary', [Component.text(item.chip)]),
                  p(
                    classes: 'm-0 text-xs mt-0.5 $textMuted',
                    [Component.text('${item.count} job${item.count == 1 ? '' : 's'} open')],
                  ),
                ]),
              ],
            ),
        ]),

      // Open gigs
      _sectionHeader(
        title: 'Open Gigs Near You',
        action: 'Browse Jobs',
        onAction: () => s.switchTab(AppTab.jobs),
        textPrimary: textPrimary,
        link: link,
      ),
      if (jobsLoading)
        div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-4', [
          for (var i = 0; i < 3; i++)
            div(classes: '$card rounded-2xl p-5 h-[120px] animate-pulse', []),
        ])
      else if (gigPreview.isEmpty)
        _emptyCard(
          card: card,
          textMuted: textMuted,
          message: 'No open gigs nearby yet. Browse again later or sign up to get notified.',
        )
      else
        div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-4', [
          for (final g in gigPreview)
            div(
              classes:
                  '$card rounded-2xl p-5 flex flex-col gap-3 cursor-pointer hover:border-[#4f46e5]/40 transition-colors',
              events: {'click': (_) => s.promptGuestSignUp()},
              [
                p(classes: 'm-0 font-semibold text-[15px] $textPrimary', [Component.text(_jobTitle(g))]),
                div(classes: 'flex flex-wrap gap-2', [
                  for (final tag in _jobTags(g, s))
                    span(
                      classes:
                          'px-2.5 py-1 rounded-full text-xs font-semibold ${isDark ? "bg-zinc-800 text-zinc-300" : "bg-zinc-100 text-zinc-600"}',
                      [Component.text(tag)],
                    ),
                ]),
                div(classes: 'flex items-center justify-between mt-1', [
                  p(classes: 'm-0 font-semibold text-base $textPrimary', [Component.text(_jobRate(g))]),
                  p(
                    classes: 'm-0 text-xs $textMuted',
                    [Component.text(formatPostingDate(g['createdAt'], withPrefix: false))],
                  ),
                ]),
              ],
            ),
        ]),

      // Nearby rentals
      _sectionHeader(
        title: 'Nearby Rentals',
        action: 'View All',
        onAction: () => s.switchTab(AppTab.transit),
        textPrimary: textPrimary,
        link: link,
      ),
      if (rentalPreview.isEmpty)
        _emptyCard(
          card: card,
          textMuted: textMuted,
          message: 'No rentals available nearby yet. View all once hosts publish listings.',
        )
      else
        div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-4', [
          for (final entry in rentalPreview)
            entry.isProperty
                ? _propertyCard(
                    entry.item as PropertyRental,
                    s: s,
                    isDark: isDark,
                    card: card,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    textMuted: textMuted,
                  )
                : _vehicleCard(
                    entry.item as Map<String, dynamic>,
                    s: s,
                    isDark: isDark,
                    card: card,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    textMuted: textMuted,
                  ),
        ]),

      // Locked features
      p(classes: 'm-0 text-sm font-medium $textMuted', [Component.text('Locked until you join.')]),
      div(classes: 'flex flex-col gap-3', [
        _lockedRow(
          isDark: isDark,
          icon: 'message-circle',
          title: 'Messages',
          body: 'Chat with employers and hosts after you create an account.',
          onSignUp: () => s.promptGuestSignUp(),
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        ),
        _lockedRow(
          isDark: isDark,
          icon: 'user',
          title: 'Profile & wallet',
          body: 'KYC, escrow payouts, and account settings stay private until you join.',
          onSignUp: () => s.promptGuestSignUp(),
          textPrimary: textPrimary,
          textSecondary: textSecondary,
        ),
      ]),
    ]);
  }

  Component _emptyCard({
    required String card,
    required String textMuted,
    required String message,
  }) {
    return div(
      classes: '$card rounded-2xl px-5 py-8 text-center',
      [p(classes: 'm-0 text-sm $textMuted', [Component.text(message)])],
    );
  }

  Component _vehicleCard(
    Map<String, dynamic> r, {
    required TranyxAppState s,
    required bool isDark,
    required String card,
    required String textPrimary,
    required String textSecondary,
    required String textMuted,
  }) {
    final brand = (r['brand'] ?? '').toString().trim();
    final model = (r['model'] ?? '').toString().trim();
    final year = (r['year'] ?? '').toString().trim();
    var title = '$brand $model'.trim();
    if (title.isEmpty) title = (r['title'] ?? 'Vehicle').toString();
    if (year.isNotEmpty && !title.contains(year)) title = '$title $year'.trim();

    final type = (r['type'] ?? r['vehicleType'] ?? '').toString();
    final transmission = (r['transmission'] ?? '').toString();
    final seats = r['seats'] ?? r['seatCount'];
    final metaParts = <String>[];
    if (type.isNotEmpty) metaParts.add(type[0].toUpperCase() + type.substring(1));
    if (transmission.isNotEmpty) metaParts.add(transmission);
    if (seats != null && seats.toString().isNotEmpty) metaParts.add('$seats seats');

    final priceVal = (r['priceDaily'] as num?)?.toDouble() ?? (r['dailyRate'] as num?)?.toDouble() ?? 0.0;
    final priceLabel = priceVal > 0 ? '₱ ${priceVal.toStringAsFixed(0)}/day' : 'Price on join';

    final lat = (r['pickupLat'] as num?)?.toDouble();
    final lng = (r['pickupLng'] as num?)?.toDouble();
    final cityHint = (r['pickupCity'] ?? r['city'] ?? r['area'] ?? '').toString();
    final area = _approxAreaLabel(lat: lat, lng: lng, s: s, cityHint: cityHint);

    final photoUrl =
        r['frontPhotoUrl'] ?? r['frontPhoto'] ?? r['photoUrl'] ?? r['interiorPhotoUrl'] ?? r['backPhotoUrl'];
    final hasPhoto = photoUrl != null && photoUrl.toString().isNotEmpty && photoUrl.toString() != 'null';
    final rating = (r['rating'] as num?)?.toDouble() ?? (r['hostRating'] as num?)?.toDouble();

    return div(
      classes:
          '$card rounded-[20px] overflow-hidden flex flex-col cursor-pointer hover:border-[#4f46e5]/40 transition-colors',
      events: {'click': (_) => s.promptGuestSignUp()},
      [
        div(
          classes:
              'relative h-[140px] overflow-hidden ${hasPhoto ? "" : "bg-gradient-to-r from-indigo-200 to-violet-400 ${isDark ? "opacity-80" : ""}"}',
          [
            if (hasPhoto)
              img(
                src: photoUrl.toString(),
                classes: 'absolute inset-0 w-full h-full object-cover ${isDark ? "opacity-90" : ""}',
                attributes: {'alt': title},
              ),
            span(
              classes:
                  'absolute top-3 left-3 px-2.5 h-6 inline-flex items-center rounded-full text-xs font-semibold bg-emerald-50 text-emerald-700',
              [Component.text('Available')],
            ),
          ],
        ),
        div(classes: 'p-4 flex flex-col gap-1.5', [
          p(classes: 'm-0 font-semibold text-[15px] $textPrimary', [Component.text(title)]),
          if (metaParts.isNotEmpty)
            p(classes: 'm-0 text-xs font-medium $textSecondary', [Component.text(metaParts.join(' • '))]),
          div(classes: 'flex items-center gap-1 $textMuted', [
            img(
              src: '/images/w05/3a723.svg',
              classes: 'size-3.5 ${isDark ? "opacity-70 invert" : ""}',
              attributes: {'alt': ''},
            ),
            span(classes: 'text-xs', [Component.text(area)]),
          ]),
          div(classes: 'flex items-center justify-between pt-1.5', [
            p(classes: 'm-0 font-semibold text-[17px] $textPrimary', [Component.text(priceLabel)]),
            if (rating != null)
              div(classes: 'flex items-center gap-1', [
                img(src: '/images/w05/f1da2.svg', classes: 'size-3.5', attributes: {'alt': ''}),
                span(
                  classes: 'text-xs font-medium $textSecondary',
                  [Component.text(rating.toStringAsFixed(1))],
                ),
              ]),
          ]),
        ]),
      ],
    );
  }

  Component _propertyCard(
    PropertyRental prop, {
    required TranyxAppState s,
    required bool isDark,
    required String card,
    required String textPrimary,
    required String textSecondary,
    required String textMuted,
  }) {
    final metaParts = <String>[
      prop.category.label,
      prop.type.label,
    ];
    final priceLabel = prop.priceMonthly > 0
        ? '₱ ${prop.priceMonthly.toStringAsFixed(0)}/mo'
        : (prop.priceDaily > 0 ? '₱ ${prop.priceDaily.toStringAsFixed(0)}/day' : 'Price on join');
    // Guests only see approximate distance — exact address unlocks after signup.
    final area = _approxAreaLabel(
      lat: prop.latitude,
      lng: prop.longitude,
      s: s,
    );
    final hasPhoto = prop.photoUrls.isNotEmpty && prop.photoUrls.first.isNotEmpty;

    return div(
      classes:
          '$card rounded-[20px] overflow-hidden flex flex-col cursor-pointer hover:border-[#4f46e5]/40 transition-colors',
      events: {'click': (_) => s.promptGuestSignUp()},
      [
        div(
          classes:
              'relative h-[140px] overflow-hidden ${hasPhoto ? "" : "bg-gradient-to-r from-sky-200 to-violet-300 ${isDark ? "opacity-80" : ""}"}',
          [
            if (hasPhoto)
              img(
                src: prop.photoUrls.first,
                classes: 'absolute inset-0 w-full h-full object-cover ${isDark ? "opacity-90" : ""}',
                attributes: {'alt': prop.title},
              ),
            span(
              classes:
                  'absolute top-3 left-3 px-2.5 h-6 inline-flex items-center rounded-full text-xs font-semibold bg-emerald-50 text-emerald-700',
              [Component.text('Available')],
            ),
          ],
        ),
        div(classes: 'p-4 flex flex-col gap-1.5', [
          p(classes: 'm-0 font-semibold text-[15px] $textPrimary', [Component.text(prop.title)]),
          p(classes: 'm-0 text-xs font-medium $textSecondary', [Component.text(metaParts.join(' • '))]),
          div(classes: 'flex items-center gap-1 $textMuted', [
            img(
              src: '/images/w05/3a723.svg',
              classes: 'size-3.5 ${isDark ? "opacity-70 invert" : ""}',
              attributes: {'alt': ''},
            ),
            span(classes: 'text-xs', [Component.text(area)]),
          ]),
          div(classes: 'flex items-center justify-between pt-1.5', [
            p(classes: 'm-0 font-semibold text-[17px] $textPrimary', [Component.text(priceLabel)]),
          ]),
        ]),
      ],
    );
  }

  Component _sectionHeader({
    required String title,
    required String action,
    required void Function() onAction,
    required String textPrimary,
    required String link,
  }) {
    return div(classes: 'flex items-center justify-between', [
      h2(classes: 'm-0 text-lg font-bold $textPrimary', [Component.text(title)]),
      button(
        classes:
            'font-semibold text-sm $link bg-transparent border-0 cursor-pointer hover:underline flex items-center gap-1',
        attributes: {'type': 'button'},
        events: {'click': (_) => onAction()},
        [
          Component.text(action),
          img(src: '/images/w05/b5f41.svg', classes: 'size-4', attributes: {'alt': ''}),
        ],
      ),
    ]);
  }

  Component _lockedRow({
    required bool isDark,
    required String icon,
    required String title,
    required String body,
    required void Function() onSignUp,
    required String textPrimary,
    required String textSecondary,
  }) {
    return div(
      classes:
          'rounded-2xl px-4 py-4 flex flex-col sm:flex-row sm:items-center gap-3 '
          '${isDark ? "bg-zinc-900/80 border border-zinc-800" : "bg-zinc-100 border border-zinc-200"}',
      [
        div(classes: 'flex items-start gap-3 flex-1 min-w-0', [
          div(
            classes:
                'size-10 rounded-xl flex items-center justify-center shrink-0 ${isDark ? "bg-zinc-800 text-zinc-400" : "bg-white text-zinc-500 border border-zinc-200"}',
            [lIcon(icon, cls: 'w-5 h-5')],
          ),
          div(classes: 'min-w-0', [
            div(classes: 'flex items-center gap-2', [
              p(classes: 'm-0 font-semibold text-sm $textPrimary', [Component.text(title)]),
              img(
                src: '/images/w05/295b0.svg',
                classes: 'size-3.5 ${isDark ? "opacity-70 invert" : ""}',
                attributes: {'alt': 'Locked'},
              ),
            ]),
            p(classes: 'm-0 text-xs mt-0.5 $textSecondary', [Component.text(body)]),
          ]),
        ]),
        button(
          classes:
              'h-10 px-4 rounded-xl font-semibold text-sm text-[#4f46e5] border border-[#4f46e5]/30 bg-transparent cursor-pointer hover:bg-[#4f46e5]/10 shrink-0',
          attributes: {'type': 'button'},
          events: {'click': (_) => onSignUp()},
          [Component.text('Sign up')],
        ),
      ],
    );
  }
}

/// Shown when a guest hits a locked tab (Messages / Profile).
class GuestLockedPane extends StatelessComponent {
  final TranyxAppState state;
  final String title;
  final String body;
  const GuestLockedPane({required this.state, required this.title, required this.body, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    return div(
      classes:
          'w05-locked max-w-lg mx-auto mt-16 text-center space-y-4 font-dm-sans animate-fade-up '
          '${isDark ? "text-zinc-50" : "text-[#18181b]"}',
      [
        div(
          classes:
              'mx-auto size-14 rounded-2xl flex items-center justify-center ${isDark ? "bg-zinc-800" : "bg-[#eef2ff]"}',
          [lIcon('lock', cls: 'w-6 h-6 text-[#4f46e5]')],
        ),
        h2(classes: 'm-0 text-2xl font-bold', [Component.text(title)]),
        p(classes: 'm-0 text-sm ${isDark ? "text-zinc-400" : "text-[#52525b]"}', [Component.text(body)]),
        div(classes: 'flex items-center justify-center gap-3 pt-2', [
          button(
            classes:
                'h-11 px-5 rounded-xl font-semibold text-sm text-white bg-[#4f46e5] border-0 cursor-pointer',
            attributes: {'type': 'button'},
            events: {'click': (_) => s.promptGuestSignUp()},
            [Component.text('Create account')],
          ),
          button(
            classes:
                'h-11 px-5 rounded-xl font-semibold text-sm border cursor-pointer '
                '${isDark ? "bg-zinc-900 border-zinc-700 text-zinc-100" : "bg-white border-[#d4d4d8] text-[#18181b]"}',
            attributes: {'type': 'button'},
            events: {'click': (_) => s.promptGuestSignIn()},
            [Component.text('Sign In')],
          ),
        ]),
      ],
    );
  }
}
