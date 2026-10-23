import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import '../../services/web_interop.dart';
import 'package:shared/shared.dart';
import '../utils/geo_helper.dart';

class HomeViewComponent extends StatefulComponent {
  final TranyxAppState state;
  const HomeViewComponent({required this.state, super.key});

  @override
  State<HomeViewComponent> createState() => HomeViewComponentState();
}

class HomeViewComponentState extends State<HomeViewComponent> {
  String _homeTab = 'dashboard';
  List<NewsPost>? _newsPosts;
  bool _isLoadingNews = false;
  String? _newsError;

  // Redeem promo state
  String _promoCodeInput = '';
  bool _isRedeeming = false;
  String? _redeemFeedback;
  bool _redeemSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  void _loadNews() async {
    setState(() {
      _isLoadingNews = true;
      _newsError = null;
    });
    try {
      final posts = await component.state.firestore.getAllActiveNewsPosts();
      setState(() {
        _newsPosts = posts;
        _isLoadingNews = false;
      });
    } catch (e) {
      setState(() {
        _newsError = e.toString();
        _isLoadingNews = false;
      });
    }
  }

  void _redeemPromo() async {
    final code = _promoCodeInput.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _isRedeeming = true;
      _redeemFeedback = null;
      _redeemSuccess = false;
    });

    try {
      final user = component.state.userProfile;
      if (user == null) throw Exception('User profile not loaded');

      final errorMsg = await component.state.firestore.redeemPromoToProfile(code, user.uid);
      if (errorMsg != null) {
        setState(() {
          _redeemFeedback = errorMsg;
          _redeemSuccess = false;
        });
        return;
      }

      await component.state.loadUserProfile();

      setState(() {
        _redeemFeedback = 'Promo code "$code" applied successfully!';
        _redeemSuccess = true;
        _promoCodeInput = '';
      });
    } catch (e) {
      setState(() {
        _redeemFeedback = 'Failed to redeem promo: $e';
        _redeemSuccess = false;
      });
    } finally {
      setState(() {
        _isRedeeming = false;
      });
    }
  }

  void _handleNewsPostAction(NewsPost post) async {
    if (post.actionType == 'promo' && post.promoCode != null) {
      setState(() {
        _isRedeeming = true;
        _redeemFeedback = null;
        _redeemSuccess = false;
      });
      try {
        final user = component.state.userProfile;
        if (user == null) return;

        final errorMsg = await component.state.firestore.redeemPromoToProfile(post.promoCode!, user.uid);
        if (errorMsg != null) {
          setState(() {
            _redeemFeedback = errorMsg;
            _redeemSuccess = false;
            _homeTab = 'news';
          });
          return;
        }

        await component.state.loadUserProfile();
        setState(() {
          _redeemFeedback = 'Promo code "${post.promoCode}" applied successfully!';
          _redeemSuccess = true;
          _homeTab = 'news';
        });
      } catch (e) {
        setState(() {
          _redeemFeedback = 'Failed to apply promo: $e';
          _redeemSuccess = false;
          _homeTab = 'news';
        });
      } finally {
        setState(() {
          _isRedeeming = false;
        });
      }
    } else if ((post.actionType == 'link' || post.actionType == 'promo') && post.actionUrl != null) {
      final url = post.actionUrl!.trim();
      if (url.startsWith('/') || url.startsWith('tranyx://')) {
        final cleanPath = url.replaceAll('tranyx://', '/');
        if (cleanPath.startsWith('/profile')) {
          component.state.setState(() => component.state.activeTab = AppTab.profile);
        } else if (cleanPath.startsWith('/transit')) {
          component.state.setState(() => component.state.activeTab = AppTab.transit);
        } else if (cleanPath.startsWith('/jobs')) {
          component.state.setState(() => component.state.activeTab = AppTab.jobs);
        } else {
          component.state.setState(() => component.state.activeTab = AppTab.home);
        }
      } else {
        web.window.open(url, '_blank');
      }
    }
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final isNyxian = s.currentViewMode == AccountType.nyxian;
    final isHybrid = s.accountType == AccountType.hybrid;

    final localVehicles =
        s.realtimeRentals.where((r) {
          if (r['status'] != 'Available' || r['hostId'] == s.userProfile?.uid) return false;
          final lat = (r['pickupLat'] as num?)?.toDouble();
          final lng = (r['pickupLng'] as num?)?.toDouble();
          if (lat == null || lng == null) return false;
          final dist = calculateDistance(s.userLatitude, s.userLongitude, lat, lng);
          return dist <= 30.0;
        }).toList()..sort((vA, vB) {
          final latA = (vA['pickupLat'] as num?)?.toDouble();
          final lngA = (vA['pickupLng'] as num?)?.toDouble();
          final distA = calculateDistance(s.userLatitude, s.userLongitude, latA, lngA);

          final latB = (vB['pickupLat'] as num?)?.toDouble();
          final lngB = (vB['pickupLng'] as num?)?.toDouble();
          final distB = calculateDistance(s.userLatitude, s.userLongitude, latB, lngB);

          return distA.compareTo(distB);
        });

    final localProperties =
        s.realtimeProperties.where((prop) {
          if (prop.status != 'Available' || prop.hostId == s.userProfile?.uid) return false;
          final dist = calculateDistance(s.userLatitude, s.userLongitude, prop.latitude, prop.longitude);
          return dist <= 30.0;
        }).toList()..sort((pA, pB) {
          final distA = calculateDistance(s.userLatitude, s.userLongitude, pA.latitude, pA.longitude);
          final distB = calculateDistance(s.userLatitude, s.userLongitude, pB.latitude, pB.longitude);
          return distA.compareTo(distB);
        });

    return div(classes: 'space-y-8 animate-fade-up', [
      // ── Hybrid mode switcher ──────────────────────────────
      if (isHybrid)
        segmentedControl(
          options: const [('Find Services', 'employer'), ('Work as Nyxian', 'nyxian')],
          selected: s.hybridToggle == AccountType.nyxian ? 'nyxian' : 'employer',
          isDark: isDark,
          onChange: (v) {
            s.setState(() => s.hybridToggle = v == 'nyxian' ? AccountType.nyxian : AccountType.employer);
            s.loadHoldbacks();
          },
        ),

      // ── Hero header ──────────────────────────────────────
      div(classes: 'space-y-3', [
        h1(
          classes:
              'text-3xl md:text-4xl font-extrabold tracking-tight leading-tight logo-gradient bg-clip-text text-transparent',
          [
            Component.text(
              isHybrid
                  ? 'All-Access Hub. Hire Services, Find Jobs & Rent Anything.'
                  : (isNyxian
                        ? 'Find Jobs. Hire Services. Rent Anything.'
                        : 'Hire Services. Find Jobs. Rent Anything.'),
            ),
          ],
        ),
        p(classes: 'text-base md:text-lg ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
          Component.text(
            isHybrid
                ? 'Seamlessly switch between hiring top Nyxian talent and earning on available jobs & assets with full platform privileges.'
                : (isNyxian
                      ? 'Browse available jobs in your area, track transit routes, and start earning.'
                      : 'Connect with verified Nyxians, rent assets, and get tasks done safely.'),
          ),
        ]),
      ]),

      // ── Home Tab Selector (W10 pill segments) ─────────────
      div(
        classes:
            'inline-flex gap-1 p-1 rounded-[14px] border '
            '${isDark ? "bg-zinc-900 border-zinc-800" : "bg-[#fafafa] border-[#e4e4e7]"}',
        [
          button(
            classes:
                'h-9 px-4 rounded-[10px] text-sm font-semibold transition-all border-0 cursor-pointer '
                '${_homeTab == 'dashboard'
                    ? (isDark
                        ? "bg-zinc-800 text-zinc-50 shadow"
                        : "bg-white text-[#18181b] shadow-[0_4px_12px_rgba(9,9,11,0.04),0_1px_2px_rgba(9,9,11,0.06)]")
                    : (isDark ? "bg-transparent text-zinc-400" : "bg-transparent text-[#52525b]")}',
            attributes: {'type': 'button'},
            events: {'click': (_) => setState(() => _homeTab = 'dashboard')},
            [Component.text('Dashboard')],
          ),
          button(
            classes:
                'h-9 px-4 rounded-[10px] text-sm font-semibold transition-all border-0 cursor-pointer '
                '${_homeTab == 'news'
                    ? (isDark
                        ? "bg-zinc-800 text-zinc-50 shadow"
                        : "bg-white text-[#18181b] shadow-[0_4px_12px_rgba(9,9,11,0.04),0_1px_2px_rgba(9,9,11,0.06)]")
                    : (isDark ? "bg-transparent text-zinc-400" : "bg-transparent text-[#52525b]")}',
            attributes: {'type': 'button'},
            events: {'click': (_) => setState(() => _homeTab = 'news')},
            [Component.text('News')],
          ),
        ],
      ),

      if (_homeTab == 'news') ...[
        // Promo redemption form
        div(
          classes:
              'p-6 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"} space-y-4',
          [
            p(classes: 'text-lg font-bold ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
              Component.text('Have a Promo Code?'),
            ]),
            p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
              Component.text('Enter your promo code below to apply discounts to your account.'),
            ]),
            div(classes: 'flex gap-3', [
              input(
                classes:
                    'px-4 py-3 rounded-xl border outline-none flex-1 text-sm ${isDark ? "bg-zinc-950 border-zinc-800 text-zinc-200 placeholder-zinc-600 focus:border-zinc-700" : "bg-zinc-50 border-zinc-200 text-zinc-800 placeholder-zinc-400 focus:border-zinc-300"}',
                type: InputType.text,
                attributes: {
                  'placeholder': 'Enter Promo Code...',
                  'value': _promoCodeInput,
                },
                events: {
                  'input': (e) => _promoCodeInput = getInputValue(e.target),
                },
              ),
              button(
                classes:
                    'px-6 py-3 rounded-xl font-bold text-white bg-indigo-600 hover:bg-indigo-500 transition-colors flex items-center justify-center min-w-[100px]',
                events: {'click': (_) => _redeemPromo()},
                [
                  if (_isRedeeming)
                    div(classes: 'w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin', [])
                  else
                    Component.text('Redeem'),
                ],
              ),
            ]),
            if (_redeemFeedback != null)
              p(
                classes: 'text-sm font-bold mt-2 ${_redeemSuccess ? "text-green-500" : "text-red-500"}',
                [Component.text(_redeemFeedback!)],
              ),
          ],
        ),

        // Active News & Promos posts list
        if (_isLoadingNews)
          div(classes: 'flex justify-center py-12', [
            div(classes: 'w-8 h-8 border-4 border-indigo-500 border-t-transparent rounded-full animate-spin', []),
          ])
        else if (_newsError != null)
          div(classes: 'text-center text-red-500 py-12', [
            Component.text('Error: $_newsError'),
          ])
        else if (_newsPosts == null || _newsPosts!.isEmpty)
          div(classes: 'text-center py-16 space-y-4', [
            div(classes: 'flex justify-center', [
              lIcon('rss', cls: 'w-12 h-12 ${isDark ? "text-zinc-800" : "text-zinc-350"}'),
            ]),
            p(classes: 'text-sm font-bold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
              Component.text('No news or promotions available at this time.'),
            ]),
          ])
        else
          div(
            classes: 'grid grid-cols-1 md:grid-cols-2 gap-6',
            [
              for (final post in _newsPosts!)
                div(
                  classes:
                      'rounded-2xl border overflow-hidden flex flex-col ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"}',
                  [
                    if (post.imageUrl.isNotEmpty)
                      div(
                        classes: 'relative w-full aspect-video bg-zinc-950 overflow-hidden group',
                        [
                          img(
                            src: post.imageUrl,
                            classes:
                                'w-full h-full object-cover cursor-pointer hover:scale-105 transition-transform duration-300',
                            events: {
                              'click': (_) => _handleNewsPostAction(post),
                            },
                          ),
                          if (post.buttonText != null &&
                              post.buttonText!.isNotEmpty &&
                              post.buttonX != null &&
                              post.buttonY != null &&
                              post.buttonWidth != null &&
                              post.buttonHeight != null)
                            button(
                              classes:
                                  'absolute font-bold transition-all shadow-lg flex items-center justify-center text-xs md:text-sm',
                              attributes: {
                                'style':
                                    'left: ${post.buttonX}%; top: ${post.buttonY}%; width: ${post.buttonWidth}%; height: ${post.buttonHeight}%; box-sizing: border-box; '
                                    'background-color: ${post.buttonBgColor ?? '#4f46e5'}; '
                                    'color: ${post.buttonTextColor ?? '#ffffff'}; '
                                    'border: ${post.buttonBorderWidth ?? 1}px solid ${post.buttonBorderColor ?? '#4f46e5'}; '
                                    'border-radius: ${post.buttonBorderRadius ?? 8}px; '
                                    'padding: ${post.buttonPaddingV ?? 8}px ${post.buttonPaddingH ?? 16}px;',
                              },
                              events: {
                                'click': (_) => _handleNewsPostAction(post),
                              },
                              [Component.text(post.buttonText!)],
                            ),
                        ],
                      ),

                    div(classes: 'p-5 flex-1 flex flex-col justify-between space-y-4', [
                      div(classes: 'space-y-3', [
                        div(classes: 'flex items-center justify-between', [
                          span(
                            classes:
                                'px-2.5 py-1 rounded-md text-[10px] font-bold tracking-wide uppercase ${post.category == 'promo'
                                    ? 'bg-green-500/10 text-green-400'
                                    : post.category == 'news'
                                    ? 'bg-indigo-500/10 text-indigo-400'
                                    : post.category == 'announcement'
                                    ? 'bg-amber-500/10 text-amber-400'
                                    : 'bg-purple-500/10 text-purple-400'}',
                            [Component.text(post.category)],
                          ),
                          span(classes: 'text-xs text-zinc-500', [
                            Component.text(
                              DateTime.now().difference(post.createdAt).inDays == 0
                                  ? 'Today'
                                  : '${post.createdAt.month}/${post.createdAt.day}/${post.createdAt.year}',
                            ),
                          ]),
                        ]),
                        h3(classes: 'text-lg font-bold text-zinc-200', [
                          Component.text(post.title),
                        ]),
                        p(classes: 'text-sm text-zinc-450 leading-relaxed', [
                          Component.text(post.content),
                        ]),
                      ]),
                    ]),
                  ],
                ),
            ],
          ),
      ] else ...[
        // ── Global Search Bar (Nyxian Only) ───────────────────
        if (isNyxian)
          div(
            classes:
                'flex items-center gap-3 p-4 rounded-2xl border transition-colors ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"}',
            [
              lIcon('search', cls: 'w-5 h-5 ${isDark ? "text-zinc-600" : "text-zinc-400"} flex-shrink-0'),
              input(
                classes:
                    'bg-transparent border-none outline-none flex-1 text-sm md:text-base ${isDark ? "text-zinc-200 placeholder-zinc-600" : "text-zinc-800 placeholder-zinc-400"}',
                type: InputType.search,
                attributes: {
                  'placeholder': 'Search available gigs...',
                  'value': s.homeSearchQuery,
                  'id': 'home-search-input',
                  'name': 'search',
                },
                events: {
                  'input': (e) {
                    s.setState(() => s.homeSearchQuery = getInputValue(e.target));
                  },
                  'keydown': (e) {
                    final key = (e as web.KeyboardEvent).key;
                    if (key == 'Enter') s.handleHomeSearch(s.homeSearchQuery);
                  },
                },
              ),
              button(
                classes:
                    'flex-shrink-0 px-4 py-2 rounded-xl text-sm font-semibold text-white logo-gradient hover:opacity-90 transition-opacity',
                events: {'click': (_) => s.handleHomeSearch(s.homeSearchQuery)},
                [Component.text('Search')],
              ),
            ],
          ),

        // ── W10 wallet + current gig (Nyxian ≥1280 side-by-side) ──
        if (isNyxian)
          _walletAndCurrentGigRow(isDark: isDark, s: s)
        else ...[
          _quickStatsBar(isDark: isDark, isNyxian: isNyxian, s: s),
          _ongoingWidget(isDark: isDark, isNyxian: isNyxian, s: s),
        ],

        // ── Active P2P Transactions (Deposits & Withdrawals) ──
        _activeP2pTransactionsBanner(isDark: isDark, s: s),

        // ── W10 Nyxian stats (3-up; wallet lives in hero card) ─
        if (isNyxian) _nyxianStatsRow(isDark: isDark, s: s),

        // ── Active Trackers & Trips ───────────────────────────
        _activeTrackersSection(isDark: isDark, s: s),

        if (isNyxian) ...[
          // ── Top Services Grid (live chip filters → W20) ────────
          _topServicesSection(isDark: isDark, s: s),

          // ── Nearby Rentals (live vehicles + properties) ────────
          _nearbyRentalsSection(
            isDark: isDark,
            s: s,
            vehicles: localVehicles,
            properties: localProperties,
          ),

          // ── Transit Teaser ────────────────────────────────────
          _transitTeaser(isDark: isDark, onTap: () => s.switchTab(AppTab.transit)),

          // ── Real Estate Teaser ────────────────────────────────
          _realEstateTeaser(isDark: isDark, s: s),
        ] else ...[
          // Employer view: Proximity-sorted rentals carousels
          _nearMeRentalsSection(
            title: '🚗 Vehicles Near Me',
            items: localVehicles.take(4).toList(),
            isProperty: false,
            isDark: isDark,
            s: s,
          ),

          _nearMeRentalsSection(
            title: '🏢 Real Estate Near Me',
            items: localProperties.take(4).toList(),
            isProperty: true,
            isDark: isDark,
            s: s,
          ),
        ],
      ],
    ]);
  }

  Component _activeP2pTransactionsBanner({required bool isDark, required TranyxAppState s}) {
    final depReq = s.activeP2pDepositRequest;
    final withReq = s.activeP2pWithdrawalRequest;

    final isDepActive = depReq != null &&
        depReq.status != 'APPROVED' &&
        depReq.status != 'CANCELLED' &&
        depReq.status != 'REJECTED';

    final isWithActive = withReq != null &&
        withReq.status != 'APPROVED' &&
        withReq.status != 'CANCELLED' &&
        withReq.status != 'REJECTED';

    if (!isDepActive && !isWithActive) {
      return const Component.fragment([]);
    }

    return div(classes: 'space-y-4 animate-fade-in', [
      if (isDepActive)
        () {
          final req = depReq;
          final status = req.status.toUpperCase();
          String badgeText = 'Waiting for Agent';
          String statusDesc = 'Broadcasting to verified P2P agents...';
          String badgeColor = 'bg-amber-500/20 text-amber-300 border-amber-500/30';
          String pulseColor = 'bg-amber-400';

          if (status == 'AWAITING_PAYMENT') {
            badgeText = 'Agent QR Ready';
            statusDesc = 'Agent ${(req.agentName ?? "").isNotEmpty ? req.agentName : "assigned"}. Send payment & submit receipt.';
            badgeColor = 'bg-blue-500/20 text-blue-300 border-blue-500/30';
            pulseColor = 'bg-blue-400';
          } else if (status == 'PENDING_VERIFICATION') {
            badgeText = 'Verifying Proof';
            statusDesc = 'Receipt submitted. Agent is reviewing and crediting your balance.';
            badgeColor = 'bg-purple-500/20 text-purple-300 border-purple-500/30';
            pulseColor = 'bg-purple-400';
          }

          final elapsedSec = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(req.createdAt)).inSeconds;
          final canCancel = status == 'WAITING_FOR_AGENT' && elapsedSec >= 300;

          return div(
            classes:
                'p-5 rounded-3xl border border-indigo-500/30 bg-gradient-to-r from-indigo-950/70 via-purple-950/60 to-zinc-950/80 backdrop-blur-xl shadow-xl shadow-indigo-950/30 flex flex-col md:flex-row md:items-center justify-between gap-4 transition-all duration-300',
            [
              div(classes: 'flex items-start sm:items-center gap-4 min-w-0', [
                div(
                  classes:
                      'w-12 h-12 rounded-2xl bg-indigo-500/20 border border-indigo-500/30 flex items-center justify-center text-indigo-400 shrink-0 shadow-lg shadow-indigo-500/20',
                  [lIcon('arrow-down-circle', cls: 'w-6 h-6')],
                ),
                div(classes: 'min-w-0 space-y-1', [
                  div(classes: 'flex flex-wrap items-center gap-2', [
                    span(
                      classes:
                          'px-2.5 py-0.5 rounded-full text-[10px] font-black uppercase tracking-wider border $badgeColor flex items-center gap-1.5',
                      [
                        span(classes: 'w-2 h-2 rounded-full $pulseColor animate-pulse', []),
                        Component.text(badgeText),
                      ],
                    ),
                    span(
                      classes: 'text-xs font-bold text-zinc-400',
                      [Component.text('P2P Top-up • ${req.paymentMethod}')],
                    ),
                  ]),
                  div(classes: 'flex items-baseline gap-2', [
                    p(
                      classes: 'text-xl font-black text-white tracking-tight',
                      [Component.text('₱${req.amount.toStringAsFixed(2)}')],
                    ),
                    span(classes: 'text-xs text-zinc-400', [Component.text('(${req.amount.toInt()} TYX)')]),
                  ]),
                  p(classes: 'text-xs text-zinc-300 line-clamp-1', [Component.text(statusDesc)]),
                ]),
              ]),
              div(classes: 'flex items-center gap-2 self-end md:self-center shrink-0', [
                if (canCancel)
                  button(
                    classes:
                        'px-4 py-2.5 rounded-xl text-xs font-bold text-red-400 hover:text-red-300 hover:bg-red-500/10 border border-red-500/30 transition-all cursor-pointer',
                    events: {'click': (_) => s.handleCancelP2pOrder(req.id)},
                    [Component.text('Cancel Request')],
                  ),
                button(
                  classes:
                      'px-5 py-2.5 rounded-xl text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-500 shadow-lg shadow-indigo-600/30 transition-all cursor-pointer flex items-center gap-2 border-0 active:scale-95',
                  events: {
                    'click': (_) => s.setState(() {
                      s.selectedDepositRail = 'manual_p2p';
                      s.showDepositModal = true;
                    }),
                  },
                  [
                    lIcon('external-link', cls: 'w-4 h-4'),
                    Component.text('Resume Top-Up'),
                  ],
                ),
              ]),
            ],
          );
        }(),

      if (isWithActive &&
          !withReq.paymentMethod.toLowerCase().contains('solana'))
        () {
          final req = withReq;
          final status = req.status.toUpperCase();
          String badgeText = 'Waiting for Agent';
          String statusDesc = 'Broadcasting cashout to online agents...';
          String badgeColor = 'bg-amber-500/20 text-amber-300 border-amber-500/30';
          String pulseColor = 'bg-amber-400';

          if (status == 'AWAITING_AGENT_PAYMENT') {
            badgeText = 'Agent Processing';
            statusDesc = 'Agent ${(req.agentName ?? "").isNotEmpty ? req.agentName : "claimed"}. Disagreeing or transferring payout...';
            badgeColor = 'bg-blue-500/20 text-blue-300 border-blue-500/30';
            pulseColor = 'bg-blue-400';
          } else if (status == 'PENDING_CONFIRMATION') {
            badgeText = 'Payment Sent - Action Needed';
            statusDesc = 'Agent has sent payout! Check your ${req.paymentMethod} and confirm receipt.';
            badgeColor = 'bg-emerald-500/20 text-emerald-300 border-emerald-500/30';
            pulseColor = 'bg-emerald-400';
          }

          final elapsedSec = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(req.createdAt)).inSeconds;
          final canCancel = status == 'WAITING_FOR_AGENT' && elapsedSec >= 300;

          return div(
            classes:
                'p-5 rounded-3xl border border-emerald-500/30 bg-gradient-to-r from-emerald-950/70 via-teal-950/60 to-zinc-950/80 backdrop-blur-xl shadow-xl shadow-emerald-950/30 flex flex-col md:flex-row md:items-center justify-between gap-4 transition-all duration-300',
            [
              div(classes: 'flex items-start sm:items-center gap-4 min-w-0', [
                div(
                  classes:
                      'w-12 h-12 rounded-2xl bg-emerald-500/20 border border-emerald-500/30 flex items-center justify-center text-emerald-400 shrink-0 shadow-lg shadow-emerald-500/20',
                  [lIcon('arrow-up-circle', cls: 'w-6 h-6')],
                ),
                div(classes: 'min-w-0 space-y-1', [
                  div(classes: 'flex flex-wrap items-center gap-2', [
                    span(
                      classes:
                          'px-2.5 py-0.5 rounded-full text-[10px] font-black uppercase tracking-wider border $badgeColor flex items-center gap-1.5',
                      [
                        span(classes: 'w-2 h-2 rounded-full $pulseColor animate-pulse', []),
                        Component.text(badgeText),
                      ],
                    ),
                    span(
                      classes: 'text-xs font-bold text-zinc-400',
                      [Component.text('P2P Cashout • ${req.paymentMethod} (${req.userAccountNumber})')],
                    ),
                  ]),
                  div(classes: 'flex items-baseline gap-2', [
                    p(
                      classes: 'text-xl font-black text-white tracking-tight',
                      [Component.text('₱${req.amount.toStringAsFixed(2)}')],
                    ),
                    span(classes: 'text-xs text-zinc-400', [Component.text('Net: ₱${req.netAmount.toStringAsFixed(2)}')]),
                  ]),
                  p(classes: 'text-xs text-zinc-300 line-clamp-1', [Component.text(statusDesc)]),
                ]),
              ]),
              div(classes: 'flex items-center gap-2 self-end md:self-center shrink-0', [
                if (status == 'PENDING_CONFIRMATION')
                  button(
                    classes:
                        'px-4 py-2.5 rounded-xl text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-500 shadow-lg shadow-emerald-600/30 transition-all cursor-pointer flex items-center gap-1.5 border-0 active:scale-95',
                    events: {'click': (_) => s.handleConfirmP2pWithdrawalReceived(req.id)},
                    [
                      lIcon('check-circle', cls: 'w-4 h-4'),
                      Component.text('Confirm Received'),
                    ],
                  )
                else if (canCancel)
                  button(
                    classes:
                        'px-4 py-2.5 rounded-xl text-xs font-bold text-red-400 hover:text-red-300 hover:bg-red-500/10 border border-red-500/30 transition-all cursor-pointer',
                    events: {'click': (_) => s.handleCancelP2pWithdrawal(req.id)},
                    [Component.text('Cancel & Refund')],
                  ),
                button(
                  classes:
                      'px-5 py-2.5 rounded-xl text-xs font-bold text-white bg-purple-600 hover:bg-purple-500 shadow-lg shadow-purple-600/30 transition-all cursor-pointer flex items-center gap-2 border-0 active:scale-95',
                  events: {
                    'click': (_) => s.setState(() {
                      s.selectedWithdrawRail = 'manual_p2p';
                      s.activeP2pWithdrawalId = req.id;
                      s.activeP2pWithdrawalRequest = req;
                      s.showWithdrawModal = true;
                    }),
                  },
                  [
                    lIcon('external-link', cls: 'w-4 h-4'),
                    Component.text('Track Cashout'),
                  ],
                ),
              ]),
            ],
          );
        }(),
    ]);
  }

  Component _ongoingWidget({required bool isDark, required bool isNyxian, required TranyxAppState s}) {
    final job = s.ongoingJob;

    if (isNyxian) {
      if (job != null) {
        final title = job['title'] as String? ?? 'Current Gig';
        final rate = '\u20b1 ${(job['pricingValue'] as num?)?.toStringAsFixed(0) ?? "0"}';
        return div(
          classes: 'p-5 rounded-2xl border border-green-500/30 bg-green-500/10 card-hover',
          [
            div(classes: 'flex items-center justify-between mb-3', [
              div(classes: 'flex items-center gap-3', [
                div(classes: 'p-2 rounded-xl bg-green-500/20', [lIcon('zap', cls: 'w-5 h-5 text-green-400')]),
                div([
                  p(classes: 'text-xs font-semibold text-green-400 uppercase tracking-wider', [
                    Component.text('Current Gig'),
                  ]),
                  p(classes: 'font-bold text-base', [Component.text(title)]),
                ]),
              ]),
              span(classes: 'px-3 py-1.5 rounded-lg text-xs font-bold bg-green-500/20 text-green-400 animate-pulse', [
                Component.text('LIVE'),
              ]),
            ]),
            div(classes: 'flex items-center justify-between', [
              span(classes: 'font-bold text-green-300 text-lg', [Component.text(rate)]),
              div(classes: 'flex items-center gap-2', [
                button(
                  classes:
                      'px-4 py-2.5 rounded-xl text-sm font-semibold text-white bg-green-500 hover:bg-green-400 transition-colors',
                  events: {'click': (_) => s.selectJobAndLoadDetails(job)},
                  [Component.text('View Details')],
                ),
                () {
                  final jId = job['id'] as String;
                  final acceptedId = job['acceptedApplicantId'] as String? ?? s.userProfile?.uid ?? SessionStorage.uid ?? '';
                  final scopedChatId = acceptedId.isNotEmpty ? 'job_${jId}_$acceptedId' : jId;
                  return button(
                    classes:
                        'px-4 py-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-zinc-350" : "border-zinc-200 hover:bg-zinc-100 text-zinc-700"} transition-colors relative',
                    events: {
                      'click': (_) => s.openChat(
                            scopedChatId,
                            title: job['title'] as String?,
                            counterpartyName: job['creatorName'] as String?,
                          ),
                    },
                    [
                      lIcon('message-square', cls: 'w-4 h-4'),
                      if (s.getUnreadChatCount(scopedChatId) > 0)
                        span(
                          classes:
                              'absolute -top-1.5 -right-1.5 px-2 py-0.5 text-[10px] font-black text-white bg-red-500 rounded-full border-2 ${isDark ? "border-zinc-900" : "border-white"} animate-pulse',
                          [Component.text('${s.getUnreadChatCount(scopedChatId)}')],
                        ),
                    ],
                  );
                }(),
              ]),
            ]),
          ],
        );
      }
      // No ongoing gig
      return div(
        classes:
            'p-5 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-900/40" : "border-zinc-200 bg-zinc-50"} flex items-center gap-3',
        [
          div(classes: 'p-2 rounded-xl bg-zinc-700/30', [lIcon('zap', cls: 'w-5 h-5 text-zinc-500')]),
          p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
            Component.text('No active gig. Browse available jobs below.'),
          ]),
        ],
      );
    }

    // Employer
    if (job != null) {
      final title = job['title'] as String? ?? 'Active Job';
      final applicants = (job['applicantCount'] as int?) ?? 0;
      return div(
        classes: 'p-5 rounded-2xl border border-blue-500/30 bg-blue-500/10 card-hover',
        [
          div(classes: 'flex items-center justify-between mb-3', [
            div(classes: 'flex items-center gap-3', [
              div(classes: 'p-2 rounded-xl bg-blue-500/20', [lIcon('briefcase', cls: 'w-5 h-5 text-blue-400')]),
              div([
                p(classes: 'text-xs font-semibold text-blue-400 uppercase tracking-wider', [
                  Component.text('Ongoing Job'),
                ]),
                p(classes: 'font-bold text-base', [Component.text(title)]),
              ]),
            ]),
            span(classes: 'px-3 py-1.5 rounded-lg text-xs font-bold bg-blue-500/20 text-blue-400', [
              Component.text('ACTIVE'),
            ]),
          ]),
          div(classes: 'flex items-center justify-between', [
            p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
              Component.text('$applicants applicant${applicants == 1 ? "" : "s"}'),
            ]),
            div(classes: 'flex items-center gap-2', [
              button(
                classes:
                    'flex items-center gap-2 px-4 py-2.5 rounded-xl text-sm font-semibold logo-gradient text-white transition-opacity',
                events: {'click': (_) => s.selectJobAndLoadDetails(job)},
                [lIcon('users', cls: 'w-4 h-4'), Component.text(' Manage')],
              ),
              () {
                final jId = job['id'] as String;
                final acceptedId = job['acceptedApplicantId'] as String? ?? '';
                final scopedChatId = acceptedId.isNotEmpty ? 'job_${jId}_$acceptedId' : jId;
                return button(
                  classes:
                      'px-4 py-2.5 rounded-xl text-sm font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-zinc-350" : "border-zinc-200 hover:bg-zinc-100 text-zinc-700"} transition-colors relative',
                  events: {
                    'click': (_) => s.openChat(
                          scopedChatId,
                          title: job['title'] as String?,
                          counterpartyName: job['acceptedApplicantName'] as String?,
                        ),
                  },
                  [
                    lIcon('message-square', cls: 'w-4 h-4'),
                    if (s.getUnreadChatCount(scopedChatId) > 0)
                      span(
                        classes:
                            'absolute -top-1.5 -right-1.5 px-2 py-0.5 text-[10px] font-black text-white bg-red-500 rounded-full border-2 ${isDark ? "border-zinc-900" : "border-white"} animate-pulse',
                        [Component.text('${s.getUnreadChatCount(scopedChatId)}')],
                      ),
                  ],
                );
              }(),
            ]),
          ]),
        ],
      );
    }

    return div(
      classes:
          'p-5 rounded-2xl border ${isDark ? "border-zinc-800 bg-zinc-900/40" : "border-zinc-200 bg-zinc-50"} flex items-center gap-3',
      [
        div(classes: 'p-2 rounded-xl bg-zinc-700/30', [lIcon('briefcase', cls: 'w-5 h-5 text-zinc-500')]),
        p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
          Component.text('No jobs in progress. Post a new job to get started.'),
        ]),
      ],
    );
  }

  Component _nearMeRentalsSection({
    required String title,
    required List<dynamic> items,
    required bool isProperty,
    required bool isDark,
    required TranyxAppState s,
  }) {
    final headerCls = isDark ? "text-white" : "text-zinc-900";

    return div([
      div(classes: 'flex items-center justify-between mb-4', [
        h2(classes: 'text-lg font-bold $headerCls', [Component.text(title)]),
        button(
          classes:
              'text-sm font-semibold text-indigo-400 hover:underline flex items-center gap-1 bg-transparent border-0 cursor-pointer',
          events: {
            'click': (_) {
              s.setState(() {
                s.activeTab = AppTab.transit;
                s.activeRentalCategory = isProperty ? RentalCategory.properties : RentalCategory.vehicles;
              });
            },
          },
          [Component.text('View All'), lIcon('chevron-right', cls: 'w-4 h-4')],
        ),
      ]),
      if (items.isEmpty)
        div(
          classes:
              'p-8 rounded-2xl border border-dashed border-zinc-800 text-zinc-500 bg-zinc-900/10 text-center font-medium text-sm',
          [Component.text('No listings available near you.')],
        )
      else
        div(classes: 'grid grid-cols-2 lg:grid-cols-4 gap-4', [
          for (final item in items) _nearMeCard(item, isProperty, isDark, s),
        ]),
    ]);
  }

  Component _nearMeCard(dynamic item, bool isProperty, bool isDark, TranyxAppState s) {
    final cardCls = isDark
        ? "bg-zinc-900 border-zinc-800 hover:border-purple-500/40"
        : "bg-white border-zinc-200 shadow-sm hover:shadow-md";

    if (isProperty) {
      final prop = item as PropertyRental;
      final hasPhoto = prop.photoUrls.isNotEmpty && prop.photoUrls.first.isNotEmpty;
      final dist = calculateDistance(s.userLatitude, s.userLongitude, prop.latitude, prop.longitude);

      return div(
        classes: 'p-4 rounded-2xl border transition-all cursor-pointer $cardCls',
        events: {
          'click': (_) => s.setState(() {
            s.selectedPropertyData = prop.toMap();
            s.showBookPropertyModal = true;
          }),
        },
        [
          div(
            classes: 'aspect-video w-full rounded-xl mb-3 overflow-hidden bg-zinc-800 relative',
            [
              if (hasPhoto)
                img(src: prop.photoUrls.first, classes: 'w-full h-full object-cover', attributes: {'alt': prop.title})
              else
                div(classes: 'w-full h-full flex items-center justify-center bg-zinc-850', [
                  lIcon('home', cls: 'w-8 h-8 text-zinc-650'),
                ]),
            ],
          ),
          h4(classes: 'font-bold text-sm line-clamp-1 text-zinc-200', [Component.text(prop.title)]),
          p(classes: 'text-[10px] text-zinc-500 mt-1 capitalize', [
            Component.text('${prop.category.name} • ${prop.type.name}'),
          ]),
          div(classes: 'flex items-center justify-between mt-3', [
            span(classes: 'font-extrabold text-purple-400 text-sm', [
              Component.text('₱ ${prop.priceMonthly.toStringAsFixed(0)}/mo'),
            ]),
            span(classes: 'text-[10px] text-zinc-500 flex items-center gap-0.5', [
              lIcon('map-pin', cls: 'w-3 h-3 text-purple-400'),
              Component.text('${dist.toStringAsFixed(1)} km'),
            ]),
          ]),
        ],
      );
    } else {
      final r = item as Map;
      final model = r['model'] ?? 'Vehicle';
      final brand = r['brand'] ?? 'Unknown';
      final photoUrl = r['frontPhotoUrl'] ?? r['frontPhoto'] ?? r['photoUrl'];
      final hasPhoto = photoUrl != null && photoUrl.toString().isNotEmpty && photoUrl.toString() != 'null';
      final pickupLat = (r['pickupLat'] as num?)?.toDouble();
      final pickupLng = (r['pickupLng'] as num?)?.toDouble();
      final dist = calculateDistance(s.userLatitude, s.userLongitude, pickupLat, pickupLng);
      final priceVal = r['priceDaily'] ?? r['dailyRate'];

      return div(
        classes: 'p-4 rounded-2xl border transition-all cursor-pointer $cardCls',
        events: {
          'click': (_) => s.setState(() {
            s.selectedRentalData = Map<String, dynamic>.from(r);
            s.showBookVehicleModal = true;
          }),
        },
        [
          div(
            classes: 'aspect-video w-full rounded-xl mb-3 overflow-hidden bg-zinc-850 relative',
            [
              if (hasPhoto)
                img(
                  src: photoUrl.toString(),
                  classes: 'w-full h-full object-cover',
                  attributes: {'alt': '$brand $model'},
                )
              else
                div(classes: 'w-full h-full flex items-center justify-center bg-zinc-800', [
                  lIcon('car', cls: 'w-8 h-8 text-zinc-650'),
                ]),
            ],
          ),
          h4(classes: 'font-bold text-sm line-clamp-1 text-zinc-200', [Component.text('$brand $model')]),
          p(classes: 'text-[10px] text-zinc-500 mt-1 capitalize', [
            Component.text(r['type'] ?? r['vehicleType'] ?? 'car'),
          ]),
          div(classes: 'flex items-center justify-between mt-3', [
            span(classes: 'font-extrabold text-purple-400 text-sm', [Component.text('₱ $priceVal/day')]),
            span(classes: 'text-[10px] text-zinc-500 flex items-center gap-0.5', [
              lIcon('map-pin', cls: 'w-3 h-3 text-purple-400'),
              Component.text('${dist.toStringAsFixed(1)} km'),
            ]),
          ]),
        ],
      );
    }
  }


  /// W10 purple Tyxbit wallet + Current Gig card (live data only).
  Component _walletAndCurrentGigRow({required bool isDark, required TranyxAppState s}) {
    final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
    final pendingTotal = s.pendingHoldbacks.fold<double>(
      0.0,
      (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0.0),
    );
    final job = s.ongoingJob;
    final surface = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-[#e4e4e7] shadow-sm';

    Component wallet = div(
      classes:
          'flex-1 min-w-[260px] rounded-3xl px-7 py-6 text-white '
          'bg-gradient-to-r from-[#4f46e5] to-[#7c3aed] '
          'shadow-[0_8px_20px_-6px_rgba(79,70,229,0.25)] flex flex-col gap-1.5',
      [
        div(classes: 'flex items-center gap-2', [
          lIcon('wallet', cls: 'w-[18px] h-[18px] text-white'),
          span(classes: 'flex-1 text-sm font-semibold', [Component.text('Tyxbit Wallet')]),
          span(classes: 'text-xs font-mono text-white/80', [Component.text('1 TYX = ₱1')]),
        ]),
        p(classes: 'm-0 text-[40px] leading-[48px] font-bold tracking-tight tabular-nums', [
          Component.text('₱ ${tyxBal.toStringAsFixed(2)}'),
        ]),
        p(classes: 'm-0 text-[13px] text-white/85', [
          Component.text(
            pendingTotal > 0
                ? '+ ₱${pendingTotal.toStringAsFixed(2)} Pending · releases when jobs complete'
                : 'Available balance · escrow releases when jobs complete',
          ),
        ]),
        div(classes: 'flex flex-wrap items-center gap-3 pt-3', [
          button(
            classes:
                'h-11 px-[18px] rounded-xl bg-white text-[#4f46e5] text-sm font-semibold '
                'border-0 cursor-pointer flex items-center gap-2 hover:opacity-95',
            attributes: {'type': 'button'},
            events: {
              'click': (_) => s.setState(() {
                s.showDepositModal = true;
              }),
            },
            [lIcon('plus', cls: 'w-[18px] h-[18px]'), Component.text('Deposit Tyx')],
          ),
          button(
            classes:
                'h-11 px-[18px] rounded-xl bg-white/16 border border-white/40 text-white text-sm font-semibold '
                'cursor-pointer flex items-center gap-2 hover:bg-white/25',
            attributes: {'type': 'button'},
            events: {
              'click': (_) => s.setState(() {
                s.showWithdrawModal = true;
              }),
            },
            [lIcon('arrow-up', cls: 'w-[18px] h-[18px]'), Component.text('Withdraw')],
          ),
          button(
            classes:
                'h-11 pl-3 text-white text-sm font-semibold bg-transparent border-0 cursor-pointer '
                'flex items-center gap-1.5 hover:underline',
            attributes: {'type': 'button'},
            events: {
              'click': (_) => s.setState(() {
                s.activeTab = AppTab.profile;
                s.profileView = ProfileView.history;
              }),
            },
            [Component.text('History'), lIcon('chevron-right', cls: 'w-4 h-4')],
          ),
        ]),
      ],
    );

    Component currentGig;
    if (job != null) {
      final title = job['title'] as String? ?? 'Current Gig';
      final employer = job['creatorName'] as String? ?? 'Employer';
      final loc = job['locationName'] as String? ??
          job['address'] as String? ??
          job['approxArea'] as String? ??
          'Approx. area';
      final pay = (job['pricingValue'] as num?)?.toDouble() ?? 0.0;
      final initials = employer
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .take(2)
          .map((part) => part[0].toUpperCase())
          .join();
      final jId = job['id'] as String;
      final acceptedId =
          job['acceptedApplicantId'] as String? ?? s.userProfile?.uid ?? SessionStorage.uid ?? '';
      final scopedChatId = acceptedId.isNotEmpty ? 'job_${jId}_$acceptedId' : jId;

      currentGig = div(
        classes: 'w-full xl:w-[440px] shrink-0 rounded-[20px] border p-6 flex flex-col gap-3 $surface',
        [
          div(classes: 'flex items-center gap-2', [
            span(classes: 'flex-1 text-sm font-semibold ${isDark ? "text-zinc-400" : "text-[#52525b]"}', [
              Component.text('Current Gig'),
            ]),
            span(
              classes:
                  'inline-flex items-center gap-1.5 h-6 px-2.5 rounded-full text-xs font-semibold '
                  'bg-[#fef2f2] text-[#dc2626]',
              [
                span(classes: 'w-1.5 h-1.5 rounded-full bg-[#dc2626] animate-pulse', []),
                Component.text('LIVE'),
              ],
            ),
          ]),
          p(classes: 'm-0 text-xl font-semibold tracking-tight ${isDark ? "text-zinc-50" : "text-[#18181b]"}', [
            Component.text(title),
          ]),
          div(classes: 'flex items-center gap-2', [
            div(
              classes:
                  'size-7 rounded-[14px] flex items-center justify-center text-[11px] font-bold '
                  '${isDark ? "bg-indigo-500/20 text-indigo-300" : "bg-[#eef2ff] text-[#4f46e5]"}',
              [Component.text(initials.isEmpty ? '?' : initials)],
            ),
            span(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-[#52525b]"}', [
              Component.text('$employer · Employer'),
            ]),
          ]),
          div(classes: 'flex items-center gap-1.5', [
            lIcon('map-pin', cls: 'w-4 h-4 ${isDark ? "text-zinc-500" : "text-[#71717a]"}'),
            span(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-[#52525b]"}', [Component.text(loc)]),
          ]),
          div(classes: 'flex items-center gap-3', [
            div(
              classes: 'h-2 w-[120px] rounded bg-[#fafafa] dark:bg-zinc-800 overflow-hidden',
              [
                div(
                  classes: 'h-2 rounded bg-[#4f46e5]',
                  attributes: {'style': 'width: 65%'},
                  [],
                ),
              ],
            ),
            span(classes: 'text-xs font-medium ${isDark ? "text-zinc-400" : "text-[#52525b]"}', [
              Component.text('In progress · Php ${pay.toStringAsFixed(2)}'),
            ]),
          ]),
          div(classes: 'flex gap-3 pt-1', [
            button(
              classes:
                  'flex-1 h-12 rounded-xl text-sm font-semibold text-white bg-[#4f46e5] border-0 cursor-pointer '
                  'shadow-[0_8px_10px_rgba(79,70,229,0.25)] hover:opacity-95',
              attributes: {'type': 'button'},
              events: {'click': (_) => s.selectJobAndLoadDetails(job)},
              [Component.text('View Details')],
            ),
            button(
              classes:
                  'h-12 px-5 rounded-xl text-sm font-semibold border cursor-pointer '
                  '${isDark ? "bg-zinc-900 border-zinc-700 text-zinc-200 hover:bg-zinc-800" : "bg-white border-[#d4d4d8] text-[#18181b] hover:bg-zinc-50"}',
              attributes: {'type': 'button'},
              events: {
                'click': (_) => s.openChat(
                      scopedChatId,
                      title: job['title'] as String?,
                      counterpartyName: job['creatorName'] as String?,
                    ),
              },
              [Component.text('Message')],
            ),
          ]),
        ],
      );
    } else {
      currentGig = div(
        classes: 'w-full xl:w-[440px] shrink-0 rounded-[20px] border p-6 flex flex-col gap-3 $surface',
        [
          div(classes: 'flex items-center gap-2', [
            span(classes: 'flex-1 text-sm font-semibold ${isDark ? "text-zinc-400" : "text-[#52525b]"}', [
              Component.text('Current Gig'),
            ]),
            span(
              classes:
                  'h-6 px-2.5 rounded-full text-xs font-semibold '
                  '${isDark ? "bg-zinc-800 text-zinc-400" : "bg-zinc-100 text-zinc-500"}',
              [Component.text('Idle')],
            ),
          ]),
          p(classes: 'm-0 text-base ${isDark ? "text-zinc-400" : "text-[#52525b]"}', [
            Component.text('No active gig. Browse available jobs to start earning.'),
          ]),
          button(
            classes:
                'mt-auto h-12 rounded-xl text-sm font-semibold text-white bg-[#4f46e5] border-0 cursor-pointer '
                'shadow-[0_8px_10px_rgba(79,70,229,0.25)] hover:opacity-95',
            attributes: {'type': 'button'},
            events: {'click': (_) => s.openJobsBrowse()},
            [Component.text('Find gigs')],
          ),
        ],
      );
    }

    return div(classes: 'flex flex-col xl:flex-row gap-6 items-stretch', [wallet, currentGig]);
  }

  /// W10 Nyxian stats — Gigs Done / Total Earned / Trust Rating (live profile).
  Component _nyxianStatsRow({required bool isDark, required TranyxAppState s}) {
    final card = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-[#e4e4e7] shadow-sm';
    final label = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    final title = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final jobsDone = s.userProfile?.jobsDone ?? 0;
    final totalEarned = s.userProfile?.totalEarned ?? 0.0;
    final rating = s.userProfile?.rating;

    Component cell({
      required String icon,
      required String name,
      required String value,
      required String action,
      required void Function() onTap,
    }) {
      return button(
        classes:
            'flex-1 min-w-[160px] text-left rounded-[20px] border px-6 py-5 flex flex-col gap-2 cursor-pointer $card',
        attributes: {'type': 'button'},
        events: {'click': (_) => onTap()},
        [
          div(classes: 'flex items-center gap-2', [
            lIcon(icon, cls: 'w-[18px] h-[18px] $label'),
            span(classes: 'text-sm $label', [Component.text(name)]),
          ]),
          p(classes: 'm-0 text-[28px] leading-9 font-bold tracking-tight $title', [Component.text(value)]),
          span(classes: 'inline-flex items-center gap-1 text-sm font-semibold text-[#4f46e5]', [
            Component.text(action),
            lIcon('chevron-right', cls: 'w-3.5 h-3.5'),
          ]),
        ],
      );
    }

    return div(classes: 'flex flex-col sm:flex-row gap-6', [
      cell(
        icon: 'briefcase',
        name: 'Gigs Done',
        value: '$jobsDone',
        action: 'View Profile',
        onTap: () => s.setState(() {
          s.activeTab = AppTab.profile;
          s.profileView = ProfileView.main;
        }),
      ),
      cell(
        icon: 'trending-up',
        name: 'Total Earned',
        value: '₱ ${totalEarned.toStringAsFixed(0)}',
        action: 'View Earnings',
        onTap: () => s.setState(() {
          s.activeTab = AppTab.profile;
          s.profileView = ProfileView.history;
        }),
      ),
      cell(
        icon: 'star',
        name: 'Trust Rating',
        value: rating != null ? rating.toStringAsFixed(1) : 'Unrated',
        action: 'View Reviews',
        onTap: () => s.setState(() {
          s.activeTab = AppTab.profile;
          s.profileView = ProfileView.reviews;
        }),
      ),
    ]);
  }

  /// W10 Top Services — live category chip tallies (same keywords as W20 filters).
  Component _topServicesSection({required bool isDark, required TranyxAppState s}) {
    final isLoading = s.isLoadingJobs;
    final allJobs = [...s.availableJobs, ...s.myJobs];
    // Exclude own postings from open-count where uid known
    final uid = s.userProfile?.uid;
    final openJobs = allJobs.where((j) {
      final status = (j['status'] as String?)?.toLowerCase() ?? 'open';
      if (status != 'open' && status != 'available') return false;
      if (uid != null && j['employerId'] == uid) return false;
      return true;
    }).toList();

    const chips = ['Cleaning', 'Plumbing', 'Electrical', 'Carpentry', 'Laundry', 'Delivery'];
    const icons = {
      'Cleaning': 'sparkles',
      'Plumbing': 'wrench',
      'Electrical': 'zap',
      'Carpentry': 'hammer',
      'Laundry': 'refresh-cw',
      'Delivery': 'truck',
    };

    final tallies = <String, int>{
      for (final chip in chips)
        chip: openJobs
            .where(
              (g) => GigFilterEngine.evaluateCategoryMatch(
                gig: g,
                categoryFilter: chip,
              ),
            )
            .length,
    };

    final cardBase = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textMuted = isDark ? 'text-zinc-400' : 'text-[#71717a]';

    return div(classes: 'space-y-4', [
      div(classes: 'flex items-center justify-between', [
        div(classes: 'flex items-center gap-2', [
          h2(classes: 'text-lg font-bold m-0 $textPrimary', [Component.text('Top Services')]),
          if (!isLoading && openJobs.isNotEmpty)
            span(
              classes:
                  'px-2 py-0.5 rounded-full text-[10px] font-bold bg-indigo-500/15 text-indigo-400 border border-indigo-500/20',
              [Component.text('LIVE')],
            ),
        ]),
        button(
          classes:
              'text-sm font-semibold text-[#4f46e5] hover:underline flex items-center gap-1 bg-transparent border-0 cursor-pointer',
          events: {'click': (_) => s.openJobsBrowse()},
          [Component.text('See All'), lIcon('chevron-right', cls: 'w-4 h-4')],
        ),
      ]),
      if (isLoading)
        div(classes: 'grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3', [
          for (int i = 0; i < 6; i++)
            div(
              classes: 'animate-pulse rounded-2xl border $cardBase p-4 h-[112px]',
              [div(classes: 'w-10 h-10 rounded-xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', [])],
            ),
        ])
      else if (openJobs.isEmpty)
        div(
          classes: 'rounded-2xl border $cardBase p-6 text-sm $textMuted',
          [
            Component.text('No open gigs yet. Check back soon or broaden your search on Jobs.'),
            button(
              classes: 'ml-2 text-[#4f46e5] font-semibold bg-transparent border-0 cursor-pointer hover:underline',
              events: {'click': (_) => s.openJobsBrowse()},
              [Component.text('Browse Jobs')],
            ),
          ],
        )
      else
        div(classes: 'grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3', [
          for (final chip in chips)
            button(
              classes:
                  'relative flex flex-col items-start gap-2 p-4 rounded-2xl border text-left transition-all cursor-pointer bg-transparent $cardBase hover:border-[#4f46e5]/50',
              attributes: {'type': 'button'},
              events: {'click': (_) => s.openJobsBrowse(filter: chip)},
              [
                div(
                  classes:
                      'size-10 rounded-xl flex items-center justify-center ${isDark ? "bg-indigo-500/15" : "bg-[#eef2ff]"}',
                  [lIcon(icons[chip] ?? 'briefcase', cls: 'w-5 h-5 text-[#4f46e5]')],
                ),
                span(classes: 'text-sm font-semibold $textPrimary', [Component.text(chip)]),
                span(classes: 'text-xs $textMuted flex items-center gap-1.5', [
                  span(classes: 'size-1.5 rounded-full bg-emerald-500', []),
                  Component.text(
                    '${tallies[chip] ?? 0} job${(tallies[chip] ?? 0) == 1 ? '' : 's'} open',
                  ),
                ]),
              ],
            ),
        ]),
    ]);
  }


  /// W10 Nearby Rentals — live Available listings within geofence (no mocks).
  Component _nearbyRentalsSection({
    required bool isDark,
    required TranyxAppState s,
    required List<Map<String, dynamic>> vehicles,
    required List<PropertyRental> properties,
  }) {
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textMuted = isDark ? 'text-zinc-400' : 'text-[#71717a]';
    final card = isDark
        ? 'bg-zinc-900 border border-zinc-800'
        : 'bg-white border border-[#e4e4e7] shadow-sm';

    final mixed = <({bool isProperty, dynamic item})>[];
    for (final v in vehicles.take(2)) {
      mixed.add((isProperty: false, item: v));
    }
    for (final p in properties.take(3 - mixed.length)) {
      mixed.add((isProperty: true, item: p));
    }
    if (mixed.length < 3) {
      for (final v in vehicles.skip(2).take(3 - mixed.length)) {
        mixed.add((isProperty: false, item: v));
      }
    }

    return div(classes: 'space-y-4', [
      div(classes: 'flex items-center justify-between', [
        h2(classes: 'text-lg font-bold m-0 $textPrimary', [Component.text('Nearby Rentals')]),
        button(
          classes:
              'text-sm font-semibold text-[#4f46e5] hover:underline flex items-center gap-1 bg-transparent border-0 cursor-pointer',
          events: {'click': (_) => s.switchTab(AppTab.transit)},
          [Component.text('View All'), lIcon('chevron-right', cls: 'w-4 h-4')],
        ),
      ]),
      if (mixed.isEmpty)
        div(
          classes: 'rounded-2xl border $card p-6 text-sm $textMuted',
          [
            Component.text('No rentals available nearby yet. View all once hosts publish listings.'),
          ],
        )
      else
        div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-4', [
          for (final entry in mixed)
            entry.isProperty
                ? _nearMePropertyTile(
                    entry.item as PropertyRental,
                    isDark: isDark,
                    s: s,
                    card: card,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                  )
                : _nearMeVehicleTile(
                    entry.item as Map<String, dynamic>,
                    isDark: isDark,
                    s: s,
                    card: card,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                  ),
        ]),
    ]);
  }

  Component _nearMeVehicleTile(
    Map<String, dynamic> r, {
    required bool isDark,
    required TranyxAppState s,
    required String card,
    required String textPrimary,
    required String textMuted,
  }) {
    final title = (r['vehicleName'] ?? r['name'] ?? r['title'] ?? 'Vehicle').toString();
    final rate = (r['dailyRate'] as num?)?.toDouble() ??
        (r['pricePerDay'] as num?)?.toDouble() ??
        0.0;
    final city = (r['pickupCity'] ?? r['city'] ?? r['address'] ?? '').toString();
    final lat = (r['pickupLat'] as num?)?.toDouble();
    final lng = (r['pickupLng'] as num?)?.toDouble();
    final dist = (lat != null && lng != null)
        ? calculateDistance(s.userLatitude, s.userLongitude, lat, lng)
        : null;
    final type = (r['vehicleType'] ?? r['type'] ?? '').toString();
    final meta = [
      if (type.isNotEmpty) type,
      if (dist != null) '${dist.toStringAsFixed(1)} km',
    ].join(' · ');

    return div(
      classes: '$card rounded-2xl overflow-hidden cursor-pointer hover:border-[#4f46e5]/40 transition-colors',
      events: {'click': (_) => s.switchTab(AppTab.transit)},
      [
        div(classes: 'h-36 bg-gradient-to-r from-indigo-200 to-violet-300 relative', [
          span(
            classes:
                'absolute top-3 left-3 px-2.5 py-1 rounded-full text-[11px] font-semibold bg-emerald-50 text-emerald-700',
            [Component.text('Available')],
          ),
        ]),
        div(classes: 'p-4 space-y-1', [
          p(classes: 'm-0 font-semibold text-[15px] $textPrimary', [Component.text(title)]),
          if (meta.isNotEmpty) p(classes: 'm-0 text-xs $textMuted', [Component.text(meta)]),
          if (city.isNotEmpty)
            p(classes: 'm-0 text-xs $textMuted flex items-center gap-1', [
              lIcon('map-pin', cls: 'w-3.5 h-3.5'),
              Component.text(city),
            ]),
          p(classes: 'm-0 pt-1 font-semibold text-[17px] $textPrimary', [
            Component.text(rate > 0 ? '₱ ${rate.toStringAsFixed(0)}/day' : 'Rate on request'),
          ]),
        ]),
      ],
    );
  }

  Component _nearMePropertyTile(
    PropertyRental prop, {
    required bool isDark,
    required TranyxAppState s,
    required String card,
    required String textPrimary,
    required String textMuted,
  }) {
    final rate = prop.monthlyRate;
    final dist = calculateDistance(s.userLatitude, s.userLongitude, prop.latitude, prop.longitude);
    final area = prop.address.split(',').first.trim();
    return div(
      classes: '$card rounded-2xl overflow-hidden cursor-pointer hover:border-[#4f46e5]/40 transition-colors',
      events: {
        'click': (_) => s.setState(() {
          s.activeTab = AppTab.transit;
          s.activeRentalCategory = RentalCategory.properties;
        }),
      },
      [
        div(classes: 'h-36 bg-gradient-to-r from-sky-200 to-violet-300 relative', [
          span(
            classes:
                'absolute top-3 left-3 px-2.5 py-1 rounded-full text-[11px] font-semibold bg-emerald-50 text-emerald-700',
            [Component.text('Available')],
          ),
        ]),
        div(classes: 'p-4 space-y-1', [
          p(classes: 'm-0 font-semibold text-[15px] $textPrimary', [Component.text(prop.title)]),
          p(classes: 'm-0 text-xs $textMuted', [
            Component.text('${prop.category.label} · ${prop.type.label}'),
          ]),
          p(classes: 'm-0 text-xs $textMuted flex items-center gap-1', [
            lIcon('map-pin', cls: 'w-3.5 h-3.5'),
            Component.text(
              '${area.isNotEmpty ? area : 'Approx. area'} · ${dist.toStringAsFixed(1)} km',
            ),
          ]),
          p(classes: 'm-0 pt-1 font-semibold text-[17px] $textPrimary', [
            Component.text(rate > 0 ? '₱ ${rate.toStringAsFixed(0)}/mo' : 'Rate on request'),
          ]),
        ]),
      ],
    );
  }

  Component _transitTeaser({required bool isDark, required void Function() onTap}) {
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    return button(
      classes:
          'w-full p-6 rounded-2xl border card-hover transition-all text-left cursor-pointer bg-transparent $cardCls',
      events: {'click': (_) => onTap()},
      [
        div(classes: 'flex items-center justify-between', [
          div(classes: 'flex items-center gap-4', [
            div(classes: 'p-3 rounded-2xl bg-purple-500/10 border border-purple-500/20', [
              lIcon('car', cls: 'w-7 h-7 text-purple-400'),
            ]),
            div([
              h3(classes: 'font-bold text-lg text-zinc-200', [Component.text('Vehicles Rentals')]),
              p(classes: 'text-sm ${isDark ? "text-zinc-550" : "text-zinc-500"}', [
                Component.text('Rent or host cars, motorbikes, or logistics trucks near you'),
              ]),
            ]),
          ]),
          div(classes: 'flex items-center gap-2 text-purple-400 font-semibold text-sm', [
            Component.text('Explore'),
            lIcon('arrow-right', cls: 'w-4 h-4'),
          ]),
        ]),
      ],
    );
  }

  Component _realEstateTeaser({required bool isDark, required TranyxAppState s}) {
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    return button(
      classes:
          'w-full p-6 rounded-2xl border card-hover transition-all text-left cursor-pointer bg-transparent $cardCls',
      events: {
        'click': (_) {
          s.setState(() {
            s.activeTab = AppTab.transit;
            s.activeRentalCategory = RentalCategory.properties;
          });
        },
      },
      [
        div(classes: 'flex items-center justify-between', [
          div(classes: 'flex items-center gap-4', [
            div(classes: 'p-3 rounded-2xl bg-amber-500/10 border border-amber-500/20', [
              lIcon('home', cls: 'w-7 h-7 text-amber-400'),
            ]),
            div([
              h3(classes: 'font-bold text-lg text-zinc-200', [Component.text('Real Estate Rentals')]),
              p(classes: 'text-sm ${isDark ? "text-zinc-555" : "text-zinc-500"}', [
                Component.text('Rent apartments, bedspaces, private rooms, and commercial offices directly'),
              ]),
            ]),
          ]),
          div(classes: 'flex items-center gap-2 text-amber-450 font-semibold text-sm', [
            Component.text('Rent Spaces'),
            lIcon('arrow-right', cls: 'w-4 h-4'),
          ]),
        ]),
      ],
    );
  }

  Component _quickStatsBar({required bool isDark, required bool isNyxian, required TranyxAppState s}) {
    final cardBg = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    final labelColor = isDark ? 'text-zinc-500' : 'text-zinc-400';
    final titleColor = isDark ? 'text-zinc-150' : 'text-zinc-800';

    final pendingTotal = s.pendingHoldbacks.fold<double>(0.0, (sum, item) {
      final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
      return sum + amt;
    });

    Component buildPendingReleaseBreakdown() {
      if (pendingTotal <= 0) return div([]);
      return div(classes: 'mt-2 space-y-1 border-t border-zinc-500/10 pt-2', [
        for (final holdback in s.pendingHoldbacks)
          Builder(
            builder: (context) {
              final amt = (holdback['amount'] as num?)?.toDouble() ?? 0.0;
              final relAt = holdback['releaseAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
              final hrs = ((relAt - DateTime.now().millisecondsSinceEpoch) / (1000 * 60 * 60)).ceil();
              final hrsStr = hrs <= 0 ? 'processing release' : 'releases in $hrs hr${hrs == 1 ? "" : "s"}';
              return p(classes: 'text-[9px] text-amber-500/80 font-bold text-left', [
                Component.text('• Php ${amt.toStringAsFixed(2)} $hrsStr'),
              ]);
            },
          ),
      ]);
    }

    if (isNyxian) {
      final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
      final jobsDone = s.userProfile?.jobsDone ?? 0;
      final totalEarned = s.userProfile?.totalEarned ?? 0.0;
      final rating = s.userProfile?.rating;

      return div(classes: 'grid grid-cols-2 lg:grid-cols-4 gap-4', [
        // Wallet Balance
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-indigo-500/40 cursor-pointer $cardBg',
          events: {'click': (_) => s.setState(() => s.showWalletActionMenu = true)},
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [Component.text('Wallet')]),
              lIcon('wallet', cls: 'w-4 h-4 text-indigo-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('₱ ${tyxBal.toStringAsFixed(2)}'),
            ]),
            if (pendingTotal > 0) ...[
              p(classes: 'text-[9px] text-amber-500 font-bold mt-1.5 flex items-center gap-0.5 animate-pulse', [
                lIcon('clock', cls: 'w-2.5 h-2.5'),
                Component.text('+ ₱${pendingTotal.toStringAsFixed(2)} Pending'),
              ]),
              buildPendingReleaseBreakdown(),
            ] else
              p(
                classes: 'text-[9px] text-zinc-500 mt-1 font-semibold hover:text-indigo-400 transition-colors',
                [Component.text('Deposit Tyx')],
              ),
          ],
        ),
        // Completed Gigs
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-purple-500/40 cursor-pointer $cardBg',
          events: {
            'click': (_) => s.setState(() {
              s.activeTab = AppTab.profile;
              s.profileView = ProfileView.main;
            }),
          },
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [
                Component.text('Gigs Done'),
              ]),
              lIcon('check-circle', cls: 'w-4 h-4 text-purple-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('$jobsDone'),
            ]),
            p(classes: 'text-[9px] text-purple-450 font-semibold mt-1', [Component.text('View Profile')]),
          ],
        ),
        // Total Earnings
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-emerald-500/40 cursor-pointer $cardBg',
          events: {
            'click': (_) => s.setState(() {
              s.activeTab = AppTab.profile;
              s.profileView = ProfileView.history;
            }),
          },
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [
                Component.text('Total Earned'),
              ]),
              lIcon('trending-up', cls: 'w-4 h-4 text-emerald-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('₱ ${totalEarned.toStringAsFixed(0)}'),
            ]),
            p(classes: 'text-[9px] text-emerald-450 font-semibold mt-1', [Component.text('View Earnings')]),
          ],
        ),
        // Rating
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-amber-500/40 cursor-pointer $cardBg',
          events: {
            'click': (_) => s.setState(() {
              s.activeTab = AppTab.profile;
              s.profileView = ProfileView.reviews;
            }),
          },
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [
                Component.text('Trust Rating'),
              ]),
              lIcon('star', cls: 'w-4 h-4 text-amber-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor flex items-center gap-1', [
              Component.text(rating != null ? rating.toStringAsFixed(1) : 'Unrated'),
              if (rating != null) span(classes: 'text-xs text-amber-400', [Component.text('★')]),
            ]),
            p(classes: 'text-[9px] text-amber-500 font-semibold mt-1', [Component.text('View Reviews')]),
          ],
        ),
      ]);
    } else {
      // Employer Mode
      final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
      final postedCount = s.myJobs.length;
      final activeHires = s.myJobs.where((j) => j['status'] == 'In Progress').length;
      final rating = s.userProfile?.rating;

      return div(classes: 'grid grid-cols-2 lg:grid-cols-4 gap-4', [
        // Wallet Balance
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-indigo-500/40 cursor-pointer $cardBg',
          events: {'click': (_) => s.setState(() => s.showWalletActionMenu = true)},
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [Component.text('Wallet')]),
              lIcon('wallet', cls: 'w-4 h-4 text-indigo-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('₱ ${tyxBal.toStringAsFixed(2)}'),
            ]),
            if (pendingTotal > 0) ...[
              p(classes: 'text-[9px] text-amber-500 font-bold mt-1.5 flex items-center gap-0.5 animate-pulse', [
                lIcon('clock', cls: 'w-2.5 h-2.5'),
                Component.text('+ ₱${pendingTotal.toStringAsFixed(2)} Pending'),
              ]),
              buildPendingReleaseBreakdown(),
            ] else
              p(classes: 'text-[9px] text-zinc-500 mt-1 font-semibold hover:text-indigo-400 transition-colors', [
                Component.text('Deposit Tyx'),
              ]),
          ],
        ),
        // Posted Gigs
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-purple-500/40 cursor-pointer $cardBg',
          events: {
            'click': (_) => s.setState(() {
              s.activeTab = AppTab.jobs;
              s.activeJobPane = 'active';
            }),
          },
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [
                Component.text('Gigs Posted'),
              ]),
              lIcon('briefcase', cls: 'w-4 h-4 text-purple-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('$postedCount'),
            ]),
            p(classes: 'text-[9px] text-purple-450 font-semibold mt-1', [Component.text('Manage Gigs')]),
          ],
        ),
        // Active Hires
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-emerald-500/40 cursor-pointer $cardBg',
          events: {
            'click': (_) => s.setState(() {
              s.activeTab = AppTab.jobs;
              s.activeJobPane = 'active';
            }),
          },
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [
                Component.text('Active Gigs'),
              ]),
              lIcon('users', cls: 'w-4 h-4 text-emerald-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor', [
              Component.text('$activeHires'),
            ]),
            p(classes: 'text-[9px] text-emerald-450 font-semibold mt-1', [Component.text('View Active Workers')]),
          ],
        ),
        // Rating
        div(
          classes: 'p-5 rounded-2xl border transition-all hover:border-amber-500/40 cursor-pointer $cardBg',
          events: {
            'click': (_) => s.setState(() {
              s.activeTab = AppTab.profile;
              s.profileView = ProfileView.reviews;
            }),
          },
          [
            div(classes: 'flex justify-between items-start mb-2', [
              span(classes: 'text-[10px] font-black uppercase tracking-wider $labelColor', [
                Component.text('Employer Score'),
              ]),
              lIcon('star', cls: 'w-4 h-4 text-amber-400'),
            ]),
            p(classes: 'text-lg font-black $titleColor flex items-center gap-1', [
              Component.text(rating != null ? rating.toStringAsFixed(1) : 'Unrated'),
              if (rating != null) span(classes: 'text-xs text-amber-400', [Component.text('★')]),
            ]),
            p(classes: 'text-[9px] text-amber-500 font-semibold mt-1', [Component.text('View Reviews')]),
          ],
        ),
      ]);
    }
  }

  Component _activeTrackersSection({required bool isDark, required TranyxAppState s}) {
    final currentUid = s.userProfile?.uid;
    if (currentUid == null) return div([]);

    final activeRentals = s.realtimeRentals
        .where(
          (r) =>
              r['renteeId'] == currentUid &&
              r['status'] != 'Available' &&
              r['status'] != 'Completed' &&
              r['status'] != 'Complete',
        )
        .toList();

    final activeLeases = s.realtimeProperties
        .where(
          (leaseItem) =>
              leaseItem.renteeId == currentUid && leaseItem.status != 'Available' && leaseItem.status != 'Completed',
        )
        .toList();

    final hasActiveRentals = activeRentals.isNotEmpty || activeLeases.isNotEmpty;

    if (!hasActiveRentals) return div([]);

    return div(classes: 'space-y-4', [
      h2(classes: 'text-lg font-bold flex items-center gap-2', [
        lIcon('compass', cls: 'w-5 h-5 text-purple-400'),
        Component.text('Active Rentals & Trips'),
      ]),
      div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
        for (final r in activeRentals)
          div(
            classes:
                'p-4 rounded-2xl border border-purple-500/20 bg-purple-500/5 hover:bg-purple-500/10 cursor-pointer transition-all flex items-center justify-between',
            events: {
              'click': (_) => s.setState(() {
                s.selectedRentalData = r;
                s.showRentalTrackerMap = true;
              }),
            },
            [
              div(classes: 'flex items-center gap-3', [
                div(classes: 'p-2 rounded-xl bg-purple-500/20', [
                  lIcon('car', cls: 'w-5 h-5 text-purple-400'),
                ]),
                div([
                  p(classes: 'text-xs font-semibold text-purple-400 uppercase tracking-wider', [
                    Component.text('Transit Rental • ${r['status']}'),
                  ]),
                  p(classes: 'font-bold text-sm text-zinc-200', [
                    Component.text('${r['brand']} ${r['model']}'),
                  ]),
                  p(classes: 'text-[10px] text-zinc-500 mt-0.5', [
                    Component.text('Click to view GPS route & tracking map'),
                  ]),
                ]),
              ]),
              lIcon('chevron-right', cls: 'w-5 h-5 text-purple-400'),
            ],
          ),
        for (final lease in activeLeases)
          div(
            classes:
                'p-4 rounded-2xl border border-indigo-500/20 bg-indigo-500/5 hover:bg-indigo-500/10 cursor-pointer transition-all flex items-center justify-between',
            events: {
              'click': (_) => s.setState(() {
                s.activeTab = AppTab.transit;
                s.activeRentalCategory = RentalCategory.properties;
              }),
            },
            [
              div(classes: 'flex items-center gap-3', [
                div(classes: 'p-2 rounded-xl bg-indigo-500/20', [
                  lIcon('home', cls: 'w-5 h-5 text-indigo-400'),
                ]),
                div([
                  p(classes: 'text-xs font-semibold text-indigo-400 uppercase tracking-wider', [
                    Component.text('Real Estate Lease • ${lease.status}'),
                  ]),
                  p(classes: 'font-bold text-sm text-zinc-200', [
                    Component.text(lease.title),
                  ]),
                  p(classes: 'text-[10px] text-zinc-500 mt-0.5', [
                    Component.text('Click to manage lease agreement & chat'),
                  ]),
                ]),
              ]),
              lIcon('chevron-right', cls: 'w-5 h-5 text-indigo-400'),
            ],
          ),
      ]),
    ]);
  }
}
