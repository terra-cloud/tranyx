import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import '../../services/firebase_service.dart';
import '../../services/web_interop.dart';
import '../widgets/p2p_admin_panel.dart';
import 'package:shared/shared.dart';

class ProfileViewComponent extends StatelessComponent {
  final TranyxAppState state;
  const ProfileViewComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;

    return div(classes: 'flex flex-col md:flex-row gap-6', [
      // Left pane — menu (always visible on desktop, hidden on mobile when sub-view open)
      div(
        classes: 'w-full md:w-72 flex-shrink-0 ${s.profileView != ProfileView.main ? "hidden md:block" : ""}',
        [_ProfileMenu(state: s)],
      ),

      // Right pane — content
      div(classes: 'flex-1 animate-fade-up', [
        _buildSubView(s, isDark),
      ]),
    ]);
  }

  Component _buildSubView(TranyxAppState s, bool isDark) {
    return switch (s.profileView) {
      ProfileView.main => _ProfileMain(state: s),
      ProfileView.personal => _PersonalInfo(state: s),
      ProfileView.professional => _ProfessionalInfo(state: s),
      ProfileView.payment => _Payment(state: s),
      ProfileView.withdraw => _WithdrawPane(state: s),
      ProfileView.subscription => _ProfileMain(state: s),
      ProfileView.trust => _TrustVerification(state: s),
      ProfileView.support => _HelpSupport(state: s),
      ProfileView.history => _HistoryView(state: s),
      ProfileView.reviews => _ReviewsView(state: s),
      ProfileView.rewards => _RewardsView(state: s),
    };
  }
}

// ── Left menu ─────────────────────────────────────────────────
class _ProfileMenu extends StatelessComponent {
  final TranyxAppState state;
  const _ProfileMenu({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    final String historyLabel = 'Transaction History';

    final items = [
      (ProfileView.personal, 'user', 'Personal Information'),
      (ProfileView.professional, 'briefcase', 'Professional Info'),
      (ProfileView.payment, 'credit-card', 'Payment Methods'),
      (ProfileView.trust, 'shield-check', 'Trust & Verification'),
      (ProfileView.support, 'help-circle', 'Help & Support'),
      (ProfileView.history, 'activity', historyLabel),
      (ProfileView.reviews, 'star', 'Ratings & Reviews'),
      (ProfileView.rewards, 'gift', 'Terra Rewards'),
    ];

    return div(classes: 'rounded-3xl border p-4 $cardCls', [
      // Avatar + name header
      div(classes: 'p-4 text-center mb-4', [
        div(classes: 'relative inline-block mb-3 group', [
          div(
            classes:
                'w-20 h-20 rounded-full overflow-hidden gradient-border flex items-center justify-center bg-indigo-600/20 relative shadow-md',
            [
              if (s.userPhotoUrl != null && s.userPhotoUrl!.isNotEmpty)
                img(src: s.userPhotoUrl!, classes: 'w-full h-full object-cover')
              else
                span(classes: 'text-2xl font-bold text-indigo-400', [
                  Component.text(s.userName.isNotEmpty ? s.userName[0].toUpperCase() : '?'),
                ]),
              if (s.isUploadingProfilePhoto)
                div(
                  classes: 'absolute inset-0 bg-black/60 flex items-center justify-center backdrop-blur-sm',
                  [lIcon('loader-2', cls: 'w-6 h-6 animate-spin text-white')],
                ),
            ],
          ),
          label(
            classes:
                'absolute bottom-0 right-0 p-2 rounded-full bg-indigo-600 hover:bg-indigo-700 text-white shadow-lg cursor-pointer transition-all hover:scale-110 flex items-center justify-center border-2 ${isDark ? "border-zinc-900" : "border-white"}',
            attributes: {'title': 'Upload custom profile photo'},
            [
              lIcon('camera', cls: 'w-3.5 h-3.5'),
              input(
                type: InputType.file,
                classes: 'hidden',
                attributes: {'accept': 'image/*'},
                events: {'change': (e) => s.handleProfilePhotoUpload(e)},
              ),
            ],
          ),
        ]),
        p(classes: 'font-bold text-lg', [Component.text(s.userName.isNotEmpty ? s.userName : 'User')]),
        div(classes: 'flex justify-center gap-2 mt-1.5', [
          span(
            classes: 'inline-block px-3 py-1 rounded-md text-xs font-bold ${s.accountType.badgeClasses}',
            [Component.text(s.accountType.label)],
          ),
          if (s.userProfile?.isBonded == true)
            span(
              classes:
                  'inline-block px-3 py-1 rounded-md text-xs font-bold bg-green-500/15 text-green-400 border border-green-500/25 flex items-center gap-1',
              [
                lIcon('shield-check', cls: 'w-3.5 h-3.5'),
                Component.text('Bonded & Protected'),
              ],
            ),
        ]),
      ]),

      // Menu items
      div(classes: 'space-y-1', [
        for (final item in items) _menuItem(item.$1, item.$2, item.$3, s, isDark),
      ]),

      div(classes: 'mt-4 pt-4 border-t ${isDark ? "border-zinc-800" : "border-zinc-100"}', [
        button(
          classes: 'w-full flex items-center gap-3 p-4 rounded-2xl transition-colors text-red-500 hover:bg-red-500/10',
          events: {'click': (_) => s.handleLogout()},
          [lIcon('log-out', cls: 'w-5 h-5'), Component.text('  Log Out')],
        ),
      ]),
    ]);
  }

  Component _menuItem(ProfileView view, String icon, String label, TranyxAppState s, bool isDark) {
    final isActive = s.profileView == view;
    final activeCls = isDark ? 'bg-indigo-600/20 text-indigo-400' : 'bg-indigo-50 text-indigo-700';
    final inactiveCls = isDark ? 'text-zinc-400 hover:bg-zinc-800' : 'text-zinc-600 hover:bg-zinc-50';
    return button(
      classes:
          'w-full flex items-center gap-3 p-4 rounded-2xl transition-all text-left ${isActive ? activeCls : inactiveCls}',
      events: {
        'click': (_) => s.setState(() {
          if (view == ProfileView.withdraw) {
            s.showWithdrawModal = true;
          } else {
            s.profileView = view;
            s.initializeProfileEditing();
          }
        }),
      },
      [
        lIcon(icon, cls: 'w-5 h-5'),
        span(classes: 'text-sm font-medium', [Component.text(label)]),
        if (isActive) ...[
          div([], classes: 'flex-1'),
          lIcon('chevron-right', cls: 'w-4 h-4'),
        ],
      ],
    );
  }
}

// ── Main overview ─────────────────────────────────────────────
class _ProfileMain extends StatefulComponent {
  final TranyxAppState state;
  const _ProfileMain({required this.state});

  @override
  State<_ProfileMain> createState() => _ProfileMainState();
}

class _ProfileMainState extends State<_ProfileMain> {
  String selectedPlan = 'monthly'; // 'monthly' | 'yearly'
  bool isProcessing = false;
  String? errorMessage;

  Component _perkRow(String text, bool active) {
    final isDark = component.state.isDark;
    return div(classes: 'flex items-center gap-2.5 text-xs', [
      lIcon('check', cls: 'w-4 h-4 text-emerald-400 flex-shrink-0'),
      span(classes: isDark ? "text-zinc-300" : "text-zinc-700", [Component.text(text)]),
    ]);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      component.state.fetchSolToPhpRate();
      component.state.loadUserProfile();
    });
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    return div(classes: 'space-y-6', [
      h2(classes: 'text-2xl font-bold hidden md:block', [Component.text('Account Settings')]),

      if (s.userProfile == null)
        div(
          classes:
              'p-5 rounded-2xl border flex flex-col md:flex-row items-center gap-4 border-amber-500/30 bg-amber-500/10',
          [
            div(classes: 'p-3 rounded-xl bg-amber-500/20 text-amber-500', [
              lIcon('alert-triangle', cls: 'w-6 h-6'),
            ]),
            div(classes: 'flex-1 text-center md:text-left', [
              p(classes: 'font-bold text-amber-500', [Component.text('Profile Incomplete')]),
              p(classes: 'text-sm mt-1 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                Component.text(
                  'Your profile records were not found in the database. Please complete your profile details to unlock all features.',
                ),
              ]),
            ]),
            button(
              classes:
                  'px-6 py-2.5 rounded-xl font-bold bg-amber-500 text-white shadow-lg hover:bg-amber-400 transition-colors',
              events: {
                'click': (_) {
                  s.setState(() {
                    s.profileView = ProfileView.personal;
                    s.initializeProfileEditing();
                  });
                },
              },
              [Component.text('Go to Profile Setup')],
            ),
          ],
        ),

      // Stats row
      div(
        classes: 'grid grid-cols-2 md:grid-cols-${s.accountType == AccountType.employer ? "2" : "3"} gap-4',
        [
          // Rating - Always shown
          _stat(
            s.userProfile?.rating != null ? s.userProfile!.rating!.toStringAsFixed(1) : 'Unrated',
            'Rating',
            'star',
            'text-amber-400',
            isDark,
          ),

          // Jobs Done - Shown for Nyxian and Hybrid
          if (s.accountType != AccountType.employer)
            _stat(
              (s.userProfile?.jobsDone ?? 0).toString(),
              'Jobs Done',
              'briefcase',
              'text-indigo-400',
              isDark,
            ),

          // Balance - Always shown for everyone with Top Up & Withdraw actions
          div(
            classes:
                'p-4 rounded-2xl border text-center transition-all duration-300 group '
                '${isDark ? "bg-zinc-900/50 border-zinc-800/50 hover:border-indigo-500/30" : "bg-white border-zinc-200 shadow-sm hover:border-indigo-500/30"}',
            [
              div(
                classes:
                    'w-10 h-10 rounded-xl bg-zinc-500/5 flex items-center justify-center mx-auto mb-2 group-hover:scale-110 transition-transform duration-300',
                [lIcon('wallet', cls: 'w-5 h-5 text-blue-400')],
              ),
              p(classes: 'font-black text-xl md:text-2xl tracking-tight ${isDark ? "text-white" : "text-zinc-900"}', [
                Component.text('₱ ${(s.userProfile?.tyxBalance ?? 0.0).toStringAsFixed(2)}'),
              ]),
              p(
                classes:
                    'text-[10px] uppercase font-black tracking-widest mt-1 ${isDark ? "text-zinc-500" : "text-zinc-400"}',
                [Component.text('Balance')],
              ),
              Builder(
                builder: (context) {
                  final pendingTotal = s.pendingHoldbacks.fold<double>(0.0, (sum, item) {
                    final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
                    return sum + amt;
                  });
                  if (pendingTotal > 0) {
                    return div(classes: 'mt-1.5 space-y-1', [
                      p(
                        classes:
                            'text-[9px] text-amber-500 font-extrabold flex items-center justify-center gap-0.5 animate-pulse',
                        [
                          lIcon('clock', cls: 'w-3 h-3'),
                          Component.text('+ ₱${pendingTotal.toStringAsFixed(2)} Pending'),
                        ],
                      ),
                      for (final holdback in s.pendingHoldbacks)
                        Builder(
                          builder: (context) {
                            final amt = (holdback['amount'] as num?)?.toDouble() ?? 0.0;
                            final relAt = holdback['releaseAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
                            final hrs = ((relAt - DateTime.now().millisecondsSinceEpoch) / (1000 * 60 * 60)).ceil();
                            final hrsStr = hrs <= 0
                                ? 'processing release'
                                : 'releases in $hrs hr${hrs == 1 ? "" : "s"}';
                            return p(classes: 'text-[8.5px] text-amber-500/80 font-bold', [
                              Component.text('• Php ${amt.toStringAsFixed(2)} $hrsStr'),
                            ]);
                          },
                        ),
                    ]);
                  }
                  return div([]);
                },
              ),
              div(classes: 'mt-3 flex justify-center gap-2', [
                button(
                  classes:
                      'px-2 py-1 text-[10px] uppercase font-bold text-indigo-400 hover:text-indigo-300 border border-indigo-500/20 rounded-lg bg-indigo-500/5 transition-colors cursor-pointer',
                  events: {'click': (_) => s.setState(() => s.showDepositModal = true)},
                  [Component.text('Top Up')],
                ),
                button(
                  classes:
                      'px-2 py-1 text-[10px] uppercase font-bold text-emerald-400 hover:text-emerald-300 border border-emerald-500/20 rounded-lg bg-emerald-500/5 transition-colors cursor-pointer',
                  events: {'click': (_) => s.setState(() => s.showWithdrawModal = true)},
                  [Component.text('Withdraw')],
                ),
              ]),
            ],
          ),
        ],
      ),

      if (const String.fromEnvironment('ENV', defaultValue: 'dev') == 'dev')
        // Switch account type (dev helper)
        div(classes: 'p-5 rounded-2xl border $cardCls', [
          p(
            classes:
                'text-xs font-semibold uppercase tracking-wider mb-3 ${isDark ? "text-zinc-500" : "text-zinc-400"}',
            [Component.text('Switch Account Type (Dev)')],
          ),
          div(classes: 'flex gap-2 flex-wrap', [
            for (final t in AccountType.values)
              button(
                classes:
                    'px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${s.accountType == t ? t.badgeClasses : (isDark ? "bg-zinc-800 text-zinc-400" : "bg-zinc-100 text-zinc-650")}',
                events: {
                  'click': (_) => s.setState(() {
                    s.accountType = t;
                    s.hybridToggle = t == AccountType.nyxian ? AccountType.nyxian : AccountType.employer;
                  }),
                },
                [Component.text(t.label)],
              ),
          ]),
        ]),

      // Perks & SOL Pricing Cards (Lite vs Pro comparison from reference)
      if (s.accountType != AccountType.hybrid)
        Builder(
          builder: (context) {
            final rate = s.solToPhpRate > 0 ? s.solToPhpRate : 8500.0;
            final double monthlySolPrice = 299.0 / rate;
            final double yearlySolPrice = 2999.0 / rate;
            final double activeSolPrice = selectedPlan == 'yearly' ? yearlySolPrice : monthlySolPrice;
            final hasWallet = s.walletState == WalletState.connected;
            final displayAddress = s.walletAddress.isNotEmpty
                ? s.walletAddress
                : (s.userProfile?.walletPublicKey ?? '');
            final textCls = isDark ? 'text-white' : 'text-zinc-900';

            return div(classes: 'mt-10 pt-8 border-t ${isDark ? "border-zinc-800" : "border-zinc-150"} space-y-6', [
              // Header section
              div(classes: 'text-center max-w-xl mx-auto space-y-2', [
                h3(classes: 'text-xl font-black $textCls', [Component.text('Upgrade to Pro')]),
                p(classes: 'text-xs text-zinc-500 mt-1', [
                  Component.text('Choose the plan that fits your business needs. Pay with SOL to upgrade instantly.'),
                ]),
              ]),

              // Plan Cards Selector
              div(classes: 'grid grid-cols-2 gap-4 max-w-md mx-auto', [
                // Monthly
                div(
                  classes:
                      'p-4 rounded-2xl border text-center transition-all cursor-pointer relative '
                      '${selectedPlan == 'monthly' ? "border-indigo-500 bg-indigo-500/10 shadow-lg shadow-indigo-500/5" : cardCls}',
                  events: {
                    'click': (_) => setState(() => selectedPlan = 'monthly'),
                  },
                  [
                    h4(classes: 'text-sm font-black $textCls', [Component.text('Monthly Plan')]),
                    p(classes: 'text-[10px] text-zinc-500 mt-0.5', [Component.text('₱299 PHP basis')]),
                    p(classes: 'text-xs font-black text-indigo-400 mt-2', [
                      Component.text('◎ ${monthlySolPrice.toStringAsFixed(4)} SOL / mo'),
                    ]),
                  ],
                ),

                // Yearly
                div(
                  classes:
                      'p-4 rounded-2xl border text-center transition-all cursor-pointer relative overflow-visible '
                      '${selectedPlan == 'yearly' ? "border-indigo-500 bg-indigo-500/10 shadow-lg shadow-indigo-500/5" : cardCls}',
                  events: {
                    'click': (_) => setState(() => selectedPlan = 'yearly'),
                  },
                  [
                    div(
                      classes:
                          'absolute -top-2.5 right-2 px-2 py-0.5 rounded-full text-[8px] font-black uppercase bg-red-500 text-white shadow-sm border border-red-400/20',
                      [Component.text('16% Saved')],
                    ),
                    h4(classes: 'text-sm font-black $textCls', [Component.text('Yearly Plan')]),
                    p(classes: 'text-[10px] text-zinc-500 mt-0.5', [Component.text('₱2,999 PHP basis')]),
                    p(classes: 'text-xs font-black text-indigo-400 mt-2', [
                      Component.text('◎ ${yearlySolPrice.toStringAsFixed(4)} SOL / yr'),
                    ]),
                  ],
                ),
              ]),

              // Columns comparison grid
              div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-6', [
                // Lite Card
                div(classes: 'p-6 rounded-[2rem] border $cardCls flex flex-col justify-between relative space-y-6', [
                  div(classes: 'space-y-4', [
                    div(classes: 'flex items-center gap-2', [
                      span([], classes: 'w-2 h-6 bg-zinc-400 rounded-sm'),
                      h4(classes: 'text-base font-black $textCls', [Component.text('Lite')]),
                    ]),
                    p(classes: 'text-xs text-zinc-500 leading-normal', [
                      Component.text('Basic account with a single active role'),
                    ]),
                    div(
                      classes:
                          'flex items-baseline gap-2 py-2 border-y ${isDark ? "border-zinc-800" : "border-zinc-150"}',
                      [
                        span(classes: 'text-3xl font-black $textCls', [Component.text('Single')]),
                        p(classes: 'text-[10px] text-zinc-500 leading-snug', [
                          Component.text('Choose either Nyxian or Employer role'),
                        ]),
                      ],
                    ),
                    div(classes: 'space-y-3 pt-2', [
                      _perkRow('Single account role active at a time', true),
                      _perkRow('Standard search exposure ranking', true),
                      _perkRow('Standard 3% platform service fee', true),
                      _perkRow('Limited daily messaging tools', true),
                    ]),
                  ]),

                  button(
                    classes:
                        'w-full py-3.5 rounded-2xl text-xs font-bold text-center border transition-all cursor-not-allowed '
                        '${isDark ? "bg-zinc-800 border-zinc-800 text-zinc-500" : "bg-zinc-100 border-zinc-200 text-zinc-400"}',
                    attributes: {'disabled': 'true'},
                    [Component.text('Your plan')],
                  ),
                ]),

                // Pro Card
                div(
                  classes:
                      'p-6 rounded-[2rem] border flex flex-col justify-between relative space-y-6 '
                      '${selectedPlan == 'monthly' ? "border-indigo-500 bg-indigo-500/5 shadow-xl shadow-indigo-500/5" : "border-indigo-600 bg-indigo-650/5 shadow-xl shadow-indigo-600/5"}',
                  [
                    div(
                      classes:
                          'absolute top-6 right-6 px-3 py-1 rounded-full text-[9px] font-black uppercase bg-amber-500/20 text-amber-400 border border-amber-500/30',
                      [Component.text('Recommended')],
                    ),

                    div(classes: 'space-y-4', [
                      div(classes: 'flex items-center gap-2', [
                        span([], classes: 'w-2 h-6 bg-indigo-500 rounded-sm'),
                        h4(classes: 'text-base font-black $textCls', [
                          Component.text('Pro '),
                          span(classes: 'text-xs', [Component.text('🔥')]),
                        ]),
                      ]),
                      p(classes: 'text-xs text-zinc-500 leading-normal', [
                        Component.text('Unlock full Hybrid permissions & tools 🔥'),
                      ]),
                      div(
                        classes:
                            'flex items-baseline gap-2 py-2 border-y ${isDark ? "border-zinc-800" : "border-zinc-150"}',
                        [
                          span(classes: 'text-3xl font-black text-indigo-400', [Component.text('Hybrid')]),
                          p(classes: 'text-[10px] text-zinc-500 leading-snug', [
                            Component.text('Simultaneously hire and work with no friction'),
                          ]),
                        ],
                      ),
                      div(classes: 'space-y-3 pt-2', [
                        _perkRow('Dual Nyxian & Employer permissions', true),
                        _perkRow('Priority search & listing exposure', true),
                        _perkRow('Reduced service fee (1.5% platform cut)', true),
                        _perkRow('Unlimited client/employer messages', true),
                        _perkRow('Premium Hybrid profile badge', true),
                      ]),
                    ]),

                    div(classes: 'space-y-4 pt-2', [
                      if (errorMessage != null)
                        p(classes: 'text-xs text-red-400 font-semibold text-center', [Component.text(errorMessage!)]),

                      if (!hasWallet) ...[
                        button(
                          classes:
                              'w-full py-3.5 rounded-2xl text-xs font-bold text-center bg-indigo-600 hover:bg-indigo-500 text-white shadow-lg shadow-indigo-600/20 transition-all border-0 cursor-pointer',
                          events: {
                            'click': (_) => s.handleConnectWallet(),
                          },
                          [Component.text('Connect Solana Wallet to Upgrade')],
                        ),
                      ] else ...[
                        div(classes: 'p-3.5 rounded-xl border $cardCls flex items-center justify-between text-xs', [
                          div([
                            span(classes: 'text-zinc-500 block text-[10px]', [Component.text('Connected Wallet')]),
                            span(classes: 'font-mono text-zinc-400 font-bold block mt-0.5', [
                              Component.text(
                                displayAddress.length > 12
                                    ? '${displayAddress.substring(0, 6)}...${displayAddress.substring(displayAddress.length - 6)}'
                                    : displayAddress,
                              ),
                            ]),
                          ]),
                          div(classes: 'text-right', [
                            span(classes: 'text-zinc-500 block text-[10px]', [Component.text('SOL Balance')]),
                            span(classes: 'font-semibold text-zinc-350 block mt-0.5', [
                              Component.text('${s.walletBalance.toStringAsFixed(4)} SOL'),
                            ]),
                          ]),
                        ]),

                        button(
                          classes:
                              'w-full py-3.5 rounded-2xl text-xs font-bold text-center text-white shadow-lg transition-all border-0 cursor-pointer '
                              '${s.walletBalance < activeSolPrice ? "bg-zinc-800/80 text-zinc-555 cursor-not-allowed" : "bg-indigo-600 hover:bg-indigo-500 shadow-indigo-600/20"}',
                          events: {
                            'click': (_) async {
                              if (s.walletBalance < activeSolPrice || isProcessing) return;
                              setState(() {
                                isProcessing = true;
                                errorMessage = null;
                              });
                              try {
                                await s.processSubscriptionPayment(activeSolPrice, selectedPlan);
                              } catch (e) {
                                setState(() {
                                  errorMessage = e.toString();
                                });
                              } finally {
                                setState(() {
                                  isProcessing = false;
                                });
                              }
                            },
                          },
                          [
                            if (isProcessing)
                              lIcon('loader-2', cls: 'w-4 h-4 animate-spin mr-1.5 inline')
                            else
                              lIcon('star', cls: 'w-4 h-4 mr-1.5 inline'),
                            Component.text(
                              s.walletBalance < activeSolPrice
                                  ? 'Insufficient SOL (Need ◎ ${activeSolPrice.toStringAsFixed(4)} SOL)'
                                  : 'Upgrade now (◎ ${activeSolPrice.toStringAsFixed(4)} SOL)',
                            ),
                          ],
                        ),
                      ],
                    ]),
                  ],
                ),
              ]),
            ]);
          },
        ),
    ]);
  }

  Component _stat(
    String value,
    String label,
    String icon,
    String iconCls,
    bool isDark, {
    String? actionLabel,
    void Function(dynamic)? onAction,
  }) {
    final cardCls = isDark
        ? 'bg-zinc-900/50 border-zinc-800/50 hover:border-indigo-500/30'
        : 'bg-white border-zinc-200 shadow-sm hover:border-indigo-500/30';

    return div(
      classes:
          'p-4 rounded-2xl border text-center transition-all duration-300 group $cardCls ${onAction != null ? "cursor-pointer" : ""}',
      events: onAction != null ? {'click': onAction} : null,
      [
        div(
          classes:
              'w-10 h-10 rounded-xl bg-zinc-500/5 flex items-center justify-center mx-auto mb-2 group-hover:scale-110 transition-transform duration-300',
          [lIcon(icon, cls: 'w-5 h-5 $iconCls')],
        ),
        p(classes: 'font-black text-xl md:text-2xl tracking-tight ${isDark ? "text-white" : "text-zinc-900"}', [
          Component.text(value),
        ]),
        p(
          classes:
              'text-[10px] uppercase font-black tracking-widest mt-1 ${isDark ? "text-zinc-500" : "text-zinc-400"}',
          [Component.text(label)],
        ),
        if (actionLabel != null)
          button(classes: 'mt-3 text-[10px] uppercase font-bold text-indigo-400 hover:text-indigo-300', [
            Component.text(actionLabel),
          ]),
      ],
    );
  }
}

// ── Personal Info ─────────────────────────────────────────────
class _PersonalInfo extends StatelessComponent {
  final TranyxAppState state;
  const _PersonalInfo({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    if (s.editName.isEmpty && (s.userProfile?.name.isNotEmpty == true || s.userName.isNotEmpty)) {
      s.initializeProfileEditing();
    }
    if (s.editEmail.isEmpty) {
      final authEmail = s.userEmail.isNotEmpty ? s.userEmail : (SessionStorage.email ?? '');
      if (authEmail.isNotEmpty) s.editEmail = authEmail;
    }
    if (s.editName.isEmpty) {
      final authName = (s.userName.isNotEmpty && s.userName != 'User')
          ? s.userName
          : (s.userProfile?.name.isNotEmpty == true && s.userProfile!.name != 'User'
              ? s.userProfile!.name
              : (SessionStorage.displayName ?? ''));
      if (authName.isNotEmpty) s.editName = authName;
    }

    return div(classes: 'space-y-6', [
      subViewHeader(
        title: 'Personal Information',
        isDark: s.isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),
      if (s.userProfile == null)
        div(classes: 'p-4 rounded-2xl bg-amber-500/10 border border-amber-500/20 flex items-center gap-3', [
          lIcon('alert-triangle', cls: 'w-5 h-5 text-amber-500'),
          div([
            p(classes: 'font-bold text-amber-500 text-sm', [Component.text('Profile Setup Required')]),
            p(classes: 'text-xs ${s.isDark ? "text-zinc-400" : "text-zinc-650"}', [
              Component.text('Enter your name and email, then click "Save Changes" to activate your account.'),
            ]),
          ]),
        ]),

      // Profile Photo Upload Card
      div(
        classes:
            'p-5 rounded-3xl border ${s.isDark ? "bg-zinc-900/60 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"} flex items-center justify-between gap-4',
        [
          div(classes: 'flex items-center gap-4', [
            div(
              classes:
                  'w-16 h-16 rounded-full overflow-hidden flex items-center justify-center relative bg-indigo-600/20 border-2 border-indigo-500/30 shrink-0 shadow-sm',
              [
                if (s.userPhotoUrl != null && s.userPhotoUrl!.isNotEmpty)
                  img(src: s.userPhotoUrl!, classes: 'w-full h-full object-cover')
                else
                  span(classes: 'text-xl font-bold text-indigo-400', [
                    Component.text(s.userName.isNotEmpty ? s.userName[0].toUpperCase() : '?'),
                  ]),
                if (s.isUploadingProfilePhoto)
                  div(
                    classes: 'absolute inset-0 bg-black/60 flex items-center justify-center backdrop-blur-sm',
                    [lIcon('loader-2', cls: 'w-5 h-5 animate-spin text-white')],
                  ),
              ],
            ),
            div([
              p(classes: 'text-sm font-bold ${s.isDark ? "text-white" : "text-zinc-900"}', [
                Component.text('Profile Picture'),
              ]),
              p(classes: 'text-xs ${s.isDark ? "text-zinc-400" : "text-zinc-500"} mt-0.5', [
                Component.text('Upload custom photo (PNG, JPG, WebP)'),
              ]),
            ]),
          ]),
          label(
            classes:
                'px-4 py-2.5 rounded-xl font-bold text-xs bg-indigo-600 hover:bg-indigo-700 text-white cursor-pointer transition-all flex items-center gap-2 shadow-sm shrink-0',
            [
              lIcon(s.isUploadingProfilePhoto ? 'loader-2' : 'camera',
                  cls: 'w-4 h-4 ${s.isUploadingProfilePhoto ? "animate-spin" : ""}'),
              Component.text(s.isUploadingProfilePhoto ? 'Uploading...' : 'Change Photo'),
              input(
                type: InputType.file,
                classes: 'hidden',
                attributes: {'accept': 'image/*'},
                events: {'change': (e) => s.handleProfilePhotoUpload(e)},
              ),
            ],
          ),
        ],
      ),

      div(classes: 'space-y-4', [
        inputField(
          label: 'Full Name',
          placeholder: 'Juan Dela Cruz',
          iconName: 'user-circle',
          isDark: s.isDark,
          value: s.editName,
          onChange: (v) => s.setState(() => s.editName = v),
        ),
        inputField(
          label: 'Email Address',
          placeholder: 'juan@example.com',
          iconName: 'mail',
          type: 'email',
          isDark: s.isDark,
          value: s.editEmail,
          onChange: (v) => s.setState(() => s.editEmail = v),
        ),
        div(classes: 'space-y-1', [
          label(
            classes:
                'block text-xs font-bold ${s.isDark ? "text-zinc-400" : "text-zinc-500"} uppercase tracking-wider mb-1',
            [
              Component.text('Phone Number (Starts with 9)'),
            ],
          ),
          div(classes: 'flex gap-2 items-stretch', [
            div(
              classes:
                  'px-4 py-3 rounded-2xl flex items-center bg-zinc-500/10 font-bold border border-zinc-500/20 text-zinc-500 text-sm',
              [Component.text('+63')],
            ),
            div(classes: 'flex-1 relative', [
              input(
                type: InputType.text,
                attributes: {
                  'placeholder': '917 000 0000',
                  'id': 'edit-profile-phone-input',
                  'name': 'phone',
                },
                value: s.formatPhone(s.editPhone),
                classes:
                    'w-full px-5 py-4 pl-12 rounded-2xl border bg-transparent font-medium focus:outline-none focus:ring-2 focus:ring-indigo-500/20 transition-all ${s.isDark ? "border-zinc-800 focus:border-indigo-500/50 text-white" : "border-zinc-200 focus:border-indigo-500 text-zinc-800"}',
                events: {
                  'input': (e) {
                    final val = getInputValue(e.target);
                    final digits = val.replaceAll(RegExp(r'\D'), '');
                    var phoneNum = digits;
                    if (phoneNum.startsWith('63')) phoneNum = phoneNum.substring(2);
                    if (phoneNum.startsWith('0')) phoneNum = phoneNum.substring(1);
                    if (phoneNum.length > 10) phoneNum = phoneNum.substring(0, 10);
                    s.setState(() => s.editPhone = phoneNum);
                  },
                },
              ),
              span(classes: 'absolute left-4 top-1/2 -translate-y-1/2 opacity-50', [
                lIcon('phone', cls: 'w-5 h-5'),
              ]),
            ]),
          ]),
        ]),
        inputField(
          label: 'Tax ID / TIN (Philippines)',
          placeholder: '000-000-000-000',
          iconName: 'file-text',
          isDark: s.isDark,
          value: s.formatTIN(s.editTaxId),
          onChange: (v) {
            final digits = v.replaceAll(RegExp(r'\D'), '');
            final tin = digits.substring(0, digits.length > 12 ? 12 : digits.length);
            s.setState(() => s.editTaxId = tin);
          },
        ),
      ]),

      // Location Services & GPS Privacy Card
      div(
        classes:
            'p-5 rounded-2xl border ${s.isDark ? "bg-zinc-900/60 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"} space-y-4',
        [
          div(classes: 'flex items-center justify-between', [
            div(classes: 'flex items-center gap-3', [
              div(
                classes:
                    'w-10 h-10 rounded-xl flex items-center justify-center ${s.isLocationEnabled ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20" : "bg-zinc-500/10 text-zinc-500 border border-zinc-500/20"}',
                [lIcon('map-pin', cls: 'w-5 h-5')],
              ),
              div([
                h4(classes: 'font-bold text-sm ${s.isDark ? "text-white" : "text-zinc-900"}', [
                  Component.text('Location Services & GPS'),
                ]),
                p(classes: 'text-xs ${s.isDark ? "text-zinc-400" : "text-zinc-500"} mt-0.5', [
                  Component.text(
                    s.isLocationEnabled
                        ? (s.hasAcquiredGps
                            ? 'GPS locked — Real-time position active for jobs, transit & navigation'
                            : 'Enabled — Awaiting GPS fix from browser')
                        : 'Disabled — Maps use default Manila coordinates',
                  ),
                ]),
              ]),
            ]),
            // Accessible Standard Toggle Switch
            button(
              classes:
                  'relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none ${s.isLocationEnabled ? "bg-indigo-600" : "bg-zinc-700"}',
              attributes: {
                'type': 'button',
                'title': s.isLocationEnabled ? 'Disable Location Services' : 'Enable Location Services',
              },
              events: {
                'click': (_) async {
                  final willEnable = !s.isLocationEnabled;
                  s.setState(() {
                    s.isLocationEnabled = willEnable;
                    if (!willEnable) {
                      s.hasAcquiredGps = false;
                      s.locationStatusMessage = 'Disabled';
                    }
                  });
                  if (willEnable) {
                    await s.requestAndUpdateUserLocation();
                  }
                },
              },
              [
                span(
                  [],
                  classes:
                      'pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${s.isLocationEnabled ? "translate-x-5" : "translate-x-0"}',
                ),
              ],
            ),
          ]),

          if (s.isLocationEnabled) ...[
            div(
              classes:
                  'p-3.5 rounded-xl border flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs ${s.isDark ? "bg-zinc-800/40 border-zinc-800/80" : "bg-zinc-50 border-zinc-200"}',
              [
                div([
                  div(classes: 'flex items-center gap-2', [
                    span(classes: 'font-semibold ${s.isDark ? "text-zinc-300" : "text-zinc-700"} block', [
                      Component.text(s.hasAcquiredGps ? 'Current Position (GPS Locked)' : 'Location Status'),
                    ]),
                    if (s.locationStatusMessage != null)
                      span(
                        classes:
                            'text-[10px] px-2 py-0.5 rounded-full font-bold ${s.hasAcquiredGps ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30" : (s.locationErrorCode == 1 ? "bg-red-500/15 text-red-400 border border-red-500/30" : "bg-amber-500/15 text-amber-400 border border-amber-500/30")}',
                        [Component.text(s.locationStatusMessage!)],
                      ),
                  ]),
                  if (s.hasAcquiredGps && s.gpsLatitude != null && s.gpsLongitude != null)
                    span(classes: 'font-mono text-xs ${s.isDark ? "text-emerald-400" : "text-emerald-600"} mt-0.5 block font-bold', [
                      Component.text('${s.gpsLatitude!.toStringAsFixed(4)}° N, ${s.gpsLongitude!.toStringAsFixed(4)}° E'),
                    ])
                  else
                    span(classes: 'text-[11px] ${s.isDark ? "text-zinc-400" : "text-zinc-500"} mt-0.5 block', [
                      Component.text('Default map center: ${s.userLatitude.toStringAsFixed(4)}° N, ${s.userLongitude.toStringAsFixed(4)}° E (Manila)'),
                    ]),
                ]),
                button(
                  classes:
                      'px-3.5 py-2 rounded-lg text-xs font-semibold bg-indigo-600/20 text-indigo-400 hover:bg-indigo-600/30 transition-colors flex items-center justify-center gap-1.5 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed',
                  attributes: s.isDetectingLocation ? {'disabled': 'disabled'} : {},
                  events: {
                    'click': (_) async {
                      if (!s.isDetectingLocation) {
                        await s.requestAndUpdateUserLocation();
                      }
                    },
                  },
                  [
                    if (s.isDetectingLocation)
                      lIcon('loader-2', cls: 'w-3.5 h-3.5 animate-spin')
                    else
                      lIcon('navigation', cls: 'w-3.5 h-3.5'),
                    Component.text(s.isDetectingLocation ? 'Detecting GPS...' : 'Detect GPS Location'),
                  ],
                ),
              ],
            ),

            if (s.locationErrorCode == 1)
              div(
                classes:
                    'p-3 rounded-xl bg-amber-500/10 border border-amber-500/20 flex items-start gap-2.5 text-xs text-amber-400',
                [
                  lIcon('alert-triangle', cls: 'w-4 h-4 mt-0.5 flex-shrink-0 text-amber-400'),
                  p(classes: 'leading-relaxed', [
                    Component.text(
                      'Browser permission is blocked. To grant access: Click the lock / tune icon in your browser address bar, set Location to "Allow", and click "Detect GPS Location".',
                    ),
                  ]),
                ],
              ),
          ],
        ],
      ),

      if (s.profileSaveError != null)
        p(classes: 'text-sm text-red-400 text-center', [Component.text(s.profileSaveError!)]),
      button(
        classes:
            'w-full py-4 rounded-2xl font-semibold text-white '
            '${s.hasPersonalInfoChanges && s.isPersonalInfoValid ? "logo-gradient hover:opacity-90 transition-opacity cursor-pointer shadow-lg shadow-indigo-500/20" : "bg-zinc-800/50 text-zinc-500 border border-zinc-850 cursor-not-allowed"} '
            'flex items-center justify-center gap-2',
        events: (s.hasPersonalInfoChanges && s.isPersonalInfoValid) ? {'click': (_) => s.handleSavePersonalInfo()} : {},
        [
          if (s.isSavingProfile) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
          Component.text(s.isSavingProfile ? 'Saving...' : 'Save Changes'),
        ],
      ),
    ]);
  }
}

// ── Professional Info ─────────────────────────────────────────
class _ProfessionalInfo extends StatelessComponent {
  final TranyxAppState state;
  const _ProfessionalInfo({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    if (s.editHeadline.isEmpty && s.editSkills.isEmpty && (s.userProfile?.headline?.isNotEmpty == true || s.userProfile?.skills?.isNotEmpty == true || s.userProfile?.businessName?.isNotEmpty == true || s.userProfile?.industry?.isNotEmpty == true)) {
      s.initializeProfileEditing();
    }
    final isDark = s.isDark;
    final isNyxian = s.accountType == AccountType.nyxian || s.accountType == AccountType.hybrid;
    final isEmployer = s.accountType == AccountType.employer || s.accountType == AccountType.hybrid;
    final sectionCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    final skills = s.editSkills;

    return div(classes: 'space-y-6', [
      subViewHeader(
        title: 'Professional Info',
        isDark: isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),
      if (s.userProfile == null)
        div(classes: 'p-4 rounded-2xl bg-amber-500/10 border border-amber-500/20 flex items-center gap-3', [
          lIcon('alert-triangle', cls: 'w-5 h-5 text-amber-500'),
          div([
            p(classes: 'font-bold text-amber-500 text-sm', [Component.text('Profile Setup Required')]),
            p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-650"}', [
              Component.text('Please complete and save your Personal Information first to register your profile.'),
            ]),
          ]),
        ]),

      if (isNyxian) ...[
        div(classes: 'p-5 rounded-2xl border $sectionCls space-y-4', [
          div(classes: 'flex items-center gap-2 mb-2', [
            span(classes: 'px-2 py-0.5 rounded text-xs font-bold bg-green-500/20 text-green-400', [
              Component.text('NYXIAN PROFILE'),
            ]),
          ]),
          inputField(
            label: 'Headline',
            placeholder: 'e.g. Expert Electrician & Handyman',
            iconName: 'zap',
            isDark: isDark,
            value: s.editHeadline,
            onChange: (v) => s.setState(() => s.editHeadline = v),
          ),
          inputField(
            label: 'Hourly Rate (₱)',
            placeholder: '250',
            iconName: 'wallet',
            isDark: isDark,
            value: s.editHourlyRate,
            onChange: (v) => s.setState(() => s.editHourlyRate = v),
          ),
          div([
            span(classes: 'text-xs font-medium ${isDark ? "text-zinc-500" : "text-zinc-400"} block mb-2', [
              Component.text('Skills'),
            ]),
            div(classes: 'flex flex-wrap gap-2', [
              for (final skill in skills)
                button(
                  classes:
                      'flex items-center gap-1 px-3 py-1.5 rounded-lg text-xs font-semibold bg-indigo-600/20 text-indigo-400 hover:bg-red-500/20 hover:text-red-400 transition-colors',
                  events: {
                    'click': (_) => s.setState(() {
                      final updated = List<String>.from(skills)..remove(skill);
                      s.editSkills = updated;
                    }),
                  },
                  [Component.text(skill), lIcon('x', cls: 'w-3 h-3 ml-1')],
                ),
              // Add skill input
              div(classes: 'flex items-center gap-1', [
                input(
                  classes:
                      'px-3 py-1.5 rounded-lg text-xs border ${isDark ? "bg-zinc-800 border-zinc-700 text-zinc-200" : "bg-zinc-50 border-zinc-200"} outline-none w-28',
                  type: InputType.text,
                  attributes: {
                    'placeholder': '+ Add skill',
                    'value': s.newSkillInput,
                    'id': 'edit-profile-skill-input',
                    'name': 'new_skill',
                  },
                  events: {
                    'input': (e) {
                      final v = getInputValue(e.target);
                      s.setState(() => s.newSkillInput = v);
                    },
                    'keydown': (e) {
                      final key = (e as web.KeyboardEvent).key;
                      if (key == 'Enter' && s.newSkillInput.trim().isNotEmpty) {
                        final updated = List<String>.from(skills)..add(s.newSkillInput.trim());
                        s.setState(() {
                          s.editSkills = updated;
                          s.newSkillInput = '';
                        });
                      }
                    },
                  },
                ),
              ]),
            ]),
          ]),

          // ── Credential Upload Center ──
          div(classes: 'border-t ${isDark ? "border-zinc-800" : "border-zinc-150"} pt-4 space-y-3', [
            span(classes: 'text-xs font-bold ${isDark ? "text-zinc-300" : "text-zinc-700"} flex items-center gap-1', [
              lIcon('award', cls: 'w-4 h-4 text-indigo-400'),
              Component.text('Professional Certifications & Licenses'),
            ]),
            p(classes: 'text-[10px] text-zinc-500 leading-relaxed', [
              Component.text(
                'Upload verified TESDA National Certificates, PRC Board IDs, or other professional credentials to display verified status badges on applicant cards.',
              ),
            ]),

            // Render currently uploaded certificate links
            if (s.userProfile?.certificationUrls != null && s.userProfile!.certificationUrls!.isNotEmpty)
              div(classes: 'space-y-1.5', [
                for (final url in s.userProfile!.certificationUrls!)
                  div(
                    classes:
                        'flex items-center justify-between p-2 rounded-xl border ${isDark ? "bg-zinc-950/40 border-zinc-850" : "bg-zinc-50 border-zinc-200"} text-xs',
                    [
                      a(
                        href: url,
                        target: Target.blank,
                        classes: 'text-indigo-400 hover:underline truncate max-w-[70%]',
                        [
                          Component.text('Certificate Document ${s.userProfile!.certificationUrls!.indexOf(url) + 1}'),
                        ],
                      ),
                      span(
                        classes:
                            'text-[10px] font-bold text-green-400 bg-green-500/10 px-1.5 py-0.5 rounded-lg border border-green-500/25',
                        [
                          Component.text('Verified'),
                        ],
                      ),
                    ],
                  ),
              ]),

            // Upload button
            div(classes: 'relative mt-2', [
              button(
                classes:
                    'w-full py-3 rounded-xl border border-dashed text-xs font-semibold flex items-center justify-center gap-2 cursor-pointer '
                    '${isDark ? "border-zinc-700 hover:border-zinc-500 text-zinc-400" : "border-zinc-300 hover:border-zinc-400 text-zinc-500"} transition-all',
                [
                  if (s.isUploadingCertificate)
                    lIcon('loader-2', cls: 'w-4 h-4 animate-spin')
                  else
                    lIcon('upload-cloud', cls: 'w-4 h-4 text-indigo-400'),
                  Component.text(
                    s.isUploadingCertificate ? 'Uploading Document...' : 'Upload Certificate / ID (PDF/Image)',
                  ),
                ],
              ),
              input(
                type: InputType.file,
                classes: 'absolute inset-0 opacity-0 cursor-pointer',
                attributes: {
                  'accept': 'image/*,application/pdf',
                  'id': 'certificate-upload-input',
                  'name': 'certificate',
                },
                events: {
                  'change': (e) => s.uploadCertification(e),
                },
              ),
            ]),
          ]),
        ]),
      ],

      if (isEmployer) ...[
        div(classes: 'p-5 rounded-2xl border $sectionCls space-y-4', [
          div(classes: 'flex items-center gap-2 mb-2', [
            span(classes: 'px-2 py-0.5 rounded text-xs font-bold bg-blue-500/20 text-blue-400', [
              Component.text('EMPLOYER PROFILE'),
            ]),
          ]),
          inputField(
            label: 'Business/Company Name (Optional)',
            placeholder: 'Juan Constructions',
            iconName: 'building',
            isDark: isDark,
            value: s.editBusinessName,
            onChange: (v) => s.setState(() => s.editBusinessName = v),
          ),
          inputField(
            label: 'Industry',
            placeholder: 'Construction & Real Estate',
            iconName: 'briefcase',
            isDark: isDark,
            value: s.editIndustry,
            onChange: (v) => s.setState(() => s.editIndustry = v),
          ),
          inputField(
            label: 'Tax ID / TIN (Philippines)',
            placeholder: '000-000-000-000',
            iconName: 'file-text',
            isDark: isDark,
            value: s.formatTIN(s.editTaxId),
            onChange: (v) {
              final digits = v.replaceAll(RegExp(r'\D'), '');
              final tin = digits.substring(0, digits.length > 12 ? 12 : digits.length);
              s.setState(() => s.editTaxId = tin);
            },
          ),
        ]),
      ],

      if (s.profileSaveError != null)
        p(classes: 'text-sm text-red-400 text-center', [Component.text(s.profileSaveError!)]),
      button(
        classes:
            'w-full py-4 rounded-2xl font-semibold text-white '
            '${s.hasProfessionalInfoChanges && s.isProfessionalInfoValid ? "logo-gradient hover:opacity-90 transition-opacity cursor-pointer shadow-lg shadow-indigo-500/20" : "bg-zinc-800/50 text-zinc-500 border border-zinc-850 cursor-not-allowed"} '
            'flex items-center justify-center gap-2',
        events: (s.hasProfessionalInfoChanges && s.isProfessionalInfoValid)
            ? {'click': (_) => s.handleSaveProfessionalInfo()}
            : {},
        [
          if (s.isSavingProfile) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
          Component.text(s.isSavingProfile ? 'Saving...' : 'Save Changes'),
        ],
      ),
    ]);
  }
}

// ── Payment Methods ───────────────────────────────────────────
class _Payment extends StatelessComponent {
  final TranyxAppState state;
  const _Payment({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;

    return div(classes: 'space-y-6', [
      subViewHeader(
        title: 'Payment Methods',
        isDark: isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),

      // Tyx Wallet Card
      div(
        classes:
            'p-8 rounded-[2.5rem] logo-gradient text-white relative overflow-hidden shadow-2xl shadow-indigo-500/20',
        [
          div(classes: 'absolute inset-0 opacity-20', [
            div(
              [],
              classes:
                  'absolute top-0 right-0 w-64 h-64 rounded-full bg-white/20 translate-x-24 -translate-y-24 blur-3xl',
            ),
            div(
              [],
              classes:
                  'absolute bottom-0 left-0 w-48 h-48 rounded-full bg-white/10 -translate-x-12 translate-y-12 blur-2xl',
            ),
          ]),
          div(classes: 'relative z-10 space-y-8', [
            div(classes: 'flex justify-between items-start', [
              div([
                p(classes: 'text-[10px] font-black uppercase tracking-[0.2em] opacity-70 mb-1', [
                  Component.text('Tyxbit Main Wallet'),
                ]),
                p(classes: 'text-sm font-medium opacity-90', [Component.text(s.userName)]),
              ]),
              div(
                classes:
                    'w-12 h-12 rounded-2xl bg-white/10 backdrop-blur-md flex items-center justify-center border border-white/20',
                [
                  lIcon('wallet', cls: 'w-6 h-6 text-white'),
                ],
              ),
            ]),

            div([
              p(classes: 'text-4xl font-black flex items-center gap-3', [
                span(classes: 'text-2xl opacity-60', [Component.text('₱')]),
                Component.text((s.userProfile?.tyxBalance ?? 0.0).toStringAsFixed(2)),
              ]),
              p(classes: 'text-xs opacity-60 mt-2 font-mono tracking-widest uppercase', [
                Component.text('tranyx-tyxbit-v1 :: ${s.userProfile?.uid.substring(0, 8) ?? "tx-9921"}'),
              ]),
            ]),

            Builder(
              builder: (context) {
                final pendingTotal = s.pendingHoldbacks.fold<double>(0.0, (sum, item) {
                  final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
                  return sum + amt;
                });
                if (pendingTotal > 0) {
                  return div(classes: 'p-4 rounded-2xl bg-amber-500/10 border border-amber-500/20 text-left space-y-2', [
                    p(classes: 'text-xs font-bold text-amber-400 flex items-center gap-1.5', [
                      lIcon('clock', cls: 'w-4 h-4'),
                      Component.text('Pending Release (48-Hr Holdback): ₱ ${pendingTotal.toStringAsFixed(2)}'),
                    ]),
                    p(classes: 'text-[10px] text-zinc-400 font-medium leading-relaxed', [
                      Component.text(
                        'In-app payments are held temporarily to protect users from incomplete jobs. Payouts release automatically after their inspection periods.',
                      ),
                    ]),
                    div(classes: 'space-y-1.5 pt-1.5 border-t border-amber-500/20', [
                      for (final holdback in s.pendingHoldbacks)
                        Builder(
                          builder: (context) {
                            final amt = (holdback['amount'] as num?)?.toDouble() ?? 0.0;
                            final relAt = holdback['releaseAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
                            final hrs = ((relAt - DateTime.now().millisecondsSinceEpoch) / (1000 * 60 * 60)).ceil();
                            final hrsStr = hrs <= 0
                                ? 'processing release'
                                : 'releases in $hrs hr${hrs == 1 ? "" : "s"}';
                            return p(
                              classes: 'text-[10px] text-amber-300 font-medium flex justify-between items-center',
                              [
                                Component.text('• Php ${amt.toStringAsFixed(2)}'),
                                span(
                                  classes: 'text-[9px] px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-400 font-bold',
                                  [
                                    Component.text(hrsStr),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                    ]),
                  ]);
                }
                return div([]);
              },
            ),

            div(classes: 'flex gap-3', [
              if (s.accountType == AccountType.employer || s.accountType == AccountType.hybrid)
                button(
                  classes:
                      'flex-1 py-3.5 rounded-2xl bg-white/10 backdrop-blur-md border border-white/20 font-bold text-sm hover:bg-white/20 transition-all flex items-center justify-center gap-2',
                  events: {'click': (_) => s.setState(() => s.showDepositModal = true)},
                  [lIcon('arrow-down-left', cls: 'w-4 h-4'), Component.text('Deposit')],
                ),
              if (s.accountType == AccountType.nyxian || s.accountType == AccountType.hybrid)
                button(
                  classes:
                      'flex-1 py-3.5 rounded-2xl bg-black/20 backdrop-blur-md border border-white/10 font-bold text-sm hover:bg-black/30 transition-all flex items-center justify-center gap-2 cursor-pointer',
                  events: {'click': (_) => s.setState(() => s.showWithdrawModal = true)},
                  [
                    lIcon('arrow-up-right', cls: 'w-4 h-4'),
                    Component.text('Withdraw'),
                  ],
                ),
            ]),
          ]),
        ],
      ),

      // Profile Promo Section
      div(
        classes:
            'p-6 rounded-[2rem] border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-sm"} space-y-4',
        [
          p(classes: 'text-sm font-bold', [Component.text('Redeem Profile Promo Code')]),
          p(classes: 'text-xs text-zinc-400', [
            Component.text(
              'Redeem a promo code directly to your profile. Applicable discounts (e.g. payout commission reductions) will be applied automatically.',
            ),
          ]),
          if (s.userProfile?.activePromoCode != null)
            div(
              classes:
                  'p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/20 flex justify-between items-center text-xs font-semibold text-emerald-500',
              [
                div(classes: 'flex flex-col gap-1', [
                  span([Component.text('Active Profile Promo: ${s.userProfile!.activePromoCode}')]),
                  span([
                    Component.text(
                      s.userProfile!.activePromoDiscountType == 'percentage'
                          ? '${s.userProfile!.activePromoDiscountValue?.toStringAsFixed(0) ?? "0"}% Off Payout Commission'
                          : '₱ ${(s.userProfile!.activePromoDiscountValue ?? 0.0).toStringAsFixed(2)} Off Payout Commission',
                    ),
                  ]),
                ]),
                button(
                  classes:
                      'ml-4 px-3 py-1.5 rounded-lg bg-rose-500/20 hover:bg-rose-500/30 text-rose-500 cursor-pointer border-0 outline-none text-[10px] uppercase font-black tracking-wider transition-all',
                  events: {
                    'click': (e) {
                      s.handleDisableProfilePromo(s.userProfile!.activePromoCode!);
                    },
                  },
                  [Component.text('Disable')],
                ),
              ],
            ),
          div(classes: 'flex gap-2', [
            input(
              classes:
                  'flex-1 p-3 rounded-xl border ${isDark ? "bg-zinc-800 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none focus:border-indigo-500 transition-colors text-sm',
              attributes: {'value': s.profilePromoCodeInput, 'placeholder': 'Enter profile promo code'},
              events: {
                'input': (e) {
                  s.profilePromoCodeInput = getInputValue(e.target);
                },
              },
            ),
            button(
              classes:
                  'px-4 py-2 rounded-xl font-semibold text-white bg-indigo-600 hover:bg-indigo-700 transition-colors cursor-pointer border-0 outline-none text-sm',
              events: {
                'click': (e) {
                  s.handleRedeemProfilePromo(s.profilePromoCodeInput);
                },
              },
              [
                Component.text(s.isValidatingProfilePromo ? 'Redeeming...' : 'Redeem'),
              ],
            ),
          ]),
          if (s.profilePromoFeedback != null)
            p(
              classes:
                  'text-xs font-semibold ${s.profilePromoFeedback!.contains("successfully") ? "text-emerald-500" : "text-red-500"}',
              [Component.text(s.profilePromoFeedback!)],
            ),
        ],
      ),

      // Add payment method
      button(
        classes:
            'w-full flex items-center justify-center gap-2 py-4 rounded-2xl border border-dashed ${isDark ? "border-zinc-700 text-zinc-500 hover:border-indigo-500 hover:text-indigo-400" : "border-zinc-300 text-zinc-400 hover:border-indigo-400"} transition-colors',
        events: {},
        [lIcon('plus', cls: 'w-5 h-5'), Component.text('  Add Payment Method')],
      ),
    ]);
  }
}

// ── Withdraw Funds Pane ───────────────────────────────────────
class _WithdrawPane extends StatefulComponent {
  final TranyxAppState state;
  const _WithdrawPane({required this.state});

  @override
  State<_WithdrawPane> createState() => _WithdrawPaneState();
}

class _WithdrawPaneState extends State<_WithdrawPane> {
  String _amountInput = '100';
  String _selectedCoin = 'USDT'; // 'USDT' (SPL) or 'SOL'
  double _solToPhpRate = 8000.0;
  double _usdToPhpRate = 57.0;
  bool _isFetchingRates = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _fetchLiveRates();
  }

  Future<void> _fetchLiveRates() async {
    setState(() => _isFetchingRates = true);
    try {
      final cgRes = await http
          .get(
            Uri.parse(
              'https://api.coingecko.com/api/v3/simple/price?ids=solana,tether&vs_currencies=php,usd',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (cgRes.statusCode == 200) {
        final data = jsonDecode(cgRes.body) as Map<String, dynamic>;
        final sol = (data['solana']?['php'] as num?)?.toDouble();
        final usdt = (data['tether']?['php'] as num?)?.toDouble();
        setState(() {
          if (sol != null && sol > 0) _solToPhpRate = sol;
          if (usdt != null && usdt > 0) _usdToPhpRate = usdt;
        });
      } else {
        final binanceRes = await http
            .get(
              Uri.parse(
                'https://api.binance.com/api/v3/ticker/price?symbol=SOLUSDT',
              ),
            )
            .timeout(const Duration(seconds: 4));
        final usdPhpRes = await http
            .get(Uri.parse('https://open.er-api.com/v6/latest/USD'))
            .timeout(const Duration(seconds: 4));

        double usdPhp = 57.0;
        if (usdPhpRes.statusCode == 200) {
          final usdData = jsonDecode(usdPhpRes.body) as Map<String, dynamic>;
          final php = (usdData['rates']?['PHP'] as num?)?.toDouble();
          if (php != null && php > 0) usdPhp = php;
        }

        if (binanceRes.statusCode == 200) {
          final bData = jsonDecode(binanceRes.body) as Map<String, dynamic>;
          final solUsd =
              double.tryParse(bData['price']?.toString() ?? '') ?? 0.0;
          if (solUsd > 0) {
            setState(() {
              _solToPhpRate = solUsd * usdPhp;
              _usdToPhpRate = usdPhp;
            });
          }
        }
      }
    } catch (_) {
      // Sensible defaults maintained if offline
    } finally {
      setState(() => _isFetchingRates = false);
    }
  }

  void _setPresetAmount(double amount, double maxBal) {
    final clamped = amount.clamp(0.0, maxBal);
    setState(() {
      _amountInput = clamped.toStringAsFixed(0);
      _errorMessage = null;
    });
  }

  Future<void> _submitWithdrawal() async {
    final s = component.state;
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;

    if (uid == null || token == null) {
      setState(() => _errorMessage = 'Please sign in to proceed.');
      return;
    }

    final hasActiveVehicleRentals = s.realtimeRentals.any((rMap) {
      final rental = VehicleRental.fromMap(rMap, rMap['id'] ?? '');
      final isRenter = (rental.renteeId == uid);
      final statusLower = rental.status.toLowerCase();
      final isActive = (statusLower != 'completed' && statusLower != 'cancelled');
      return isRenter && isActive;
    });

    final hasActivePropertyRentals = s.realtimeProperties.any((prop) {
      final isRenter = (prop.renteeId == uid);
      final statusLower = prop.status.toLowerCase();
      final isActive = (statusLower != 'completed' && statusLower != 'cancelled' && statusLower != 'available');
      return isRenter && isActive;
    });

    if (hasActiveVehicleRentals || hasActivePropertyRentals) {
      setState(
        () => _errorMessage =
            'Withdrawals are disabled while you have active/ongoing rentals.',
      );
      return;
    }

    final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
    final amount = double.tryParse(_amountInput.trim()) ?? 0.0;

    if (amount < 100) {
      setState(() => _errorMessage = 'Minimum withdrawal amount is ₱ 100.00.');
      return;
    }

    if (amount > tyxBal) {
      setState(() => _errorMessage = 'Requested amount exceeds your available balance.');
      return;
    }

    final walletKey = s.walletAddress.isNotEmpty ? s.walletAddress : (s.userProfile?.walletPublicKey ?? '');

    if (walletKey.isEmpty) {
      setState(
        () => _errorMessage =
            'Withdrawals are only available to connected Solana wallets. Please link your Solana wallet first in Payment Methods or Trust & Verification.',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final requestId = 'withdraw_$timestamp';
      final svc = FirestoreService(token, s.handleTokenRefresh);
      final methodTitle = 'Solana ($_selectedCoin)';

      final feePhp = (amount * 0.02);
      final netPhp = (amount - feePhp);
      final activeRate = _selectedCoin == 'SOL' ? (_solToPhpRate > 0 ? _solToPhpRate : 8000.0) : (_usdToPhpRate > 0 ? _usdToPhpRate : 57.0);
      final cryptoAmount = activeRate > 0 ? netPhp / activeRate : 0.0;

      final requestData = <String, dynamic>{
        'id': requestId,
        'uid': uid,
        'userName': s.userName,
        'amount': amount,
        'feeAmount': feePhp,
        'netAmount': netPhp,
        'cryptoAmount': cryptoAmount,
        'rateUsed': activeRate,
        'status': 'Pending',
        'createdAt': timestamp,
        'currency': 'PHP',
        'method': 'Solana',
        'methodTitle': methodTitle,
        'coin': _selectedCoin,
        'walletPublicKey': walletKey,
      };

      // 1. Direct on-chain treasury transfer if private key configured
      String txSignature = '';
      bool isOnChainTransferred = false;

      final treasuryPrivKey = Env.solanaPrivateKey;
      if (treasuryPrivKey.isNotEmpty) {
        try {
          if (_selectedCoin == 'SOL') {
            final lamports = (cryptoAmount * 1e9).round();
            if (lamports > 0) {
              final sig = await broadcastTreasuryTransfer(
                treasuryPrivKeyBase58: treasuryPrivKey,
                recipientPubkey: walletKey,
                lamports: lamports,
              );
              if (sig != null && sig.isNotEmpty) {
                txSignature = sig;
                isOnChainTransferred = true;
              }
            }
          } else {
            if (cryptoAmount > 0) {
              final sig = await broadcastTreasuryTokenTransfer(
                treasuryPrivKeyBase58: treasuryPrivKey,
                recipientPubkey: walletKey,
                amountInUsdt: cryptoAmount,
              );
              if (sig != null && sig.isNotEmpty) {
                txSignature = sig;
                isOnChainTransferred = true;
              }
            }
          }
        } catch (vaultErr) {
          print('Direct client-side vault transfer skipped/queued: $vaultErr');
        }
      }

      final txStatus = isOnChainTransferred ? 'Successful' : 'Pending';

      // 2. Save withdrawal request record
      await svc.createOrUpdate('withdrawalRequests/$requestId', {
        ...requestData,
        'status': txStatus,
        if (txSignature.isNotEmpty) 'solanaTxSignature': txSignature,
      });

      // 3. Create transaction record
      await svc.createOrUpdate('transactions/tx_$timestamp', {
        'id': 'tx_$timestamp',
        'uid': uid,
        'title': isOnChainTransferred
            ? 'Withdrawal Successful ($methodTitle)'
            : 'Withdrawal Request ($methodTitle)',
        'type': 'withdraw',
        'amount': -amount,
        'feeAmount': feePhp,
        'netAmount': netPhp,
        'cryptoAmount': cryptoAmount,
        'rateUsed': activeRate,
        'currency': 'PHP',
        'status': txStatus,
        'createdAt': timestamp,
        'walletPublicKey': walletKey,
        'coin': _selectedCoin,
        if (txSignature.isNotEmpty) 'solanaTxSignature': txSignature,
        'desc': isOnChainTransferred
            ? 'Withdrew ₱${amount.toStringAsFixed(2)} to $walletKey (${cryptoAmount.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin). On-Chain Tx: $txSignature'
            : 'Requested ₱${amount.toStringAsFixed(2)} withdrawal to $walletKey (${cryptoAmount.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin)',
      });

      // 4. Deduct from user profile balance
      final newBalance = (tyxBal - amount).clamp(0.0, double.infinity);
      await svc.createOrUpdate('users/$uid', {'tyxBalance': newBalance});

      s.setState(() {
        if (s.userProfile != null) {
          s.userProfile = s.userProfile!.copyWith(tyxBalance: newBalance);
        }
      });

      setState(() {
        _isSubmitting = false;
        _successMessage = isOnChainTransferred
            ? 'Withdrawal of ₱ ${amount.toStringAsFixed(2)} (${cryptoAmount.toStringAsFixed(_selectedCoin == 'SOL' ? 6 : 2)} $_selectedCoin) has been transferred directly to your Solana wallet on-chain!'
            : 'Withdrawal of ₱ ${amount.toStringAsFixed(2)} to your Solana wallet requested successfully! Processing typically completes within 1 hour.';
      });
      s.showAppToast(
        isOnChainTransferred ? 'Withdrawal Completed' : 'Withdrawal Requested',
        '₱ ${amount.toStringAsFixed(2)} via $methodTitle ${isOnChainTransferred ? "sent on-chain!" : "submitted."}',
      );
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Withdrawal request failed: $e';
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final tyxBal = s.userProfile?.tyxBalance ?? 0.0;
    final walletKey = s.walletAddress.isNotEmpty ? s.walletAddress : (s.userProfile?.walletPublicKey ?? '');
    final hasWallet = walletKey.isNotEmpty;
    final cardBg = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    final inputBg = isDark ? 'bg-zinc-800 border-zinc-700 text-white' : 'bg-white border-zinc-300 text-zinc-900';

    final enteredAmount = double.tryParse(_amountInput.trim()) ?? 0.0;
    final feePhp = enteredAmount * 0.02;
    final netPhp = (enteredAmount - feePhp).clamp(0.0, double.infinity);
    final activeRate = _selectedCoin == 'SOL' ? (_solToPhpRate > 0 ? _solToPhpRate : 8000.0) : (_usdToPhpRate > 0 ? _usdToPhpRate : 57.0);
    final estCryptoAmount = activeRate > 0 ? netPhp / activeRate : 0.0;
    final estCryptoStr = _selectedCoin == 'SOL'
        ? '${estCryptoAmount.toStringAsFixed(6)} SOL'
        : '${estCryptoAmount.toStringAsFixed(2)} USDT';

    return div(classes: 'space-y-6', [
      subViewHeader(
        title: 'Withdraw Funds (Solana)',
        isDark: isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),

      // Security / Linked Wallet Requirement Banner
      if (!hasWallet)
        div(
          classes:
              'p-4 rounded-2xl bg-amber-500/10 border border-amber-500/20 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs text-amber-400',
          [
            div(classes: 'flex items-start gap-2.5', [
              lIcon('shield-alert', cls: 'w-5 h-5 shrink-0 text-amber-400 mt-0.5'),
              div([
                p(classes: 'font-bold text-sm text-amber-300', [Component.text('Solana Wallet Required')]),
                p(classes: 'mt-0.5 text-zinc-400', [
                  Component.text(
                    'Withdrawals are only available to verified Solana wallets. Please link your Solana wallet in Payment Methods or Trust & Verification.',
                  ),
                ]),
              ]),
            ]),
            button(
              classes:
                  'px-3.5 py-2 rounded-xl font-bold bg-amber-500/20 text-amber-300 hover:bg-amber-500/30 transition-all text-xs cursor-pointer border-0 shrink-0',
              events: {'click': (_) => s.setState(() => s.profileView = ProfileView.payment)},
              [Component.text('Link Wallet in Payments')],
            ),
          ],
        )
      else
        div(
          classes:
              'p-3.5 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-between text-xs',
          [
            div(classes: 'flex items-center gap-2.5', [
              lIcon('shield-check', cls: 'w-4 h-4 text-emerald-400'),
              span(classes: 'font-semibold text-zinc-300', [Component.text('Connected Solana Wallet:')]),
              span(classes: 'font-mono text-emerald-400 font-bold', [
                Component.text('${walletKey.substring(0, 6)}...${walletKey.substring(walletKey.length - 6)}'),
              ]),
            ]),
            span(classes: 'text-[10px] px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-400 font-bold', [
              Component.text('Verified'),
            ]),
          ],
        ),

      // Withdrawable Balance Banner
      div(
        classes:
            'p-8 rounded-[2.5rem] logo-gradient text-white relative overflow-hidden shadow-2xl shadow-indigo-500/20',
        [
          div(classes: 'relative z-10 space-y-4', [
            div(classes: 'flex justify-between items-start', [
              div([
                p(classes: 'text-[10px] font-black uppercase tracking-[0.2em] opacity-70 mb-1', [
                  Component.text('Withdrawable Balance'),
                ]),
                p(classes: 'text-sm font-medium opacity-90', [Component.text(s.userName)]),
              ]),
              div(
                classes:
                    'w-12 h-12 rounded-2xl bg-white/10 backdrop-blur-md flex items-center justify-center border border-white/20',
                [lIcon('arrow-up-right', cls: 'w-6 h-6 text-white')],
              ),
            ]),
            div([
              p(classes: 'text-4xl font-black flex items-center gap-3', [
                span(classes: 'text-2xl opacity-60', [Component.text('₱')]),
                Component.text(tyxBal.toStringAsFixed(2)),
              ]),
              p(classes: 'text-xs opacity-75 mt-1 font-mono tracking-wide', [
                Component.text('Equivalent to ${tyxBal.toStringAsFixed(0)} Tyxbits (1 Tyx = ₱1.00)'),
              ]),
            ]),
          ]),
        ],
      ),

      // Step 1: Amount Selection Card
      div(classes: 'p-6 rounded-[2rem] border $cardBg space-y-4', [
        p(classes: 'text-xs font-bold uppercase tracking-wider text-indigo-400', [
          Component.text('1. Enter Withdrawal Amount'),
        ]),
        div(classes: 'relative', [
          span(classes: 'absolute left-4 top-1/2 -translate-y-1/2 text-2xl font-black text-indigo-400', [
            Component.text('₱'),
          ]),
          input(
            classes:
                'w-full pl-12 pr-4 py-4 rounded-2xl border $inputBg text-2xl font-black outline-none focus:border-indigo-500 transition-colors',
            attributes: {
              'type': 'number',
              'step': '1',
              'min': '100',
              'value': _amountInput,
              'placeholder': '100',
            },
            events: {
              'input': (e) {
                setState(() {
                  _amountInput = getInputValue(e.target);
                  _errorMessage = null;
                });
              },
            },
          ),
        ]),
        // Quick Presets
        div(classes: 'flex flex-wrap gap-2 pt-2', [
          for (final preset in [100.0, 500.0, 1000.0, 5000.0])
            button(
              classes:
                  'px-3.5 py-2 rounded-xl text-xs font-bold border transition-all cursor-pointer ${isDark ? "bg-zinc-800 border-zinc-700 text-zinc-300 hover:bg-zinc-700" : "bg-zinc-100 border-zinc-200 text-zinc-700 hover:bg-zinc-200"}',
              events: {'click': (_) => _setPresetAmount(preset, tyxBal)},
              [Component.text('₱${preset.toStringAsFixed(0)}')],
            ),
          button(
            classes:
                'px-4 py-2 rounded-xl text-xs font-bold bg-indigo-600/20 border border-indigo-500/40 text-indigo-400 hover:bg-indigo-600/30 transition-all cursor-pointer',
            events: {'click': (_) => _setPresetAmount(tyxBal, tyxBal)},
            [Component.text('MAX BALANCE')],
          ),
        ]),
      ]),

      // Step 2: Solana Destination Card
      div(classes: 'p-6 rounded-[2rem] border $cardBg space-y-4', [
        div(classes: 'flex items-center justify-between', [
          p(classes: 'text-xs font-bold uppercase tracking-wider text-indigo-400', [
            Component.text('2. Solana Payout Destination'),
          ]),
          span(
            classes:
                'text-[11px] font-bold px-2.5 py-1 rounded-lg ${isDark ? "bg-purple-500/10 text-purple-400" : "bg-purple-50 text-purple-700"} flex items-center gap-1.5',
            [
              lIcon('wallet', cls: 'w-3.5 h-3.5'),
              Component.text('Solana Network Only'),
            ],
          ),
        ]),

        div(classes: 'p-4 rounded-2xl bg-indigo-500/5 border border-indigo-500/10 space-y-3', [
          div(classes: 'flex items-center justify-between', [
            span(classes: 'text-xs font-semibold text-zinc-400', [Component.text('Destination Solana Address')]),
            span(
              classes:
                  'text-[10px] px-2 py-0.5 rounded-full font-bold ${hasWallet ? "bg-emerald-500/10 text-emerald-400" : "bg-amber-500/10 text-amber-400"}',
              [Component.text(hasWallet ? 'Linked' : 'No Wallet Linked')],
            ),
          ]),
          if (hasWallet) ...[
            p(classes: 'font-mono text-xs font-bold text-indigo-400 break-all', [Component.text(walletKey)]),
            div(classes: 'pt-2 space-y-2', [
              div(classes: 'flex items-center justify-between', [
                span(classes: 'text-xs font-semibold text-zinc-400 block', [Component.text('Select Payout Token:')]),
                span(classes: 'text-[11px] text-zinc-400 font-mono', [
                  Component.text(_isFetchingRates ? 'Fetching live rates...' : 'Live Web Rates'),
                ]),
              ]),
              div(classes: 'grid grid-cols-1 sm:grid-cols-2 gap-2.5', [
                button(
                  classes:
                      'p-3 rounded-2xl text-left border transition-all cursor-pointer ${_selectedCoin == 'USDT' ? "bg-indigo-600/15 border-indigo-500 text-white shadow-md shadow-indigo-600/20" : (isDark ? "bg-zinc-800/80 border-zinc-700 text-zinc-400 hover:text-white" : "bg-zinc-100 border-zinc-200 text-zinc-700 hover:bg-zinc-200")}',
                  events: {'click': (_) => setState(() => _selectedCoin = 'USDT')},
                  [
                    div(classes: 'flex justify-between items-center', [
                      span(classes: 'text-xs font-bold text-white', [Component.text('Tether (USDT SPL)')]),
                      if (_selectedCoin == 'USDT') lIcon('check-circle', cls: 'w-4 h-4 text-indigo-400'),
                    ]),
                    p(classes: 'text-[11px] text-zinc-400 mt-1', [
                      Component.text('1 USDT ≈ ₱${_usdToPhpRate.toStringAsFixed(2)}'),
                    ]),
                  ],
                ),
                button(
                  classes:
                      'p-3 rounded-2xl text-left border transition-all cursor-pointer ${_selectedCoin == 'SOL' ? "bg-indigo-600/15 border-indigo-500 text-white shadow-md shadow-indigo-600/20" : (isDark ? "bg-zinc-800/80 border-zinc-700 text-zinc-400 hover:text-white" : "bg-zinc-100 border-zinc-200 text-zinc-700 hover:bg-zinc-200")}',
                  events: {'click': (_) => setState(() => _selectedCoin = 'SOL')},
                  [
                    div(classes: 'flex justify-between items-center', [
                      span(classes: 'text-xs font-bold text-white', [Component.text('Solana (SOL Native)')]),
                      if (_selectedCoin == 'SOL') lIcon('check-circle', cls: 'w-4 h-4 text-indigo-400'),
                    ]),
                    p(classes: 'text-[11px] text-zinc-400 mt-1', [
                      Component.text('1 SOL ≈ ₱${_solToPhpRate.toStringAsFixed(2)}'),
                    ]),
                  ],
                ),
              ]),
            ]),
          ] else ...[
            p(classes: 'text-xs text-zinc-400', [
              Component.text('Link your Phantom, Solflare, or Trust wallet in Payment Methods to receive instant Solana payouts.'),
            ]),
          ],
        ]),
      ]),

      // Fee & ETA Summary
      div(classes: 'p-4 rounded-2xl border ${isDark ? "bg-zinc-900/40 border-zinc-800 text-zinc-400" : "bg-zinc-50 border-zinc-200 text-zinc-600"} text-xs space-y-2', [
        div(classes: 'flex justify-between items-center', [
          span([Component.text('Live Rate (from web)')]),
          span(classes: 'font-mono font-bold text-indigo-400', [
            Component.text('1 $_selectedCoin ≈ ₱${activeRate.toStringAsFixed(2)}'),
          ]),
        ]),
        div(classes: 'flex justify-between items-center', [
          span([Component.text('Platform Fee (2%)')]),
          span(classes: 'font-semibold text-rose-400', [
            Component.text('₱ ${feePhp.toStringAsFixed(2)}'),
          ]),
        ]),
        div(classes: 'flex justify-between items-center', [
          span([Component.text('Estimated Net Payout')]),
          span(classes: 'font-bold text-emerald-400 font-mono', [
            Component.text('₱ ${netPhp.toStringAsFixed(2)} ($estCryptoStr)'),
          ]),
        ]),
        div(classes: 'flex justify-between items-center', [
          span([Component.text('Network Fee')]),
          span(classes: 'font-bold text-emerald-400', [Component.text('Covered by Tranyx (0%)')]),
        ]),
        div(classes: 'flex justify-between items-center', [
          span([Component.text('Estimated Settlement')]),
          span(classes: 'font-semibold', [Component.text('Instant to 1 Hour')]),
        ]),
        div(classes: 'flex justify-between items-center', [
          span([Component.text('Minimum Amount')]),
          span(classes: 'font-semibold', [Component.text('₱ 100.00')]),
        ]),
      ]),

      if (_errorMessage != null)
        div(classes: 'p-3.5 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-xs flex items-center gap-2', [
          lIcon('alert-triangle', cls: 'w-4 h-4 shrink-0'),
          span([Component.text(_errorMessage!)]),
        ]),

      if (_successMessage != null)
        div(classes: 'p-3.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs flex items-center gap-2', [
          lIcon('check-circle', cls: 'w-4 h-4 shrink-0'),
          span(classes: 'font-bold', [Component.text(_successMessage!)]),
        ]),

      // Action Button
      button(
        classes:
          'w-full py-4 rounded-2xl font-bold text-white bg-indigo-600 hover:bg-indigo-500 transition-all flex items-center justify-center gap-2 shadow-lg shadow-indigo-600/20 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed',
        attributes: _isSubmitting ? {'disabled': 'disabled'} : {},
        events: {
          'click': (_) async {
            if (!_isSubmitting) {
              await _submitWithdrawal();
            }
          },
        },
        [
          if (_isSubmitting) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
          lIcon('arrow-up-right', cls: 'w-5 h-5'),
          Component.text(_isSubmitting ? 'Submitting Request...' : 'Confirm & Request Withdrawal'),
        ],
      ),
    ]);
  }
}

// ── Trust & Verification ──────────────────────────────────────
class _TrustVerification extends StatelessComponent {
  final TranyxAppState state;
  const _TrustVerification({required this.state});

  Component verificationCard({
    required String title,
    required String desc,
    required bool isVerified,
    required bool isDark,
    required void Function() onVerify,
    required bool isSaving,
  }) {
    return div(
      classes:
          'p-5 rounded-2xl border ${isDark ? "bg-zinc-900/40 border-zinc-800/80" : "bg-white border-zinc-200/60 shadow-sm"} flex items-center justify-between gap-4',
      [
        div(classes: 'flex items-center gap-3', [
          div(
            classes:
                'w-10 h-10 rounded-xl flex items-center justify-center '
                '${isVerified ? "bg-green-500/10 text-green-400" : "bg-zinc-500/10 text-zinc-400"}',
            [lIcon(isVerified ? 'check-circle' : 'circle', cls: 'w-5 h-5')],
          ),
          div([
            p(classes: 'font-bold text-sm ${isDark ? "text-white" : "text-zinc-800"}', [Component.text(title)]),
            p(classes: 'text-[11px] ${isDark ? "text-zinc-500" : "text-zinc-550"}', [Component.text(desc)]),
            if (title == 'Email Address' && state.verificationEmailSent && !isVerified)
              p(classes: 'text-[10px] text-indigo-400 font-semibold mt-1 flex items-center gap-1 animate-pulse', [
                lIcon('mail', cls: 'w-3 h-3'),
                Component.text('Verification link sent! Check your inbox/spam.'),
              ]),
          ]),
        ]),
        if (isVerified)
          span(
            classes:
                'px-3 py-1 rounded-full text-xs font-bold bg-green-500/10 text-green-400 border border-green-500/20',
            [
              Component.text('Verified'),
            ],
          )
        else if (title == 'Email Address' && state.verificationEmailSent)
          div(classes: 'flex gap-2 items-center', [
            button(
              classes:
                  'px-3 py-1.5 rounded-xl text-[11px] font-bold border transition-colors '
                  '${isDark ? "border-zinc-800 hover:bg-zinc-800 text-zinc-400" : "border-zinc-200 hover:bg-zinc-100 text-zinc-650"}',
              events: isSaving ? {} : {'click': (_) => onVerify()},
              [Component.text('Resend')],
            ),
            button(
              classes:
                  'px-3 py-1.5 rounded-xl text-[11px] font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center gap-1',
              events: isSaving ? {} : {'click': (_) => onVerify()},
              [
                if (isSaving) lIcon('loader-2', cls: 'w-3 h-3 animate-spin'),
                Component.text(isSaving ? 'Verifying...' : "I've Verified"),
              ],
            ),
          ])
        else
          button(
            classes:
                'px-4 py-2 rounded-xl text-xs font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center gap-1.5 min-w-[100px] justify-center',
            events: isSaving ? {} : {'click': (_) => onVerify()},
            [
              if (isSaving) lIcon('loader-2', cls: 'w-3.5 h-3.5 animate-spin'),
              Component.text(isSaving ? 'Verifying...' : 'Verify Now'),
            ],
          ),
      ],
    );
  }

  Component kycVerificationCard({
    required String title,
    required String desc,
    required bool isVerified,
    required String status,
    required String? rejectionReason,
    required bool isDark,
    required void Function() onVerify,
    required bool isSaving,
  }) {
    final displayStatus = isVerified ? 'approved' : status;

    return div(
      classes:
          'p-5 rounded-2xl border ${isDark ? "bg-zinc-900/40 border-zinc-800/80" : "bg-white border-zinc-200/60 shadow-sm"} flex flex-col gap-3',
      [
        div(classes: 'flex items-center justify-between gap-4 w-full', [
          div(classes: 'flex items-center gap-3', [
            div(
              classes:
                  'w-10 h-10 rounded-xl flex items-center justify-center '
                  '${displayStatus == "approved"
                      ? "bg-green-500/10 text-green-400"
                      : displayStatus == "pending"
                      ? "bg-amber-500/10 text-amber-400"
                      : displayStatus == "rejected"
                      ? "bg-red-500/10 text-red-400"
                      : "bg-zinc-500/10 text-zinc-400"}',
              [
                lIcon(
                  displayStatus == "approved"
                      ? 'check-circle'
                      : displayStatus == "pending"
                      ? 'clock'
                      : displayStatus == "rejected"
                      ? 'alert-circle'
                      : 'circle',
                  cls: 'w-5 h-5',
                ),
              ],
            ),
            div([
              p(classes: 'font-bold text-sm ${isDark ? "text-white" : "text-zinc-800"}', [Component.text(title)]),
              p(classes: 'text-[11px] ${isDark ? "text-zinc-500" : "text-zinc-550"}', [Component.text(desc)]),
            ]),
          ]),
          if (displayStatus == 'approved')
            span(
              classes:
                  'px-3 py-1 rounded-full text-xs font-bold bg-green-500/10 text-green-400 border border-green-500/20',
              [Component.text('Verified')],
            )
          else if (displayStatus == 'pending')
            span(
              classes:
                  'px-3 py-1 rounded-full text-xs font-bold bg-amber-500/10 text-amber-400 border border-amber-500/20 animate-pulse',
              [Component.text('Pending Review')],
            )
          else if (displayStatus == 'rejected')
            button(
              classes:
                  'px-4 py-2 rounded-xl text-xs font-bold text-white bg-red-650 hover:bg-red-700 transition-colors flex items-center gap-1.5 min-w-[100px] justify-center border-0 cursor-pointer',
              events: isSaving ? {} : {'click': (_) => onVerify()},
              [Component.text('Try Again')],
            )
          else
            button(
              classes:
                  'px-4 py-2 rounded-xl text-xs font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center gap-1.5 min-w-[100px] justify-center border-0 cursor-pointer',
              events: isSaving ? {} : {'click': (_) => onVerify()},
              [Component.text('Verify Now')],
            ),
        ]),
        if (displayStatus == 'rejected' && rejectionReason != null && rejectionReason.isNotEmpty)
          div(
            classes:
                'mt-1 p-3 rounded-xl bg-red-500/5 border border-red-500/10 text-[10.5px] text-red-400 font-medium flex items-start gap-1.5',
            [
              lIcon('alert-triangle', cls: 'w-3.5 h-3.5 mt-0.5 shrink-0'),
              div([
                p(classes: 'font-bold text-[11px]', [Component.text('Rejection Reason:')]),
                p(classes: 'mt-0.5 opacity-90', [Component.text(rejectionReason)]),
              ]),
            ],
          ),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;

    final isEmail = s.userProfile?.emailVerified ?? false;
    final isPhone = s.userProfile?.phoneVerified ?? false;
    final isId = s.userProfile?.idVerified ?? false;
    final isBg = s.userProfile?.bgChecked ?? false;
    final level = s.userProfile?.verificationLevel ?? 0;

    return div(classes: 'space-y-6', [
      subViewHeader(
        title: 'Trust & Verification',
        isDark: isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),
      div(
        classes:
            'p-6 rounded-3xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200 shadow-md"} text-center relative overflow-hidden',
        [
          div([], classes: 'absolute inset-0 bg-gradient-to-br from-indigo-500/5 to-purple-500/5 pointer-events-none'),
          div(classes: 'relative z-10 space-y-3', [
            div(
              classes:
                  'w-16 h-16 rounded-full flex items-center justify-center mx-auto '
                  '${level == 2
                      ? "bg-green-500/10 text-green-400 border border-green-500/20"
                      : level == 1
                      ? "bg-blue-500/10 text-blue-400 border border-blue-500/20"
                      : "bg-zinc-500/10 text-zinc-500 border border-zinc-500/20"}',
              [lIcon(level > 0 ? 'shield-check' : 'shield-alert', cls: 'w-8 h-8')],
            ),
            h4(classes: 'text-xl font-black tracking-tight', [
              Component.text(
                level == 2
                    ? 'Fully Verified (Level 2)'
                    : level == 1
                    ? 'Basic Verified (Level 1)'
                    : 'Unverified (Level 0)',
              ),
            ]),
            p(classes: 'text-xs max-w-sm mx-auto ${isDark ? "text-zinc-400" : "text-zinc-500"} leading-relaxed', [
              Component.text(
                level == 2
                    ? 'Amazing! You have completed all verification levels. You get maximum trust badge visibility!'
                    : level == 1
                    ? 'You have verified email & phone number. Complete ID & Background checks to become Fully Verified.'
                    : 'Get started by verifying your profile details to gain trust from the community.',
              ),
            ]),
            // Progress Bar
            div(classes: 'w-full bg-zinc-700/20 rounded-full h-2 mt-4', [
              div(
                [],
                classes: 'h-2 rounded-full logo-gradient transition-all duration-500',
                attributes: {
                  'style':
                      'width: ${level == 2
                          ? "100"
                          : level == 1
                          ? "50"
                          : "15"}%',
                },
              ),
            ]),
          ]),
        ],
      ),
      div(classes: 'space-y-3', [
        verificationCard(
          title: 'Email Address',
          desc: 'Verify ownership of your registered email address',
          isVerified: isEmail,
          isDark: isDark,
          isSaving: s.isUpdatingVerification && !isEmail,
          onVerify: () => s.updateVerificationField(email: true),
        ),
        verificationCard(
          title: 'Phone Number',
          desc: 'Add and verify a Philippine mobile number (+63)',
          isVerified: isPhone,
          isDark: isDark,
          isSaving: s.isUpdatingVerification && !isPhone,
          onVerify: () => s.updateVerificationField(phone: true),
        ),
        kycVerificationCard(
          title: 'Government ID',
          desc: 'Submit your Driver License, Passport or National ID',
          isVerified: isId,
          status: s.activeKycSubmission?['idVerification']?['status']?.toString() ?? 'not_submitted',
          rejectionReason: s.activeKycSubmission?['idVerification']?['rejectionReason']?.toString(),
          isDark: isDark,
          isSaving: s.isLoadingKyc,
          onVerify: () => s.setState(() => s.showKycIdModal = true),
        ),
        kycVerificationCard(
          title: 'Background Check',
          desc: 'Undergo criminal history background clearance',
          isVerified: isBg,
          status: s.activeKycSubmission?['backgroundCheck']?['status']?.toString() ?? 'not_submitted',
          rejectionReason: s.activeKycSubmission?['backgroundCheck']?['rejectionReason']?.toString(),
          isDark: isDark,
          isSaving: s.isLoadingKyc,
          onVerify: () => s.setState(() => s.showKycBgModal = true),
        ),
      ]),

      // ── Linked Accounts Section ──────────────────────────────────
      div(
        classes:
            'p-5 rounded-2xl border space-y-4 ${isDark ? "bg-zinc-900/40 border-zinc-800/80" : "bg-white border-zinc-200/60 shadow-sm"}',
        [
          div(classes: 'flex items-center gap-2 mb-2', [
            div(
              classes: 'p-2 rounded-xl bg-indigo-500/10',
              [lIcon('link', cls: 'w-5 h-5 text-indigo-455')],
            ),
            div([
              p(classes: 'font-bold text-sm ${isDark ? "text-white" : "text-zinc-800"}', [
                Component.text('Linked Accounts'),
              ]),
              p(classes: 'text-[11px] ${isDark ? "text-zinc-500" : "text-zinc-550"}', [
                Component.text('Manage connected wallets and third-party login providers'),
              ]),
            ]),
          ]),

          // Google Account Link
          div(
            classes:
                'flex items-center justify-between p-3 rounded-xl ${isDark ? "bg-zinc-800/40 border border-zinc-800" : "bg-zinc-50 border border-zinc-200"}',
            [
              div(classes: 'flex items-center gap-3', [
                lIcon('mail', cls: 'w-5 h-5 text-red-400'),
                div([
                  p(classes: 'text-xs font-bold ${isDark ? "text-white" : "text-zinc-800"}', [
                    Component.text('Google Account'),
                  ]),
                  p(classes: 'text-[10px] ${isDark ? "text-zinc-500" : "text-zinc-550"}', [
                    Component.text(
                      (s.userProfile?.googleEmail ?? '').isNotEmpty
                          ? 'Linked to: ${s.userProfile!.googleEmail}'
                          : 'Not linked',
                    ),
                  ]),
                ]),
              ]),
              if ((s.userProfile?.googleEmail ?? '').isNotEmpty)
                button(
                  classes:
                      'px-3 py-1 text-xs font-bold rounded-lg bg-red-500/10 text-red-400 hover:bg-red-500/20 transition-all border border-red-500/20',
                  events: {'click': (_) => s.handleUnlinkGoogleAccount()},
                  [Component.text('Unlink')],
                )
              else
                button(
                  classes:
                      'px-3 py-1 text-xs font-bold rounded-lg bg-indigo-650 text-white hover:bg-indigo-700 transition-all shadow-sm',
                  events: {'click': (_) => s.handleLinkGoogleAccount()},
                  [Component.text('Link Google')],
                ),
            ],
          ),

          // Solana Wallet Link
          div(
            classes:
                'flex items-center justify-between p-3 rounded-xl ${isDark ? "bg-zinc-800/40 border border-zinc-800" : "bg-zinc-50 border border-zinc-200"}',
            [
              div(classes: 'flex items-center gap-3', [
                lIcon('wallet', cls: 'w-5 h-5 text-purple-400'),
                div([
                  div(classes: 'flex items-center gap-2', [
                    p(classes: 'text-xs font-bold ${isDark ? "text-white" : "text-zinc-800"}', [
                      Component.text('Solana Wallet'),
                    ]),
                    span(
                      classes:
                          'px-1.5 py-0.5 rounded text-[8px] font-black uppercase tracking-wider ${(s.userProfile?.walletPublicKey ?? '').isNotEmpty ? "bg-green-500/10 text-green-400 border border-green-500/20" : "bg-yellow-500/10 text-yellow-500 border border-yellow-500/20"}',
                      [
                        Component.text(
                          (s.userProfile?.walletPublicKey ?? '').isNotEmpty
                              ? '🪙 +200 TP Claimed'
                              : '🪙 +200 TP Reward',
                        ),
                      ],
                    ),
                  ]),
                  p(classes: 'text-[10px] ${isDark ? "text-zinc-500" : "text-zinc-550"}', [
                    Component.text(
                      (s.userProfile?.walletPublicKey ?? '').isNotEmpty
                          ? 'Linked: ${s.userProfile!.walletPublicKey!.substring(0, 6)}...${s.userProfile!.walletPublicKey!.substring(s.userProfile!.walletPublicKey!.length - 6)}'
                          : 'Link your wallet to secure payments and claim your reward',
                    ),
                  ]),
                ]),
              ]),
              if ((s.userProfile?.walletPublicKey ?? '').isNotEmpty)
                button(
                  classes:
                      'px-3 py-1 text-xs font-bold rounded-lg bg-red-500/10 text-red-400 hover:bg-red-500/20 transition-all border border-red-500/20',
                  events: {'click': (_) => s.unlinkSolanaWallet()},
                  [Component.text('Unlink')],
                )
              else
                div(classes: 'flex flex-wrap items-center gap-1.5', [
                  button(
                    classes:
                        'px-2.5 py-1 text-[10px] font-bold rounded-lg bg-zinc-700 hover:bg-zinc-600 text-white transition-all shadow-sm',
                    events: {'click': (_) => s.linkSolanaWallet('phantom')},
                    [Component.text('Phantom')],
                  ),
                  button(
                    classes:
                        'px-2.5 py-1 text-[10px] font-bold rounded-lg bg-zinc-700 hover:bg-zinc-600 text-white transition-all shadow-sm',
                    events: {'click': (_) => s.linkSolanaWallet('solflare')},
                    [Component.text('Solflare')],
                  ),
                  button(
                    classes:
                        'px-2.5 py-1 text-[10px] font-bold rounded-lg bg-zinc-700 hover:bg-zinc-600 text-white transition-all shadow-sm',
                    events: {'click': (_) => s.linkSolanaWallet('backpack')},
                    [Component.text('Backpack')],
                  ),
                  button(
                    classes:
                        'px-2.5 py-1 text-[10px] font-bold rounded-lg bg-zinc-700 hover:bg-zinc-600 text-white transition-all shadow-sm',
                    events: {'click': (_) => s.linkSolanaWallet('trust')},
                    [Component.text('Trust')],
                  ),
                ]),
            ],
          ),
        ],
      ),

      // ── Skill Certifications ───────────────────────────────────────
      if (s.accountType == AccountType.nyxian || s.accountType == AccountType.hybrid)
        div(
          classes:
              'p-5 rounded-2xl border space-y-4 ${isDark ? "bg-zinc-900/40 border-zinc-800/80" : "bg-white border-zinc-200/60 shadow-sm"}',
          [
            div(classes: 'flex items-center justify-between', [
              div(classes: 'flex items-center gap-2', [
                div(
                  classes: 'p-2 rounded-xl bg-yellow-500/10',
                  [lIcon('award', cls: 'w-5 h-5 text-yellow-400')],
                ),
                div([
                  p(classes: 'font-bold text-sm ${isDark ? "text-white" : "text-zinc-800"}', [
                    Component.text('Skill Certifications'),
                  ]),
                  p(classes: 'text-[11px] ${isDark ? "text-zinc-500" : "text-zinc-550"}', [
                    Component.text('Upload TESDA, PRC, or trade certificates to earn a Skill Certified badge'),
                  ]),
                ]),
              ]),
              if ((s.userProfile?.certificationUrls ?? []).isNotEmpty)
                span(
                  classes:
                      'px-3 py-1 rounded-full text-xs font-bold bg-yellow-500/10 text-yellow-400 border border-yellow-500/20',
                  [Component.text('Skill Certified')],
                ),
            ]),

            // Uploaded certificates
            if ((s.userProfile?.certificationUrls ?? []).isNotEmpty)
              div(classes: 'flex flex-wrap gap-2', [
                for (final url in s.userProfile!.certificationUrls!)
                  div(
                    classes:
                        'flex items-center gap-2 px-3 py-2 rounded-xl text-xs font-medium '
                        '${isDark ? "bg-zinc-800 border border-zinc-700 text-zinc-300" : "bg-zinc-50 border border-zinc-200 text-zinc-700"}',
                    [
                      lIcon('file-check', cls: 'w-3.5 h-3.5 text-green-400'),
                      Component.text(
                        url.split('/').last.split('?').first.length > 30
                            ? '${url.split('/').last.split('?').first.substring(0, 28)}...'
                            : url.split('/').last.split('?').first,
                      ),
                    ],
                  ),
              ]),

            // Upload button
            if ((s.userProfile?.certificationUrls ?? []).length < 3)
              div(classes: 'relative', [
                button(
                  classes:
                      'w-full py-3 rounded-xl border border-dashed text-sm font-semibold transition-colors flex items-center justify-center gap-2 '
                      '${isDark ? "border-zinc-700 text-zinc-400 hover:border-yellow-500/50 hover:text-yellow-400" : "border-zinc-300 text-zinc-500 hover:border-yellow-500 hover:text-yellow-600"}',
                  events: {},
                  [
                    if (s.isUploadingCertificate)
                      lIcon('loader-2', cls: 'w-4 h-4 animate-spin')
                    else
                      lIcon('upload', cls: 'w-4 h-4'),
                    Component.text(s.isUploadingCertificate ? 'Uploading...' : 'Upload Certificate (PDF or Image)'),
                  ],
                ),
                input(
                  type: InputType.file,
                  classes: 'absolute inset-0 opacity-0 cursor-pointer',
                  attributes: {
                    'accept': 'image/*,application/pdf',
                    'id': 'cert-upload-input',
                    'name': 'certification_file',
                  },
                  events: {
                    'change': (e) => s.uploadCertification(e),
                  },
                ),
              ]),

            p(classes: 'text-[10px] ${isDark ? "text-zinc-600" : "text-zinc-400"}', [
              Component.text(
                'Max 3 files • Supported: JPG, PNG, PDF • Admin review may be required for some certifications',
              ),
            ]),
          ],
        ),
    ]);
  }
}

class _HelpSupport extends StatefulComponent {
  final TranyxAppState state;
  const _HelpSupport({required this.state});

  @override
  State<_HelpSupport> createState() => _HelpSupportState();
}

class _HelpSupportState extends State<_HelpSupport> {
  int expandedFaqIndex = -1;
  bool showChat = false;
  bool showTicketForm = false;
  bool isSubmitting = false;
  String? submitSuccessMessage;
  String? submitErrorMessage;

  // Ticket Form Controllers/State
  String ticketSubject = '';
  String ticketDescription = '';
  String ticketCategory = 'General';

  // Chat State
  final List<Map<String, dynamic>> chatMessages = [
    {
      'isUser': false,
      'text': 'Hi! I am Nyx, your Tranyx AI support agent. How can I help you today?',
      'time': 'Just now',
    },
  ];
  String currentChatInput = '';
  bool isAiTyping = false;
  double? supportTokens;

  // Agent Chat State
  bool showAgentChat = false;
  List<Map<String, dynamic>> agentChatMessages = [];
  bool isLoadingAgentChat = false;
  String currentAgentChatInput = '';
  Timer? agentChatTimer;

  void startAgentChatPolling() {
    agentChatTimer?.cancel();
    agentChatTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted || !showAgentChat) {
        timer.cancel();
        return;
      }
      loadAgentChatMessages(silent: true);
    });
  }

  void stopAgentChatPolling() {
    agentChatTimer?.cancel();
    agentChatTimer = null;
  }

  Future<void> loadAgentChatMessages({bool silent = false}) async {
    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    if (token == null || uid == null) return;

    if (!silent) {
      setState(() => isLoadingAgentChat = true);
    }

    try {
      final firestore = FirestoreService(token, component.state.handleTokenRefresh);
      final msgs = await firestore.getAgentSupportChatMessages(uid);
      if (mounted) {
        setState(() {
          agentChatMessages = msgs.map((m) {
            return {
              'isUser': m['senderId'] == uid,
              'text': m['content'] ?? '',
              'senderName': m['senderName'] ?? 'Support',
              'time': m['createdAt'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int).toLocal().toString().substring(11, 16)
                  : 'Just now',
            };
          }).toList();
          if (agentChatMessages.isEmpty) {
            agentChatMessages.add({
              'isUser': false,
              'text': 'Connecting you to a support agent... How can we help you today?',
              'senderName': 'System',
              'time': 'Just now',
            });
          }
          if (!silent) {
            isLoadingAgentChat = false;
          }
        });
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() => isLoadingAgentChat = false);
      }
    }
  }

  Future<void> sendAgentChatMessage() async {
    final text = currentAgentChatInput.trim();
    if (text.isEmpty) return;

    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    final name = component.state.userName.isNotEmpty ? component.state.userName : 'User';
    if (token == null || uid == null) return;

    final messageId = 'MSG_${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      agentChatMessages.add({
        'isUser': true,
        'text': text,
        'senderName': name,
        'time': 'Just now',
      });
      currentAgentChatInput = '';
    });

    try {
      final firestore = FirestoreService(token, component.state.handleTokenRefresh);
      await firestore.sendAgentSupportChatMessage(
        uid: uid,
        messageId: messageId,
        senderId: uid,
        senderName: name,
        content: text,
      );
      loadAgentChatMessages(silent: true);
    } catch (e) {
      setState(() {
        agentChatMessages.add({
          'isUser': false,
          'text': 'Failed to send message: $e',
          'senderName': 'System',
          'time': 'Just now',
        });
      });
    }
  }

  @override
  void dispose() {
    stopAgentChatPolling();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    loadSupportTokens();
  }

  Future<void> loadSupportTokens() async {
    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    if (token != null && uid != null) {
      try {
        final firestore = FirestoreService(token, component.state.handleTokenRefresh);
        final userDoc = await firestore.getDocument('users/$uid');
        if (userDoc != null && userDoc.containsKey('supportTokensAvailable')) {
          final double savedTokens = (userDoc['supportTokensAvailable'] as num).toDouble();
          final int savedTime = (userDoc['supportLastRequestedTimestamp'] as num).toInt();
          final now = DateTime.now().millisecondsSinceEpoch;
          final elapsedMs = now - savedTime;
          final recovered = elapsedMs / 3600000.0;
          setState(() {
            supportTokens = (savedTokens + recovered).clamp(0.0, 5.0);
          });
          return;
        }
      } catch (_) {}
    }
    setState(() {
      supportTokens = 5.0;
    });
  }

  List<Map<String, String>> get faqData {
    final type = component.state.accountType;
    final items = TranyxFaqData.getFaqsForAccountType(type);
    return items
        .map((f) => {
              'title': f.title,
              'icon': f.icon,
              'category': f.category,
              'answer': f.answer,
            })
        .toList();
  }

  void toggleFaq(int index) {
    setState(() {
      expandedFaqIndex = (expandedFaqIndex == index) ? -1 : index;
    });
  }

  Future<void> sendChatMessage() async {
    final text = currentChatInput.trim();
    if (text.isEmpty) return;

    setState(() {
      chatMessages.add({
        'isUser': true,
        'text': text,
        'time': 'Just now',
      });
      currentChatInput = '';
      isAiTyping = true;
    });

    // Check for satisfaction / termination keywords
    final cleanText = text.toLowerCase().trim();
    final terminationKeywords = [
      'thank you',
      'thanks',
      'thank u',
      'no more questions',
      'no more question',
      'no questions',
      "i'm good",
      'im good',
      'satisfied',
      'all good',
      'that is all',
      'thats all',
      "that's all",
      'nothing else',
      'no need',
      'salamat',
      'maraming salamat',
      'wala na',
      'ok na',
      'okay na',
      'ayos na',
      'sapat na',
      'walang anuman',
      'damo nga salamat',
      'waray na',
      'igo na',
      'tolda na',
    ];
    final isTerminating = terminationKeywords.any((k) => cleanText.contains(k) || cleanText == k);

    if (isTerminating) {
      String partingMsg = "You're welcome! Glad I could help. Terminating the support session now. Have a great day!";
      if (cleanText.contains('damo') || cleanText.contains('waray na') || cleanText.contains('igo na')) {
        partingMsg =
            'Waray anuman! Malipayon ako nga nakabulig. Awtomatiko ko na nga tatapuson ini nga chat. Maopay nga adlaw!';
      } else if (cleanText.contains('salamat') ||
          cleanText.contains('wala na') ||
          cleanText.contains('ok na') ||
          cleanText.contains('okay na') ||
          cleanText.contains('ayos na')) {
        partingMsg =
            'Walang anuman! Masaya akong makatolong. Awtomatiko ko nang tatapusin ang chat na ito. Magandang araw!';
      }

      setState(() {
        isAiTyping = false;
        chatMessages.add({
          'isUser': false,
          'text': partingMsg,
          'time': 'Just now',
        });
      });

      // Terminate after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            showChat = false;
          });
        }
      });
      return;
    }

    // Only check tokens for a new conversation session (the first user message)
    double? tokensToUpdate;
    int? timestampToUpdate;
    final isNewConversation = (chatMessages.length == 2);

    if (isNewConversation) {
      final token = SessionStorage.idToken;
      final uid = SessionStorage.uid;
      if (token != null && uid != null) {
        try {
          final firestore = FirestoreService(token, component.state.handleTokenRefresh);
          final userDoc = await firestore.getDocument('users/$uid');
          final now = DateTime.now().millisecondsSinceEpoch;

          double tokensAvailable = 5.0;
          int lastRequestedTimestamp = now;

          if (userDoc != null && userDoc.containsKey('supportTokensAvailable')) {
            final double savedTokens = (userDoc['supportTokensAvailable'] as num).toDouble();
            final int savedTime = (userDoc['supportLastRequestedTimestamp'] as num).toInt();

            final elapsedMs = now - savedTime;
            final recovered = elapsedMs / 3600000.0;
            tokensAvailable = (savedTokens + recovered).clamp(0.0, 5.0);
            lastRequestedTimestamp = now;
          }

          if (tokensAvailable < 1.0) {
            final timeNeededMs = (1.0 - tokensAvailable) * 3600000.0;
            final minutesLeft = (timeNeededMs / 60000.0).ceil();
            setState(() {
              isAiTyping = false;
              chatMessages.add({
                'isUser': false,
                'text':
                    'You have run out of free support questions. A new free question token will recover in $minutesLeft minutes. Other services like title, description, and cover note generation remain unlimited!',
                'time': 'Just now',
              });
            });
            return;
          }

          // Keep track of the checked values, but don't save yet!
          tokensToUpdate = tokensAvailable - 1.0;
          timestampToUpdate = lastRequestedTimestamp;
        } catch (e) {
          // Fallback: Proceed if Firestore quota check fails, to ensure resilience.
        }
      }
    }

    // Prepare history to send to Cloudflare (exclude the greeting)
    final history = chatMessages.sublist(1).map((m) {
      return {
        'role': m['isUser'] == true ? 'user' : 'assistant',
        'content': m['text'] as String,
      };
    }).toList();

    try {
      final gemini = GeminiService(currentFirebaseConfig, idToken: SessionStorage.idToken);
      final profile = component.state.userProfile;
      final userCtx = TranyxAIUserContext(
        userId: SessionStorage.uid,
        userRole: component.state.accountType.name,
        walletAddress: profile?.walletPublicKey,
        connectedWallet: profile?.walletPublicKey != null ? 'Solana Wallet' : null,
        tyxbitBalance: profile?.tyxBalance,
        isWalletVerified: profile?.walletPublicKey != null,
      );
      final response = await gemini.askSupportQuestion(history, appContext: userCtx);

      if (response == "TRANSFER_TO_AGENT") {
        setState(() {
          isAiTyping = false;
          showAgentChat = true;
          startAgentChatPolling();
        });
        return;
      }

      final isErrorResponse =
          response.startsWith('Error:') || response.startsWith('HTTP Error:') || response.startsWith('Request failed:');

      // Successfully connected to server AI and got valid response!
      // Only decrement token if this was a new conversation AND not an error response.
      if (!isErrorResponse && isNewConversation && tokensToUpdate != null && timestampToUpdate != null) {
        final token = SessionStorage.idToken;
        final uid = SessionStorage.uid;
        if (token != null && uid != null) {
          try {
            final firestore = FirestoreService(token, component.state.handleTokenRefresh);
            await firestore.setDocument('users/$uid', {
              'supportTokensAvailable': tokensToUpdate,
              'supportLastRequestedTimestamp': timestampToUpdate,
            });
            setState(() {
              supportTokens = tokensToUpdate;
            });
          } catch (_) {
            // Silently ignore or fallback
          }
        }
      }

      setState(() {
        isAiTyping = false;
        chatMessages.add({
          'isUser': false,
          'text': response,
          'time': 'Just now',
        });
      });
    } catch (e) {
      setState(() {
        isAiTyping = false;
        showAgentChat = true;
        startAgentChatPolling();
      });
    }
  }

  Future<void> submitTicket() async {
    if (ticketSubject.trim().isEmpty || ticketDescription.trim().isEmpty) {
      setState(() => submitErrorMessage = 'Please fill out all fields.');
      return;
    }

    setState(() {
      isSubmitting = true;
      submitErrorMessage = null;
      submitSuccessMessage = null;
    });

    try {
      final uid = SessionStorage.uid;
      final token = SessionStorage.idToken;
      if (uid == null || token == null) throw 'Not authenticated';

      final svc = FirestoreService(token, component.state.handleTokenRefresh);
      await svc.createOrUpdate('supportTickets/${DateTime.now().millisecondsSinceEpoch}', {
        'uid': uid,
        'userEmail': component.state.userEmail,
        'userName': component.state.userName,
        'subject': ticketSubject,
        'description': ticketDescription,
        'category': ticketCategory,
        'status': 'Open',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      setState(() {
        isSubmitting = false;
        submitSuccessMessage =
            'Ticket submitted successfully! Ticket ID: #${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}.';
        ticketSubject = '';
        ticketDescription = '';
        showTicketForm = false;
      });
    } catch (e) {
      setState(() {
        isSubmitting = false;
        submitErrorMessage = 'Failed to submit ticket: $e';
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;

    return div(classes: 'space-y-6', [
      subViewHeader(
        title: 'Help & Support',
        isDark: isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),

      if (showAgentChat) ...[
        // Agent Chat Box
        div(
          classes:
              'w-full border rounded-[2rem] overflow-hidden flex flex-col transition-all duration-300 '
              '${isDark ? "bg-zinc-950/80 border-zinc-800" : "bg-white border-zinc-200 shadow-xl"}',
          [
            // Chat Header
            div(
              classes:
                  'px-6 py-4 border-b flex justify-between items-center '
                  '${isDark ? "bg-zinc-900/40 border-zinc-800" : "bg-zinc-50 border-zinc-200"}',
              [
                div(classes: 'flex items-center gap-3', [
                  div(
                    classes:
                        'w-10 h-10 rounded-full bg-emerald-500/10 flex items-center justify-center text-emerald-400',
                    [lIcon('user', cls: 'w-5 h-5 text-emerald-400')],
                  ),
                  div([
                    p(classes: 'font-extrabold text-sm ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
                      Component.text('Live Support Agent'),
                    ]),
                    p(classes: 'text-xs text-emerald-400 font-bold flex items-center gap-1.5', [
                      span(classes: 'w-2 h-2 rounded-full bg-emerald-400 animate-ping', []),
                      Component.text('Connected to Agent Support'),
                    ]),
                  ]),
                ]),
                button(
                  classes:
                      'p-2 rounded-full border transition-all '
                      '${isDark ? "bg-zinc-900 border-zinc-800 text-zinc-400 hover:text-white" : "bg-zinc-100 border-zinc-200 text-zinc-600 hover:text-zinc-800"}',
                  events: {
                    'click': (_) {
                      stopAgentChatPolling();
                      setState(() => showAgentChat = false);
                    },
                  },
                  [lIcon('x', cls: 'w-4 h-4')],
                ),
              ],
            ),

            // Messages Container
            div(
              classes: 'p-6 h-[320px] overflow-y-auto space-y-4 ${isDark ? "bg-zinc-950/40" : "bg-zinc-50/50"}',
              [
                for (final msg in agentChatMessages)
                  div(
                    classes: 'flex flex-col ${msg['isUser'] == true ? "items-end" : "items-start"}',
                    [
                      div(
                        classes: 'text-[10px] font-bold text-zinc-500 mb-1 px-1',
                        [Component.text(msg['senderName'] as String)],
                      ),
                      div(
                        classes:
                            'max-w-[80%] px-4 py-3 rounded-2xl text-sm font-medium leading-relaxed '
                            '${msg['isUser'] == true ? "bg-indigo-600 text-white rounded-tr-none" : (isDark ? "bg-zinc-900 text-zinc-200 border border-zinc-800 rounded-tl-none" : "bg-white text-zinc-800 border border-zinc-200 shadow-sm rounded-tl-none")}',
                        [
                          p([Component.text(msg['text'] as String)]),
                        ],
                      ),
                      span(
                        classes: 'text-[8px] text-zinc-400 mt-1 px-1',
                        [Component.text(msg['time'] as String)],
                      ),
                    ],
                  ),
                if (isLoadingAgentChat)
                  div(
                    classes: 'flex justify-start',
                    [
                      div(
                        classes:
                            'px-4 py-3 rounded-2xl bg-zinc-900 text-zinc-400 border border-zinc-800 rounded-tl-none flex items-center gap-2',
                        [
                          lIcon('loader-2', cls: 'w-4 h-4 animate-spin text-emerald-400'),
                          Component.text('Loading messages...'),
                        ],
                      ),
                    ],
                  ),
              ],
            ),

            // Input Row
            div(
              classes:
                  'p-4 border-t flex gap-3 items-center '
                  '${isDark ? "bg-zinc-900/20 border-zinc-800" : "bg-white border-zinc-200"}',
              [
                input<String>(
                  classes:
                      'flex-1 py-3 px-4 rounded-xl border outline-none text-sm transition-all '
                      '${isDark ? "bg-zinc-950 border-zinc-800 text-white focus:border-indigo-500" : "bg-zinc-50 border-zinc-200 text-zinc-900 focus:border-indigo-500"}',
                  value: currentAgentChatInput,
                  attributes: {
                    'placeholder': 'Type message to live agent support...',
                    'id': 'agent-chat-input',
                    'name': 'agent_chat_message',
                  },
                  onInput: (v) => setState(() => currentAgentChatInput = v),
                  events: {
                    'keydown': (event) {
                      if ((event as web.KeyboardEvent).key == 'Enter') {
                        sendAgentChatMessage();
                      }
                    },
                  },
                ),
                button(
                  classes:
                      'p-3 rounded-xl logo-gradient text-white hover:opacity-90 transition-opacity flex items-center justify-center',
                  events: {'click': (_) => sendAgentChatMessage()},
                  [lIcon('send', cls: 'w-5 h-5 text-white')],
                ),
              ],
            ),
          ],
        ),
      ] else if (showChat) ...[
        // Support Chat Box
        div(
          classes:
              'w-full border rounded-[2rem] overflow-hidden flex flex-col transition-all duration-300 '
              '${isDark ? "bg-zinc-950/80 border-zinc-800" : "bg-white border-zinc-200 shadow-xl"}',
          [
            // Chat Header
            div(
              classes:
                  'px-6 py-4 border-b flex justify-between items-center '
                  '${isDark ? "bg-zinc-900/40 border-zinc-800" : "bg-zinc-50 border-zinc-200"}',
              [
                div(classes: 'flex items-center gap-3', [
                  div(
                    classes: 'w-10 h-10 rounded-full logo-gradient flex items-center justify-center text-white',
                    [lIcon('zap', cls: 'w-5 h-5 text-white animate-pulse')],
                  ),
                  div([
                    p(classes: 'font-extrabold text-sm ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
                      Component.text('Nyx AI Support'),
                    ]),
                    p(classes: 'text-xs text-emerald-400 font-bold flex items-center gap-1.5', [
                      span(classes: 'w-2 h-2 rounded-full bg-emerald-400 animate-ping', []),
                      Component.text(
                        supportTokens != null
                            ? 'Online Now • Tokens: ${supportTokens! % 1 == 0 ? supportTokens!.toInt() : supportTokens!.toStringAsFixed(1)}/5'
                            : 'Online Now',
                      ),
                    ]),
                  ]),
                ]),
                button(
                  classes:
                      'p-2 rounded-full border transition-all '
                      '${isDark ? "bg-zinc-900 border-zinc-800 text-zinc-400 hover:text-white" : "bg-zinc-100 border-zinc-200 text-zinc-600 hover:text-zinc-800"}',
                  events: {'click': (_) => setState(() => showChat = false)},
                  [lIcon('x', cls: 'w-4 h-4')],
                ),
              ],
            ),

            // Messages Container
            div(
              classes: 'p-6 h-[320px] overflow-y-auto space-y-4 ${isDark ? "bg-zinc-950/40" : "bg-zinc-50/50"}',
              [
                for (final msg in chatMessages)
                  div(
                    classes: 'flex ${msg['isUser'] == true ? "justify-end" : "justify-start"}',
                    [
                      div(
                        classes:
                            'max-w-[80%] px-4 py-3 rounded-2xl text-sm font-medium leading-relaxed '
                            '${msg['isUser'] == true ? "bg-indigo-600 text-white rounded-tr-none" : (isDark ? "bg-zinc-900 text-zinc-200 border border-zinc-800 rounded-tl-none" : "bg-white text-zinc-800 border border-zinc-200 shadow-sm rounded-tl-none")}',
                        [
                          p([Component.text(msg['text'] as String)]),
                        ],
                      ),
                    ],
                  ),
                if (isAiTyping)
                  div(
                    classes: 'flex justify-start',
                    [
                      div(
                        classes:
                            'px-4 py-3 rounded-2xl bg-zinc-900 text-zinc-400 border border-zinc-800 rounded-tl-none flex items-center gap-2',
                        [
                          lIcon('loader-2', cls: 'w-4 h-4 animate-spin text-indigo-400'),
                          Component.text('Nyx is typing...'),
                        ],
                      ),
                    ],
                  ),
              ],
            ),

            // Input Row
            div(
              classes:
                  'p-4 border-t flex gap-3 items-center '
                  '${isDark ? "bg-zinc-900/20 border-zinc-800" : "bg-white border-zinc-200"}',
              [
                input<String>(
                  classes:
                      'flex-1 py-3 px-4 rounded-xl border outline-none text-sm transition-all '
                      '${isDark ? "bg-zinc-950 border-zinc-800 text-white focus:border-indigo-500" : "bg-zinc-50 border-zinc-200 text-zinc-900 focus:border-indigo-500"}',
                  value: currentChatInput,
                  attributes: {
                    'placeholder': 'Ask me anything about Tranyx...',
                    'id': 'support-chat-input',
                    'name': 'support_chat_message',
                  },
                  onInput: (v) => setState(() => currentChatInput = v),
                  events: {
                    'keydown': (event) {
                      if ((event as web.KeyboardEvent).key == 'Enter') {
                        sendChatMessage();
                      }
                    },
                  },
                ),
                button(
                  classes:
                      'p-3 rounded-xl logo-gradient text-white hover:opacity-90 transition-opacity flex items-center justify-center',
                  events: {'click': (_) => sendChatMessage()},
                  [lIcon('send', cls: 'w-5 h-5 text-white')],
                ),
              ],
            ),
          ],
        ),
      ] else if (showTicketForm) ...[
        // Support Ticket Form
        div(
          classes:
              'w-full border rounded-[2rem] p-6 space-y-6 '
              '${isDark ? "bg-zinc-950/80 border-zinc-800" : "bg-white border-zinc-200 shadow-xl"}',
          [
            div(classes: 'flex justify-between items-center', [
              h3(classes: 'text-lg font-black tracking-tight ${isDark ? "text-zinc-150" : "text-zinc-800"}', [
                Component.text('Submit Support Ticket'),
              ]),
              button(
                classes:
                    'p-2 rounded-full border transition-all '
                    '${isDark ? "bg-zinc-900 border-zinc-800 text-zinc-400 hover:text-white" : "bg-zinc-100 border-zinc-200 text-zinc-600 hover:text-zinc-800"}',
                events: {'click': (_) => setState(() => showTicketForm = false)},
                [lIcon('x', cls: 'w-4 h-4')],
              ),
            ]),

            if (submitSuccessMessage != null)
              div(
                classes:
                    'p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-sm font-medium flex items-center gap-2',
                [lIcon('check-circle', cls: 'w-5 h-5'), Component.text(submitSuccessMessage!)],
              ),

            if (submitErrorMessage != null)
              div(
                classes:
                    'p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm font-medium flex items-center gap-2',
                [lIcon('alert-circle', cls: 'w-5 h-5'), Component.text(submitErrorMessage!)],
              ),

            div(classes: 'space-y-4', [
              // Ticket Subject
              inputField(
                label: 'Subject / Topic',
                placeholder: 'e.g. Disputed Escrow or Payment issue',
                iconName: 'file-text',
                isDark: isDark,
                value: ticketSubject,
                onChange: (v) => setState(() => ticketSubject = v),
              ),

              // Category Selector
              div(classes: 'space-y-2', [
                span(classes: 'block text-xs font-medium ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                  Component.text('Issue Category'),
                ]),
                div(classes: 'flex gap-2 flex-wrap', [
                  for (final cat in ['General', 'Payment', 'Escrow Dispute', 'Account Security'])
                    button(
                      classes:
                          'px-4 py-2 text-xs font-bold rounded-xl border transition-all '
                          '${ticketCategory == cat ? "bg-indigo-600 border-indigo-500 text-white" : (isDark ? "bg-zinc-900 border-zinc-800 text-zinc-400 hover:bg-zinc-800" : "bg-zinc-50 border-zinc-200 text-zinc-600 hover:bg-zinc-100")}',
                      events: {'click': (_) => setState(() => ticketCategory = cat)},
                      [Component.text(cat)],
                    ),
                ]),
              ]),

              // Description Textarea
              div(
                classes:
                    'p-4 rounded-2xl border transition-colors '
                    '${isDark ? "bg-zinc-900 border-zinc-800 focus-within:border-indigo-500" : "bg-white border-zinc-200 focus-within:border-indigo-500 shadow-sm"}',
                [
                  span(classes: 'block text-xs font-medium mb-2 ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                    Component.text('Describe your problem detailedly'),
                  ]),
                  textarea(
                    classes:
                        'w-full bg-transparent border-none outline-none h-28 text-sm md:text-base font-medium resize-none ${isDark ? "text-zinc-200" : "text-zinc-900"}',
                    attributes: {'placeholder': 'Please specify details or reference contract IDs...'},
                    events: {
                      'input': (e) {
                        setState(() => ticketDescription = getInputValue(e.target));
                      },
                    },
                    [Component.text(ticketDescription)],
                  ),
                ],
              ),
            ]),

            button(
              classes:
                  'w-full py-4 rounded-xl logo-gradient text-white font-bold hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
              events: {'click': (_) => submitTicket()},
              [
                if (isSubmitting) lIcon('loader-2', cls: 'w-5 h-5 animate-spin'),
                Component.text(isSubmitting ? 'Submitting Ticket...' : 'Submit Support Ticket'),
              ],
            ),
          ],
        ),
      ] else ...[
        // Default View Option Buttons
        div(classes: 'grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4', [
          button(
            classes:
                'py-6 px-4 rounded-[2rem] border transition-all text-center flex flex-col items-center justify-center gap-3 '
                '${isDark ? "bg-zinc-900/60 border-purple-500/30 hover:bg-purple-950/20 hover:border-purple-500/60" : "bg-white border-purple-200 shadow-sm hover:shadow-md hover:border-purple-400"}',
            events: {
              'click': (_) => s.openWalkthroughModal(),
            },
            [
              div(
                classes: 'w-12 h-12 rounded-2xl bg-purple-500/10 flex items-center justify-center text-purple-400',
                [lIcon('sparkles', cls: 'w-6 h-6')],
              ),
              div([
                p(classes: 'font-bold text-sm ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
                  Component.text('App Guide & Badges'),
                ]),
                p(classes: 'text-xs text-purple-400 mt-1', [
                  Component.text('Interactive walkthrough'),
                ]),
              ]),
            ],
          ),
          button(
            classes:
                'py-6 px-4 rounded-[2rem] border transition-all text-center flex flex-col items-center justify-center gap-3 '
                '${isDark ? "bg-zinc-900/60 border-zinc-800 hover:bg-zinc-800 hover:border-indigo-500/50" : "bg-white border-zinc-200 shadow-sm hover:shadow-md hover:border-indigo-400"}',
            events: {
              'click': (_) {
                loadSupportTokens();
                setState(() {
                  showChat = true;
                  chatMessages.clear();
                  chatMessages.add({
                    'isUser': false,
                    'text': 'Hi! I am Nyx, your Tranyx AI support agent. How can I help you today?',
                    'time': 'Just now',
                  });
                });
              },
            },
            [
              div(
                classes: 'w-12 h-12 rounded-2xl bg-indigo-500/10 flex items-center justify-center text-indigo-400',
                [lIcon('message-square', cls: 'w-6 h-6')],
              ),
              div([
                p(classes: 'font-bold text-sm ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
                  Component.text('Start AI Chat'),
                ]),
                p(classes: 'text-xs text-zinc-500 mt-1', [
                  Component.text('Instant dynamic answers'),
                ]),
              ]),
            ],
          ),
          button(
            classes:
                'py-6 px-4 rounded-[2rem] border transition-all text-center flex flex-col items-center justify-center gap-3 '
                '${isDark ? "bg-zinc-900/60 border-zinc-800 hover:bg-zinc-800 hover:border-emerald-500/50" : "bg-white border-zinc-200 shadow-sm hover:shadow-md hover:border-emerald-400"}',
            events: {
              'click': (_) {
                setState(() {
                  showAgentChat = true;
                  showChat = false;
                  showTicketForm = false;
                });
                loadAgentChatMessages();
                startAgentChatPolling();
              },
            },
            [
              div(
                classes: 'w-12 h-12 rounded-2xl bg-emerald-500/10 flex items-center justify-center text-emerald-400',
                [lIcon('user', cls: 'w-6 h-6')],
              ),
              div([
                p(classes: 'font-bold text-sm ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
                  Component.text('Chat with Agent'),
                ]),
                p(classes: 'text-xs text-zinc-500 mt-1', [
                  Component.text('Speak with actual support'),
                ]),
              ]),
            ],
          ),
          button(
            classes:
                'py-6 px-4 rounded-[2rem] border transition-all text-center flex flex-col items-center justify-center gap-3 '
                '${isDark ? "bg-zinc-900/60 border-zinc-800 hover:bg-zinc-800 hover:border-indigo-500/50" : "bg-white border-zinc-200 shadow-sm hover:shadow-md hover:border-indigo-400"}',
            events: {'click': (_) => setState(() => showTicketForm = true)},
            [
              div(
                classes: 'w-12 h-12 rounded-2xl bg-violet-500/10 flex items-center justify-center text-violet-400',
                [lIcon('file-text', cls: 'w-6 h-6')],
              ),
              div([
                p(classes: 'font-bold text-sm ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
                  Component.text('Submit Ticket'),
                ]),
                p(classes: 'text-xs text-zinc-500 mt-1', [
                  Component.text('Raise issue to admins'),
                ]),
              ]),
            ],
          ),
        ]),
      ],

      // Expandable FAQ Section
      div(classes: 'space-y-4 mt-6', [
        p(classes: 'text-xs font-black uppercase tracking-[0.2em] opacity-60 mb-2', [
          Component.text('Frequently Asked Questions'),
        ]),
        div(classes: 'space-y-3', [
          for (int i = 0; i < faqData.length; i++) ...[
            button(
              classes:
                  'w-full flex items-center justify-between p-5 rounded-2xl border transition-all text-left '
                  '${isDark ? "bg-zinc-900/60 border-zinc-800 hover:bg-zinc-800" : "bg-white border-zinc-200 shadow-sm hover:shadow-md hover:bg-zinc-50"}',
              events: {'click': (_) => toggleFaq(i)},
              [
                div(classes: 'flex items-center gap-4', [
                  lIcon(faqData[i]['icon']!, cls: 'w-5 h-5 ${isDark ? "text-indigo-400" : "text-indigo-500"}'),
                  span(
                    classes: 'font-bold text-base ${isDark ? "text-zinc-200" : "text-zinc-800"}',
                    [Component.text(faqData[i]['title']!)],
                  ),
                ]),
                lIcon(
                  expandedFaqIndex == i ? 'chevron-down' : 'chevron-right',
                  cls: 'w-5 h-5 ${isDark ? "text-zinc-500" : "text-zinc-400"} transition-transform',
                ),
              ],
            ),
            if (expandedFaqIndex == i)
              div(
                classes:
                    'p-6 rounded-2xl -mt-1 border border-t-0 animate-fade-in '
                    '${isDark ? "bg-zinc-900/30 border-zinc-800 text-zinc-400" : "bg-zinc-50 border-zinc-150 text-zinc-600"}',
                [
                  p(classes: 'text-sm leading-relaxed font-medium', [
                    Component.text(faqData[i]['answer']!),
                  ]),
                ],
              ),
          ],
        ]),
      ]),
    ]);
  }
}

class _HistoryView extends StatefulComponent {
  final TranyxAppState state;
  const _HistoryView({required this.state});

  @override
  State<_HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<_HistoryView> {
  String activeTab = 'all_transactions';
  String activeFilter = 'daily';
  String ledgerFilter = 'all'; // 'all', 'income', 'expenses', 'topups', 'withdrawals', 'jobs', 'purchases'
  int hoveredBarIndex = -1;
  int currentPage = 1;
  int itemsPerPage = 10;

  // Earnings dataset (kept static for graphs temporarily)
  final Map<String, List<Map<String, dynamic>>> earningsData = {
    'daily': [
      {'label': 'Mon', 'value': 1200.0},
      {'label': 'Tue', 'value': 800.0},
      {'label': 'Wed', 'value': 1500.0},
      {'label': 'Thu', 'value': 2100.0},
      {'label': 'Fri', 'value': 950.0},
      {'label': 'Sat', 'value': 3000.0},
      {'label': 'Sun', 'value': 2400.0},
    ],
    'weekly': [
      {'label': 'Week 1', 'value': 8500.0},
      {'label': 'Week 2', 'value': 12000.0},
      {'label': 'Week 3', 'value': 9800.0},
      {'label': 'Week 4', 'value': 15400.0},
    ],
    'monthly': [
      {'label': 'Jan', 'value': 38000.0},
      {'label': 'Feb', 'value': 45000.0},
      {'label': 'Mar', 'value': 42000.0},
      {'label': 'Apr', 'value': 58000.0},
      {'label': 'May', 'value': 64000.0},
      {'label': 'Jun', 'value': 72000.0},
    ],
    'yearly': [
      {'label': '2024', 'value': 450000.0},
      {'label': '2025', 'value': 680000.0},
      {'label': '2026', 'value': 320000.0},
    ],
  };

  List<Map<String, dynamic>> allUnifiedLedger = [];
  List<Map<String, dynamic>> earningsTransactions = [];
  List<Map<String, dynamic>> purchaseTransactions = [];
  List<Map<String, dynamic>> depositTransactions = [];
  List<DepositRequest> userP2pDeposits = [];
  List<Map<String, dynamic>> userWithdrawalRequests = [];
  String p2pFilter = 'all'; // 'all', 'deposits', 'withdrawals'
  List<Map<String, dynamic>> _dbRentalHistory = [];
  double totalEarningsSum = 0.0;
  double totalInflowSum = 0.0;
  double totalOutflowSum = 0.0;
  int completedGigsCount = 0;
  bool _isLoading = true;

  String _cleanAgentName(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Payment Agent';
    final trimmed = raw.trim();
    if (trimmed.contains('@')) {
      final local = trimmed.split('@').first;
      return local
          .split(RegExp(r'[._\-]'))
          .where((s) => s.isNotEmpty)
          .map((s) => s[0].toUpperCase() + (s.length > 1 ? s.substring(1).toLowerCase() : ''))
          .join(' ');
    }
    return trimmed;
  }

  void _loadRentalHistory() async {
    final uid = component.state.userProfile?.uid;
    if (uid == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final list = await component.state.firestore.getMyRentalHistory(uid);
      final p2pList = await component.state.firestore.fetchUserDepositRequests(uid);
      final withList = await component.state.firestore.fetchUserWithdrawalRequests(uid);
      _dbRentalHistory = list;
      userP2pDeposits = p2pList;
      userWithdrawalRequests = withList;
      _loadDbHistory();
    } catch (e) {
      print('Error loading db rental history: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDate(int? ms) {
    if (ms == null) return 'Unknown Date';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day.toString().padLeft(2, '0')}, ${dt.year}';
  }

  void _loadDbHistory() {
    final myJobs = component.state.myJobs;
    final uid = component.state.userProfile?.uid;
    if (uid == null) return;

    final eTrans = <Map<String, dynamic>>[];
    final pTrans = <Map<String, dynamic>>[];
    final dTrans = <Map<String, dynamic>>[];

    double earningsSum = 0.0;
    int gigsCount = 0;

    final now = DateTime.now();
    // Monday of the current week at 00:00:00 local time
    final today = DateTime(now.year, now.month, now.day);
    final currentWeekMonday = today.subtract(Duration(days: today.weekday - 1));
    final currentWeekMondayMs = currentWeekMonday.millisecondsSinceEpoch;
    final currentWeekSundayEnd = currentWeekMonday.add(const Duration(days: 7));
    final currentWeekSundayEndMs = currentWeekSundayEnd.millisecondsSinceEpoch;

    // Start & end of current month
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final currentMonthStartMs = currentMonthStart.millisecondsSinceEpoch;
    final currentMonthEnd = DateTime(now.year, now.month + 1, 1);
    final currentMonthEndMs = currentMonthEnd.millisecondsSinceEpoch;

    // Start & end of current year
    final currentYearStart = DateTime(now.year, 1, 1);
    final currentYearStartMs = currentYearStart.millisecondsSinceEpoch;
    final currentYearEnd = DateTime(now.year + 1, 1, 1);
    final currentYearEndMs = currentYearEnd.millisecondsSinceEpoch;

    // Initialize daily/weekly/monthly/yearly aggregates
    final dailyAgg = {'Mon': 0.0, 'Tue': 0.0, 'Wed': 0.0, 'Thu': 0.0, 'Fri': 0.0, 'Sat': 0.0, 'Sun': 0.0};
    final weeklyAgg = {'Week 1': 0.0, 'Week 2': 0.0, 'Week 3': 0.0, 'Week 4': 0.0};
    final monthlyAgg = {
      'Jan': 0.0,
      'Feb': 0.0,
      'Mar': 0.0,
      'Apr': 0.0,
      'May': 0.0,
      'Jun': 0.0,
      'Jul': 0.0,
      'Aug': 0.0,
      'Sep': 0.0,
      'Oct': 0.0,
      'Nov': 0.0,
      'Dec': 0.0,
    };
    final currentYear = now.year;
    final yearlyAgg = <String, double>{
      '${currentYear - 2}': 0.0,
      '${currentYear - 1}': 0.0,
      '$currentYear': 0.0,
    };

    for (final job in myJobs) {
      final status = job['status'] as String? ?? '';
      final lowerStatus = status.toLowerCase();
      if (lowerStatus == 'completed' || lowerStatus == 'done' || lowerStatus == 'complete') {
        final creatorId = job['creatorId'] as String?;
        final applicantId = job['acceptedApplicantId'] as String?;
        final title = job['title'] as String? ?? 'Job';
        final price = (job['pricingValue'] as num?)?.toDouble() ?? 0.0;
        final createdAt = (job['createdAt'] as num?)?.toInt();

        // If the user was the accepted applicant -> earnings
        if (applicantId == uid) {
          final payout = price * 0.97;
          earningsSum += payout;
          gigsCount++;
          eTrans.add({
            'title': title,
            'desc': 'Completed contract',
            'date': _formatDate(createdAt),
            'amount': payout,
            'baseAmount': price,
            'commissionFee': price * 0.03,
            'commissionLabel': 'Platform Commission (3%)',
            'status': 'Released',
            'timestamp': createdAt ?? 0,
          });

          // Aggregate for graphs
          if (createdAt != null) {
            final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
            // Daily (only for current calendar week)
            if (createdAt >= currentWeekMondayMs && createdAt < currentWeekSundayEndMs) {
              final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              final dayName = days[dt.weekday - 1];
              dailyAgg[dayName] = (dailyAgg[dayName] ?? 0.0) + payout;
            }

            // Weekly (only for current calendar month)
            if (createdAt >= currentMonthStartMs && createdAt < currentMonthEndMs) {
              final wNum = ((dt.day - 1) ~/ 7) + 1;
              final wName = 'Week ${wNum > 4 ? 4 : wNum}';
              weeklyAgg[wName] = (weeklyAgg[wName] ?? 0.0) + payout;
            }

            // Monthly (only for current calendar year)
            if (createdAt >= currentYearStartMs && createdAt < currentYearEndMs) {
              final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
              final mName = months[dt.month - 1];
              monthlyAgg[mName] = (monthlyAgg[mName] ?? 0.0) + payout;
            }

            // Yearly (all-time)
            final yName = dt.year.toString();
            yearlyAgg[yName] = (yearlyAgg[yName] ?? 0.0) + payout;
          }
        }

        // If the user was the creator -> purchases
        if (creatorId == uid) {
          final txFee = price * 0.07;
          final convFee = price * 0.03;
          final totalCost = price + txFee + convFee;
          pTrans.add({
            'title': title,
            'desc': 'Job payment',
            'date': _formatDate(createdAt),
            'amount': totalCost,
            'baseAmount': price,
            'txFee': txFee,
            'convFee': convFee,
            'status': 'Successful',
            'timestamp': createdAt ?? 0,
          });
        }
      }
    }

    // Process Vehicle Rentals
    for (final rentalMap in component.state.realtimeRentals) {
      final rental = VehicleRental.fromMap(rentalMap, rentalMap['id'] ?? '');
      final status = rental.status.toLowerCase();
      if (status == 'completed' || status == 'complete') {
        final creatorId = rental.hostId;
        final applicantId = rental.renteeId;
        final title = '${rental.year} ${rental.brand} ${rental.model}';
        final price = rental.totalCost ?? 0.0;
        final createdAtMs = rental.createdAt.millisecondsSinceEpoch;

        // If the user was the host -> earnings
        if (creatorId == uid) {
          final payout = price * 0.97; // 3% host commission fee deducted
          earningsSum += payout;
          gigsCount++;
          eTrans.add({
            'title': title,
            'desc': 'Completed vehicle rental',
            'date': _formatDate(createdAtMs),
            'amount': payout,
            'baseAmount': price,
            'commissionFee': price * 0.03,
            'commissionLabel': 'Platform Commission (3%)',
            'listingFee': rental.priceDaily * 0.015,
            'status': 'Released',
            'timestamp': createdAtMs,
          });

          // Aggregate for graphs
          final dt = rental.createdAt;
          // Daily (only for current calendar week)
          if (createdAtMs >= currentWeekMondayMs && createdAtMs < currentWeekSundayEndMs) {
            final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            final dayName = days[dt.weekday - 1];
            dailyAgg[dayName] = (dailyAgg[dayName] ?? 0.0) + payout;
          }

          // Weekly (only for current calendar month)
          if (createdAtMs >= currentMonthStartMs && createdAtMs < currentMonthEndMs) {
            final wNum = ((dt.day - 1) ~/ 7) + 1;
            final wName = 'Week ${wNum > 4 ? 4 : wNum}';
            weeklyAgg[wName] = (weeklyAgg[wName] ?? 0.0) + payout;
          }

          // Monthly (only for current calendar year)
          if (createdAtMs >= currentYearStartMs && createdAtMs < currentYearEndMs) {
            final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            final mName = months[dt.month - 1];
            monthlyAgg[mName] = (monthlyAgg[mName] ?? 0.0) + payout;
          }

          // Yearly (all-time)
          final yName = dt.year.toString();
          yearlyAgg[yName] = (yearlyAgg[yName] ?? 0.0) + payout;
        }

        // If the user was the rentee -> purchases
        if (applicantId == uid) {
          final bookingFee = price * 0.03; // 3% platform booking fee
          pTrans.add({
            'title': title,
            'desc': 'Vehicle rental payment',
            'date': _formatDate(createdAtMs),
            'amount': price + bookingFee,
            'baseAmount': price,
            'bookingFee': bookingFee,
            'status': 'Successful',
            'timestamp': createdAtMs,
          });
        }
      }
    }

    // Process DB Rental History (both Vehicles and Properties)
    for (final rentalMap in _dbRentalHistory) {
      final kind = rentalMap['rentalKind'] as String? ?? 'vehicle';
      if (kind == 'vehicle') {
        final rental = VehicleRental.fromMap(rentalMap, rentalMap['id'] ?? '');
        final creatorId = rental.hostId;
        final applicantId = rental.renteeId;
        final title = '${rental.year} ${rental.brand} ${rental.model}';
        final price = rental.totalCost ?? 0.0;
        final createdAtMs = rental.createdAt.millisecondsSinceEpoch;

        // If the user was the host -> earnings
        if (creatorId == uid) {
          final payout = price * 0.97; // 3% host commission fee deducted
          earningsSum += payout;
          gigsCount++;

          final alreadyAdded = eTrans.any((e) => e['timestamp'] == createdAtMs && e['title'] == title);
          if (!alreadyAdded) {
            eTrans.add({
              'title': title,
              'desc': 'Completed vehicle rental',
              'date': _formatDate(createdAtMs),
              'amount': payout,
              'baseAmount': price,
              'commissionFee': price * 0.03,
              'commissionLabel': 'Platform Commission (3%)',
              'listingFee': rental.priceDaily * 0.015,
              'status': 'Released',
              'timestamp': createdAtMs,
            });

            // Aggregate for graphs
            final dt = rental.createdAt;
            // Daily (only for current calendar week)
            if (createdAtMs >= currentWeekMondayMs && createdAtMs < currentWeekSundayEndMs) {
              final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              final dayName = days[dt.weekday - 1];
              dailyAgg[dayName] = (dailyAgg[dayName] ?? 0.0) + payout;
            }

            // Weekly (only for current calendar month)
            if (createdAtMs >= currentMonthStartMs && createdAtMs < currentMonthEndMs) {
              final wNum = ((dt.day - 1) ~/ 7) + 1;
              final wName = 'Week ${wNum > 4 ? 4 : wNum}';
              weeklyAgg[wName] = (weeklyAgg[wName] ?? 0.0) + payout;
            }

            // Monthly (only for current calendar year)
            if (createdAtMs >= currentYearStartMs && createdAtMs < currentYearEndMs) {
              final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
              final mName = months[dt.month - 1];
              monthlyAgg[mName] = (monthlyAgg[mName] ?? 0.0) + payout;
            }

            // Yearly (all-time)
            final yName = dt.year.toString();
            yearlyAgg[yName] = (yearlyAgg[yName] ?? 0.0) + payout;
          }
        }

        // If the user was the rentee -> purchases
        if (applicantId == uid) {
          final alreadyAdded = pTrans.any((tx) => tx['timestamp'] == createdAtMs && tx['title'] == title);
          if (!alreadyAdded) {
            final bookingFee = price * 0.03;
            pTrans.add({
              'title': title,
              'desc': 'Vehicle rental payment',
              'date': _formatDate(createdAtMs),
              'amount': price + bookingFee,
              'baseAmount': price,
              'bookingFee': bookingFee,
              'status': 'Successful',
              'timestamp': createdAtMs,
            });
          }
        }
      } else {
        // Property rental
        final rental = PropertyRental.fromMap(rentalMap, rentalMap['id'] ?? '');
        final creatorId = rental.hostId;
        final applicantId = rental.renteeId;
        final title = rental.title;
        final price = rental.totalCost ?? 0.0;
        final createdAtMs = rental.createdAt.millisecondsSinceEpoch;

        // If the user was the host -> earnings
        if (creatorId == uid) {
          final payout = price * 0.97; // 3% host commission fee deducted
          earningsSum += payout;
          gigsCount++;

          final alreadyAdded = eTrans.any((e) => e['timestamp'] == createdAtMs && e['title'] == title);
          if (!alreadyAdded) {
            eTrans.add({
              'title': title,
              'desc': 'Completed property rental',
              'date': _formatDate(createdAtMs),
              'amount': payout,
              'baseAmount': price,
              'commissionFee': price * 0.03,
              'commissionLabel': 'Platform Commission (3%)',
              'listingFee': rental.priceMonthly * 0.015,
              'status': 'Released',
              'timestamp': createdAtMs,
            });

            // Aggregate for graphs
            final dt = rental.createdAt;
            // Daily (only for current calendar week)
            if (createdAtMs >= currentWeekMondayMs && createdAtMs < currentWeekSundayEndMs) {
              final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              final dayName = days[dt.weekday - 1];
              dailyAgg[dayName] = (dailyAgg[dayName] ?? 0.0) + payout;
            }

            // Weekly (only for current calendar month)
            if (createdAtMs >= currentMonthStartMs && createdAtMs < currentMonthEndMs) {
              final wNum = ((dt.day - 1) ~/ 7) + 1;
              final wName = 'Week ${wNum > 4 ? 4 : wNum}';
              weeklyAgg[wName] = (weeklyAgg[wName] ?? 0.0) + payout;
            }

            // Monthly (only for current calendar year)
            if (createdAtMs >= currentYearStartMs && createdAtMs < currentYearEndMs) {
              final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
              final mName = months[dt.month - 1];
              monthlyAgg[mName] = (monthlyAgg[mName] ?? 0.0) + payout;
            }

            // Yearly (all-time)
            final yName = dt.year.toString();
            yearlyAgg[yName] = (yearlyAgg[yName] ?? 0.0) + payout;
          }
        }

        // If the user was the rentee -> purchases
        if (applicantId == uid) {
          final alreadyAdded = pTrans.any((tx) => tx['timestamp'] == createdAtMs && tx['title'] == title);
          if (!alreadyAdded) {
            final bookingFee = price * 0.03;
            pTrans.add({
              'title': title,
              'desc': 'Property rental payment',
              'date': _formatDate(createdAtMs),
              'amount': price + bookingFee,
              'baseAmount': price,
              'bookingFee': bookingFee,
              'status': 'Successful',
              'timestamp': createdAtMs,
            });
          }
        }
      }
    }

    // Process userTransactions for deposits (or any other types)
    for (final tx in component.state.userTransactions) {
      final record = WalletTransaction.fromMap(tx);
      final createdAt = record.createdAt;
      final rawStatus = (tx['status'] as String? ?? record.status).toUpperCase();
      final isCancelled = rawStatus == 'CANCELLED' || rawStatus == 'REJECTED';

      final isDeposit = record.amount >= 0 ||
          record.transactionType == WalletTransactionType.deposit ||
          record.transactionType == WalletTransactionType.refund ||
          isCancelled;

      if (isDeposit) {
        final rawMethod = (tx['paymentMethod'] ?? tx['method'] ?? record.method ?? '').toString();
        final rawProof = record.proofImageUrl ??
            (tx['proofImageUrl'] ?? tx['proofUrl'] ?? tx['receiptUrl'] ?? tx['proof_image_url'] ?? tx['imageUrl']) as String?;
        final rawRef = record.referenceNumber ??
            (tx['referenceNumber'] ?? tx['refNumber'] ?? tx['ref']) as String?;
        var rawDesc = (tx['desc'] ?? tx['description'] ?? record.desc ?? '').toString();
        final rawReason = (tx['rejectionReason'] ?? tx['reason'] ?? record.rejectionReason) as String?;

        final isRefund = record.transactionType == WalletTransactionType.refund ||
            (tx['type'] ?? '').toString().contains('refund') ||
            (tx['category'] ?? '') == 'refund';

        final isP2p = !isRefund && (record.originRail == TransactionOriginRail.manualP2p ||
            tx['depositRequestId'] != null ||
            (tx['id'] as String? ?? '').startsWith('p2p_') ||
            rawMethod.toLowerCase().contains('gcash') ||
            rawMethod.toLowerCase().contains('maya') ||
            rawMethod.toLowerCase().contains('p2p') ||
            rawDesc.toLowerCase().contains('gcash') ||
            rawDesc.toLowerCase().contains('maya') ||
            rawDesc.toLowerCase().contains('p2p'));

        String method;
        String originRail;
        if (isRefund) {
          originRail = 'internal_balance';
          method = rawMethod.isNotEmpty ? rawMethod : 'Tranyx Escrow';
        } else if (isP2p) {
          originRail = 'manual_p2p';
          method = rawMethod.toLowerCase().contains('maya')
              ? 'Maya'
              : (rawMethod.toLowerCase().contains('gcash') ? 'GCash' : (rawMethod.isNotEmpty ? rawMethod : 'GCash'));
        } else if (record.originRail == TransactionOriginRail.mwaOnChain || record.solanaTxSignature != null || tx['solanaTxSignature'] != null) {
          originRail = 'mwa_on_chain';
          method = rawMethod.isNotEmpty ? rawMethod : 'Solana';
        } else {
          originRail = 'internal_balance';
          method = rawMethod.isNotEmpty ? rawMethod : 'Tyxbit Balance';
        }

        if (rawDesc.isEmpty) {
          if (isCancelled) {
            rawDesc = rawStatus == 'REJECTED'
                ? 'P2P Top-Up request rejected by agent'
                : 'P2P Top-Up request cancelled';
          } else if (isRefund) {
            rawDesc = '100% Escrow refund for cancelled job';
          } else {
            rawDesc = isP2p
                ? (rawRef != null && rawRef.isNotEmpty ? 'Manual $method Transfer (Ref: $rawRef)' : 'P2P Top-Up')
                : 'Funds added to Tyxbit balance';
          }
        }

        // Clean any email address inside rawDesc to friendly agent name (e.g. agent.juana2@tranyx.app -> Agent Juana)
        final cleanDesc = rawDesc.replaceAllMapped(
          RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
          (m) => cleanAgentDisplayName(m.group(0)),
        );

        final title = (tx['title'] as String?) ??
            (isCancelled
                ? (rawStatus == 'REJECTED' ? 'P2P Top-Up (Rejected)' : 'P2P Top-Up (Cancelled)')
                : (isRefund
                    ? 'Job Escrow Refund'
                    : (originRail == 'manual_p2p'
                        ? 'P2P Top-Up ($method)'
                        : (originRail == 'mwa_on_chain' ? 'Solana Top-Up' : 'Wallet Top-Up'))));

        final categoryLabel = isCancelled
            ? (rawStatus == 'REJECTED' ? 'Rejected' : 'Cancelled')
            : (isRefund ? 'Escrow Refund' : (isP2p ? 'P2P Top-Up' : 'Added Funds'));

        dTrans.add({
          'id': record.id.isNotEmpty ? record.id : (tx['id'] as String? ?? 'dep_${createdAt}'),
          'depositRequestId': tx['depositRequestId'] as String? ?? (tx['id'] as String? ?? '').replaceAll('p2p_dep_', ''),
          'title': title,
          'desc': cleanDesc,
          'date': _formatDate(createdAt),
          'amount': record.amount.abs(),
          'cryptoAmount': originRail == 'mwa_on_chain' ? record.cryptoAmount : null,
          'cryptoCurrency': originRail == 'mwa_on_chain' ? record.cryptoCurrency : null,
          'solanaTxSignature': originRail == 'mwa_on_chain' ? record.solanaTxSignature : null,
          'originRail': originRail,
          'method': method,
          'type': isCancelled ? 'cancelled' : 'credit',
          'category': isCancelled ? rawStatus.toLowerCase() : (isRefund ? 'refund' : 'topup'),
          'categoryLabel': categoryLabel,
          'status': record.status.isNotEmpty ? record.status : (isCancelled ? rawStatus : 'Completed'),
          'referenceNumber': rawRef,
          'proofImageUrl': rawProof,
          'rejectionReason': rawReason,
          'agentName': cleanAgentDisplayName(tx['agentName'] as String?),
          'timestamp': createdAt,
        });
      } else if (record.transactionType == WalletTransactionType.listingFee) {
        pTrans.add({
          'title': record.title.isNotEmpty ? record.title : 'Listing Fee',
          'desc': record.desc.isNotEmpty ? record.desc : 'Platform Listing Fee (1.5%)',
          'date': _formatDate(createdAt),
          'amount': record.amount.abs(),
          'status': 'Successful',
          'timestamp': createdAt,
          'kind': 'listing_fee',
        });
      } else if (record.transactionType == WalletTransactionType.feeDeduction ||
          (tx['type'] ?? '').toString().contains('fee')) {
        pTrans.add({
          'title': record.title.isNotEmpty ? record.title : 'Job Completion Fees (10%)',
          'desc': record.desc.isNotEmpty ? record.desc : '7% Transaction Fee & 3% Convenience Fee',
          'date': _formatDate(createdAt),
          'amount': record.amount.abs(),
          'status': 'Successful',
          'timestamp': createdAt,
          'kind': 'service_fee',
        });
      } else if (record.transactionType == WalletTransactionType.subscription ||
          (tx['type'] ?? '').toString() == 'subscription') {
        pTrans.add({
          'title': record.title.isNotEmpty ? record.title : 'Hybrid PRO Subscription',
          'desc': record.desc.isNotEmpty ? record.desc : 'Monthly Platform Membership',
          'date': _formatDate(createdAt),
          'amount': record.amount.abs(),
          'status': 'Successful',
          'timestamp': createdAt,
          'kind': 'subscription',
        });
      } else if (record.transactionType == WalletTransactionType.withdraw ||
          (tx['type'] ?? '').toString().contains('withdraw')) {
        pTrans.add({
          'title': record.title.isNotEmpty ? record.title : 'Wallet Withdrawal',
          'desc': record.desc.isNotEmpty ? record.desc : 'Disbursed Funds',
          'date': _formatDate(createdAt),
          'amount': record.amount.abs(),
          'status': record.status.isNotEmpty ? record.status : 'Completed',
          'timestamp': createdAt,
          'kind': 'withdrawal',
        });
      }
    }

    // Merge User P2P Deposits into dTrans (matching by id, depositRequestId, referenceNumber, or timestamp/amount proximity)
    for (final p2p in userP2pDeposits) {
      final p2pStatus = p2p.status.toUpperCase();
      final isCancelled = p2pStatus == 'CANCELLED' || p2pStatus == 'REJECTED';
      final method = p2p.paymentMethod.isNotEmpty ? p2p.paymentMethod : 'GCash';
      final existingIndex = dTrans.indexWhere((d) {
        if (d['id'] == p2p.id ||
            d['depositRequestId'] == p2p.id ||
            d['id'] == 'p2p_dep_${p2p.id}' ||
            d['id'] == 'dep_${p2p.id}') {
          return true;
        }
        if (d['referenceNumber'] != null &&
            p2p.referenceNumber.isNotEmpty &&
            d['referenceNumber'] == p2p.referenceNumber) {
          return true;
        }
        // Match same amount P2P deposit within 15 minutes
        if (d['originRail'] == 'manual_p2p' &&
            ((d['amount'] as num).toDouble() - p2p.amount).abs() < 0.01) {
          final diff = ((d['timestamp'] as int) - p2p.createdAt).abs();
          if (diff < 15 * 60 * 1000) {
            return true;
          }
        }
        return false;
      });

      final existingProof = existingIndex >= 0 ? dTrans[existingIndex]['proofImageUrl'] as String? : null;
      final existingRef = existingIndex >= 0 ? dTrans[existingIndex]['referenceNumber'] as String? : null;
      final proofImg = p2p.proofImageUrl.isNotEmpty ? p2p.proofImageUrl : (existingProof ?? '');
      final refNum = p2p.referenceNumber.isNotEmpty ? p2p.referenceNumber : (existingRef ?? '');

      final cleanAgent = cleanAgentDisplayName((p2p.agentName?.isNotEmpty ?? false) ? p2p.agentName : p2p.adminUid);
      final isApproved = p2p.status == 'APPROVED' || p2p.status == 'COMPLETED';
      String p2pDesc;
      if (isCancelled) {
        p2pDesc = p2pStatus == 'REJECTED'
            ? 'P2P Top-Up request rejected by agent'
            : 'P2P Top-Up request cancelled';
      } else if (isApproved) {
        p2pDesc = refNum.isNotEmpty ? 'Reference #$refNum approved by $cleanAgent' : 'P2P Transfer approved by $cleanAgent';
      } else {
        p2pDesc = '$method P2P Top-Up';
      }

      final p2pTitle = isCancelled
          ? (p2pStatus == 'REJECTED' ? 'P2P Top-Up (Rejected)' : 'P2P Top-Up (Cancelled)')
          : 'P2P Top-Up ($method)';

      final p2pCategoryLabel = isCancelled
          ? (p2pStatus == 'REJECTED' ? 'Rejected' : 'Cancelled')
          : 'P2P Top-Up';

      final p2pMap = {
        'id': p2p.id,
        'depositRequestId': p2p.id,
        'title': p2pTitle,
        'desc': p2pDesc,
        'date': _formatDate(p2p.createdAt),
        'amount': p2p.amount,
        'originRail': 'manual_p2p',
        'method': method,
        'type': isCancelled ? 'cancelled' : 'credit',
        'category': isCancelled ? p2pStatus.toLowerCase() : 'topup',
        'categoryLabel': p2pCategoryLabel,
        'status': p2p.status,
        'referenceNumber': refNum,
        'proofImageUrl': proofImg,
        'agentName': cleanAgent,
        'agentAccountName': p2p.agentAccountName,
        'agentAccountNumber': p2p.agentAccountNumber,
        'agentQrUrl': p2p.agentQrUrl,
        'rejectionReason': p2p.rejectionReason,
        'createdAt': p2p.createdAt,
        'timestamp': p2p.createdAt,
      };

      if (existingIndex >= 0) {
        final prevStatus = (dTrans[existingIndex]['status'] as String? ?? '').toUpperCase();
        if (prevStatus == 'APPROVED' || prevStatus == 'COMPLETED' || prevStatus == 'SUCCESSFUL') {
          p2pMap['status'] = prevStatus;
        }
        dTrans[existingIndex] = p2pMap;
      } else {
        dTrans.add(p2pMap);
      }
    }

    earningsData['daily'] = dailyAgg.entries.map((e) => {'label': e.key, 'value': e.value}).toList();
    earningsData['weekly'] = weeklyAgg.entries.map((e) => {'label': e.key, 'value': e.value}).toList();
    earningsData['monthly'] = monthlyAgg.entries.map((e) => {'label': e.key, 'value': e.value}).toList();
    earningsData['yearly'] = yearlyAgg.entries.map((e) => {'label': e.key, 'value': e.value}).toList();

    // Sort descending by timestamp (latest first)
    eTrans.sort((t1, t2) => (t2['timestamp'] as int).compareTo(t1['timestamp'] as int));
    pTrans.sort((t1, t2) => (t2['timestamp'] as int).compareTo(t1['timestamp'] as int));
    dTrans.sort((t1, t2) => (t2['timestamp'] as int).compareTo(t1['timestamp'] as int));

    // ── BUILD UNIFIED TRANSACTION LEDGER ─────────────────────────────────────
    final unified = <Map<String, dynamic>>[];
    double inflowSum = 0.0;
    double outflowSum = 0.0;

    // 1. Inflows from Completed Earnings (Jobs, Vehicle Rentals, Property Rentals)
    for (final e in eTrans) {
      final amt = (e['amount'] as num).toDouble();
      inflowSum += amt;
      unified.add({
        'id': e['id'] ?? 'earn_${e['timestamp']}_${e['title'].hashCode}',
        'type': 'credit',
        'category': 'job_payout',
        'categoryLabel': 'Job & Gig Earning',
        'title': e['title'] ?? 'Earning Payout',
        'desc': e['desc'] ?? 'Completed contract payout',
        'date': e['date'] ?? _formatDate(e['timestamp'] as int?),
        'amount': amt,
        'status': e['status'] ?? 'Released',
        'method': e['method'] ?? 'Escrow Release',
        'timestamp': e['timestamp'] ?? 0,
        'baseAmount': e['baseAmount'],
        'commissionFee': e['commissionFee'],
        'holdbackAmount': e['holdbackAmount'],
        'listingFee': e['listingFee'],
        'kind': e['kind'],
        'isCompleted': true,
      });
    }

    // 2. Inflows from Deposits / Top-ups (Solana Crypto, GCash/Maya P2P) & Cancelled Items
    for (final d in dTrans) {
      final status = (d['status'] as String? ?? 'Completed').toUpperCase();
      final isCancelled = status == 'CANCELLED' || status == 'REJECTED' || d['type'] == 'cancelled';
      final amt = (d['amount'] as num).toDouble();
      final isCompleted = status == 'APPROVED' ||
          status == 'COMPLETED' ||
          status == 'RELEASED' ||
          status == 'SUCCESSFUL';
      if (isCompleted && !isCancelled) {
        inflowSum += amt;
      }
      final method = (d['method'] as String? ?? '').isNotEmpty
          ? (d['method'] as String)
          : (d['originRail'] == 'manual_p2p' ? 'GCash' : (d['originRail'] == 'mwa_on_chain' ? 'Solana' : 'Tyxbit Balance'));

      // If proofImageUrl is still empty, look up in userP2pDeposits
      var proofImg = (d['proofImageUrl'] as String? ?? '').trim();
      if (proofImg.isEmpty && d['originRail'] == 'manual_p2p') {
        final reqId = (d['depositRequestId'] as String? ?? d['id'] as String? ?? '').replaceAll('p2p_dep_', '').replaceAll('dep_', '');
        final matchedP2p = userP2pDeposits.where((p) =>
            p.id == reqId ||
            p.id == d['id'] ||
            (p.referenceNumber.isNotEmpty && p.referenceNumber == d['referenceNumber'])).firstOrNull;
        if (matchedP2p != null && matchedP2p.proofImageUrl.isNotEmpty) {
          proofImg = matchedP2p.proofImageUrl;
        }
      }

      final unifiedDesc = (d['desc'] as String? ?? 'Funds added to Tyxbit balance').replaceAllMapped(
        RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
        (m) => cleanAgentDisplayName(m.group(0)),
      );

      final categoryLabel = isCancelled
          ? (status == 'REJECTED' ? 'Rejected' : 'Cancelled')
          : (d['categoryLabel'] ?? (d['category'] == 'refund' ? 'Escrow Refund' : 'Added Funds'));

      unified.add({
        'id': d['id'] ?? 'dep_${d['timestamp']}_${d['title'].hashCode}',
        'depositRequestId': d['depositRequestId'],
        'type': isCancelled ? 'cancelled' : 'credit',
        'category': isCancelled ? status.toLowerCase() : (d['category'] ?? 'topup'),
        'categoryLabel': categoryLabel,
        'title': d['title'] ?? 'P2P Top-Up ($method)',
        'desc': unifiedDesc,
        'date': d['date'] ?? _formatDate(d['timestamp'] as int?),
        'amount': amt,
        'cryptoAmount': d['originRail'] == 'mwa_on_chain' ? d['cryptoAmount'] : null,
        'cryptoCurrency': d['originRail'] == 'mwa_on_chain' ? d['cryptoCurrency'] : null,
        'solanaTxSignature': d['originRail'] == 'mwa_on_chain' ? d['solanaTxSignature'] : null,
        'status': d['status'] ?? (isCancelled ? status : 'Completed'),
        'method': method,
        'originRail': d['originRail'],
        'referenceNumber': d['referenceNumber'],
        'proofImageUrl': proofImg,
        'agentName': d['agentName'],
        'agentAccountName': d['agentAccountName'],
        'agentAccountNumber': d['agentAccountNumber'],
        'agentQrUrl': d['agentQrUrl'],
        'rejectionReason': d['rejectionReason'],
        'createdAt': d['createdAt'] ?? d['timestamp'],
        'timestamp': d['timestamp'] ?? 0,
        'isCompleted': isCompleted && !isCancelled,
      });
    }

    // 3. Outflows from Purchases, Bookings, Subscriptions & Listing Fees
    for (final p in pTrans) {
      final amt = (p['amount'] as num).toDouble();
      outflowSum += amt;
      unified.add({
        'id': p['id'] ?? 'pur_${p['timestamp']}_${p['title'].hashCode}',
        'type': 'debit',
        'category': p['kind'] == 'listing_fee' ? 'fee' : (p['kind'] == 'service_fee' ? 'fee' : 'purchase'),
        'categoryLabel': p['kind'] == 'listing_fee' ? 'Listing Fee' : (p['kind'] == 'service_fee' ? 'Completion Fees' : (p['kind'] == 'subscription' ? 'Subscription' : 'Purchase / Booking')),
        'title': p['title'] ?? 'Payment',
        'desc': p['desc'] ?? 'Platform payment',
        'date': p['date'] ?? _formatDate(p['timestamp'] as int?),
        'amount': amt,
        'status': p['status'] ?? 'Successful',
        'method': p['method'] ?? 'Tyxbit Balance',
        'timestamp': p['timestamp'] ?? 0,
        'baseAmount': p['baseAmount'],
        'txFee': p['txFee'],
        'convFee': p['convFee'],
        'commissionFee': p['commissionFee'],
        'bookingFee': p['bookingFee'],
        'listingFee': p['listingFee'],
        'holdbackAmount': p['holdbackAmount'],
        'discountAmount': p['discountAmount'],
        'driverFee': p['driverFee'],
        'kind': p['kind'],
        'isCompleted': true,
      });
    }

    // 4. Outflows from Withdrawals / Payout Requests
    for (final w in userWithdrawalRequests) {
      final amt = (w['amount'] as num?)?.toDouble() ?? 0.0;
      final createdAt = (w['createdAt'] as num?)?.toInt() ?? 0;
      final method = w['payoutMethod'] ?? w['method'] ?? 'Bank Transfer';
      final status = w['status'] ?? 'PENDING';
      final isCompleted = status.toString().toUpperCase() == 'APPROVED' ||
          status.toString().toUpperCase() == 'COMPLETED';
      if (isCompleted) {
        outflowSum += amt;
      }
      unified.add({
        'id': w['id'] ?? 'with_${createdAt}',
        'type': 'debit',
        'category': 'withdrawal',
        'categoryLabel': 'Withdrawal / Payout',
        'title': 'Withdrawal ($method)',
        'desc': 'Disbursement to $method account',
        'date': _formatDate(createdAt),
        'amount': amt,
        'status': status,
        'method': method,
        'accountNumber': w['accountNumber'],
        'accountName': w['accountName'],
        'timestamp': createdAt,
        'isCompleted': isCompleted,
      });
    }

    // Deduplicate by composite key so identical topup/payout is never listed twice
    final seenKeys = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final item in unified) {
      String key;
      if (item['originRail'] == 'manual_p2p' || item['category'] == 'topup') {
        final ref = (item['referenceNumber'] as String? ?? '').trim();
        final reqId = (item['depositRequestId'] as String? ?? item['id'] as String? ?? '')
            .replaceAll('p2p_dep_', '')
            .replaceAll('dep_', '');
        if (ref.isNotEmpty) {
          key = 'p2p_ref_$ref';
        } else if (reqId.isNotEmpty) {
          key = 'p2p_req_$reqId';
        } else {
          key = 'p2p_${item['amount']}_${(item['timestamp'] as int) ~/ (10 * 60 * 1000)}';
        }
      } else {
        key = '${item['type']}_${item['category']}_${item['amount']}_${item['title']}_${(item['timestamp'] as int) ~/ (60 * 1000)}';
      }

      if (seenKeys.add(key)) {
        deduped.add(item);
      }
    }

    // Sort chronologically descending (latest first)
    deduped.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

    // Compute line-by-line running balance from current live tyxBalance
    final liveTyxBalance = component.state.userProfile?.tyxBalance ?? 0.0;
    double currentRunning = liveTyxBalance;

    for (int i = 0; i < deduped.length; i++) {
      final item = deduped[i];
      final isCompleted = item['isCompleted'] != false &&
          item['status'] != 'REJECTED' &&
          item['status'] != 'CANCELLED';

      item['runningBalance'] = currentRunning;

      // Reverse this transaction's effect to get the balance before it:
      if (isCompleted) {
        final amt = item['amount'] as double;
        if (item['type'] == 'credit') {
          currentRunning -= amt;
        } else {
          currentRunning += amt;
        }
        if (currentRunning < 0) currentRunning = 0.0;
      }
    }

    setState(() {
      earningsTransactions = eTrans;
      purchaseTransactions = pTrans;
      depositTransactions = dTrans;
      allUnifiedLedger = deduped;
      totalEarningsSum = earningsSum;
      totalInflowSum = inflowSum;
      totalOutflowSum = outflowSum;
      completedGigsCount = gigsCount;
    });
  }

  @override
  void initState() {
    super.initState();
    activeTab = 'all_transactions';
    _loadRentalHistory();
    component.state.loadUserProfile();
  }

  @override
  void didUpdateComponent(_HistoryView oldComponent) {
    super.didUpdateComponent(oldComponent);
    final profileTransitioned = oldComponent.state.userProfile == null && component.state.userProfile != null;
    if (profileTransitioned ||
        oldComponent.state.myJobs != component.state.myJobs ||
        oldComponent.state.userTransactions != component.state.userTransactions ||
        oldComponent.state.realtimeRentals != component.state.realtimeRentals) {
      _loadRentalHistory();
      if (!profileTransitioned) {
        component.state.loadUserProfile();
      }
    }
  }

  String formatCurrency(double val) {
    final parts = val.toStringAsFixed(2);
    final dotIndex = parts.indexOf('.');
    final integerPart = dotIndex != -1 ? parts.substring(0, dotIndex) : parts;
    final decimalPart = dotIndex != -1 ? parts.substring(dotIndex) : '';

    if (integerPart.length > 3) {
      final buffer = StringBuffer();
      final len = integerPart.length;
      for (int i = 0; i < len; i++) {
        buffer.write(integerPart[i]);
        final remaining = len - 1 - i;
        if (remaining > 0 && remaining % 3 == 0) {
          buffer.write(',');
        }
      }
      return '₱${buffer.toString()}$decimalPart';
    }
    return '₱$parts';
  }

  Component _buildBar(int i, Map<String, dynamic> item, double maxVal) {
    final val = (item['value'] as num).toDouble();
    final pct = maxVal > 0 ? (val / maxVal) * 100 : 0.0;
    final barHeight = pct < 8.0 ? 8.0 : pct;

    return div(
      classes: 'h-full flex-1 flex flex-col justify-end items-center group relative z-10',
      [
        // Tooltip
        div(
          classes:
              'absolute top-[-36px] opacity-0 scale-95 group-hover:opacity-100 group-hover:scale-100 transition-all duration-200 pointer-events-none z-20 bg-indigo-600 text-white text-[10px] sm:text-xs font-bold px-2.5 py-1.5 rounded-lg shadow-lg whitespace-nowrap',
          [
            Component.text('${item['label']}: ${formatCurrency(val)}'),
          ],
        ),
        div(
          classes:
              'w-8 sm:w-10 rounded-t-lg transition-all duration-300 logo-gradient hover:opacity-90 relative cursor-pointer',
          styles: Styles(
            raw: {
              'height': '${barHeight.toStringAsFixed(1)}%',
            },
          ),
          [],
        ),
        span(
          classes:
              'absolute bottom-[-24px] text-[10px] sm:text-xs font-bold ${component.state.isDark ? "text-zinc-500" : "text-zinc-400"} mt-2',
          [Component.text(item['label'] as String)],
        ),
      ],
    );
  }

  Component _buildTransactionHistoryShimmer(bool isDark, String cardCls) {
    final shimmerCls = isDark ? 'shimmer-dark' : 'shimmer-light';
    final bgPlaceholder = isDark ? 'bg-zinc-800/80' : 'bg-zinc-200/80';

    return div(classes: 'space-y-6 animate-fade-in', [
      // 1. TOP SUMMARY CARDS SHIMMER
      div(classes: 'grid grid-cols-1 sm:grid-cols-3 gap-4', [
        for (int i = 0; i < 3; i++)
          div(classes: 'p-5 rounded-[1.75rem] border $cardCls flex items-center justify-between', [
            div(classes: 'space-y-2 flex-1', [
              div(classes: 'h-3 w-28 rounded-md $bgPlaceholder $shimmerCls', []),
              div(classes: 'h-7 w-36 rounded-lg $bgPlaceholder $shimmerCls', []),
              div(classes: 'h-4 w-24 rounded-full $bgPlaceholder $shimmerCls', []),
            ]),
            div(classes: 'w-12 h-12 rounded-2xl $bgPlaceholder $shimmerCls flex-shrink-0 ml-3', []),
          ]),
      ]),

      // 2. FILTER PILLS SHIMMER
      div(classes: 'flex flex-wrap items-center justify-between gap-3', [
        div(classes: 'flex flex-wrap items-center gap-1.5', [
          for (final width in ['w-16', 'w-20', 'w-20', 'w-18', 'w-24', 'w-22', 'w-32'])
            div(classes: 'h-7 $width rounded-xl $bgPlaceholder $shimmerCls', []),
        ]),
        div(classes: 'h-3.5 w-64 rounded-md $bgPlaceholder $shimmerCls hidden sm:block', []),
      ]),

      // 3. TRANSACTION ROWS SHIMMER
      div(
        classes: 'rounded-[2rem] border overflow-hidden $cardCls divide-y ${isDark ? "divide-zinc-800" : "divide-zinc-200"}',
        [
          for (int i = 0; i < 6; i++)
            div(
              classes: 'p-5 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4',
              [
                div(classes: 'flex items-start gap-4 flex-1', [
                  // Icon placeholder
                  div(classes: 'w-11 h-11 rounded-2xl $bgPlaceholder $shimmerCls flex-shrink-0', []),
                  // Content lines
                  div(classes: 'space-y-2 flex-1', [
                    div(classes: 'flex items-center gap-2', [
                      div(classes: 'h-4.5 ${i % 2 == 0 ? "w-36" : "w-48"} rounded-md $bgPlaceholder $shimmerCls', []),
                      div(classes: 'h-4 w-16 rounded-full $bgPlaceholder $shimmerCls', []),
                      div(classes: 'h-4 w-12 rounded-full $bgPlaceholder $shimmerCls', []),
                    ]),
                    div(classes: 'h-3.5 ${i % 2 == 0 ? "w-64" : "w-52"} rounded-md $bgPlaceholder $shimmerCls', []),
                    div(classes: 'h-3 w-32 rounded-md $bgPlaceholder $shimmerCls', []),
                  ]),
                ]),
                // Right side: amount and status
                div(classes: 'flex sm:flex-col items-start sm:items-end justify-between w-full sm:w-auto gap-2', [
                  div(classes: 'h-5 w-24 rounded-md $bgPlaceholder $shimmerCls', []),
                  div(classes: 'h-4 w-28 rounded-lg $bgPlaceholder $shimmerCls', []),
                  div(classes: 'h-4 w-16 rounded-full $bgPlaceholder $shimmerCls', []),
                ]),
              ],
            ),
        ],
      ),
    ]);
  }

  Component _buildAllTransactionsLedger(bool isDark, TranyxAppState s, String cardCls) {
    if (_isLoading) {
      return _buildTransactionHistoryShimmer(isDark, cardCls);
    }

    final liveTyxBalance = s.userProfile?.tyxBalance ?? 0.0;

    // Filter transactions based on selected category pill
    final filtered = allUnifiedLedger.where((item) {
      if (ledgerFilter == 'all') return true;
      if (ledgerFilter == 'income') return item['type'] == 'credit';
      if (ledgerFilter == 'expenses') return item['type'] == 'debit';
      if (ledgerFilter == 'topups') return item['category'] == 'topup' || (item['type'] == 'credit' && item['category'] != 'job_payout');
      if (ledgerFilter == 'withdrawals') return item['category'] == 'withdrawal';
      if (ledgerFilter == 'jobs') return item['category'] == 'job_payout';
      if (ledgerFilter == 'purchases') return item['category'] == 'purchase' || item['category'] == 'fee';
      if (ledgerFilter == 'cancelled') return item['type'] == 'cancelled' || item['status'] == 'CANCELLED' || item['status'] == 'REJECTED';
      return true;
    }).toList();

    // Pagination calculations
    final totalItems = filtered.length;
    final totalPages = (totalItems / itemsPerPage).ceil().clamp(1, 999999);
    final safePage = currentPage.clamp(1, totalPages);
    final startIndex = (safePage - 1) * itemsPerPage;
    final endIndex = (startIndex + itemsPerPage).clamp(0, totalItems);
    final pagedTransactions = startIndex < totalItems
        ? filtered.sublist(startIndex, endIndex)
        : <Map<String, dynamic>>[];

    return div(classes: 'space-y-6', [
      // 1. TOP SUMMARY BANNER
      div(classes: 'grid grid-cols-1 sm:grid-cols-3 gap-4', [
        // Available Balance Card
        div(classes: 'p-5 rounded-[1.75rem] border $cardCls flex items-center justify-between', [
          div([
            span(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider', [
              Component.text('Wallet Available Balance'),
            ]),
            p(classes: 'text-2xl font-black ${isDark ? "text-white" : "text-zinc-900"} mt-1', [
              Component.text(formatCurrency(liveTyxBalance)),
            ]),
            span(classes: 'inline-block mt-1 text-[11px] font-semibold text-indigo-400 bg-indigo-500/10 px-2 py-0.5 rounded-full border border-indigo-500/20', [
              Component.text('Live Tyxbit Balance'),
            ]),
          ]),
          div(classes: 'w-12 h-12 rounded-2xl bg-indigo-500/10 flex items-center justify-center text-indigo-400', [
            lIcon('wallet', cls: 'w-6 h-6'),
          ]),
        ]),

        // Lifetime Inflow Card
        div(classes: 'p-5 rounded-[1.75rem] border $cardCls flex items-center justify-between', [
          div([
            span(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider', [
              Component.text('Total Inflows (+ Credits)'),
            ]),
            p(classes: 'text-2xl font-black text-emerald-400 mt-1', [
              Component.text('+ ${formatCurrency(totalInflowSum)}'),
            ]),
            span(classes: 'text-[11px] text-zinc-500 mt-1 block', [
              Component.text('Top-ups, Job & Rental Payouts'),
            ]),
          ]),
          div(classes: 'w-12 h-12 rounded-2xl bg-emerald-500/10 flex items-center justify-center text-emerald-400', [
            lIcon('arrow-down-left', cls: 'w-6 h-6'),
          ]),
        ]),

        // Lifetime Outflow Card
        div(classes: 'p-5 rounded-[1.75rem] border $cardCls flex items-center justify-between', [
          div([
            span(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider', [
              Component.text('Total Outflows (- Debits)'),
            ]),
            p(classes: 'text-2xl font-black text-rose-400 mt-1', [
              Component.text('- ${formatCurrency(totalOutflowSum)}'),
            ]),
            span(classes: 'text-[11px] text-zinc-500 mt-1 block', [
              Component.text('Purchases, Escrows & Withdrawals'),
            ]),
          ]),
          div(classes: 'w-12 h-12 rounded-2xl bg-rose-500/10 flex items-center justify-center text-rose-400', [
            lIcon('arrow-up-right', cls: 'w-6 h-6'),
          ]),
        ]),
      ]),

      // 2. FILTER PILLS BAR
      div(classes: 'flex flex-wrap items-center justify-between gap-3', [
        div(classes: 'flex flex-wrap items-center gap-1.5', [
          for (final filterOption in [
            {'id': 'all', 'label': 'All (${allUnifiedLedger.length})'},
            {'id': 'income', 'label': 'Income (+)'},
            {'id': 'expenses', 'label': 'Expenses (-)'},
            {'id': 'topups', 'label': 'Top-ups'},
            {'id': 'withdrawals', 'label': 'Withdrawals'},
            {'id': 'jobs', 'label': 'Job Payouts'},
            {'id': 'purchases', 'label': 'Purchases & Subscriptions'},
            {'id': 'cancelled', 'label': 'Cancelled / Rejected'},
          ])
            button(
              classes:
                  'px-3.5 py-1.5 rounded-xl text-xs font-bold transition-all cursor-pointer ${ledgerFilter == filterOption['id'] ? "bg-indigo-600 text-white shadow-md shadow-indigo-600/30" : "bg-zinc-800/80 hover:bg-zinc-800 text-zinc-400 hover:text-zinc-200 border border-zinc-700/60"}',
              events: {
                'click': (_) => setState(() {
                  ledgerFilter = filterOption['id']!;
                  currentPage = 1;
                })
              },
              [Component.text(filterOption['label']!)],
            ),
        ]),
        span(classes: 'text-xs text-zinc-500 font-medium', [
          Component.text('Chronological wallet ledger with running balance'),
        ]),
      ]),

      // 3. TRANSACTION LIST
      if (filtered.isEmpty)
        div(
          classes:
              'p-12 text-center rounded-[2rem] border border-dashed ${isDark ? "border-zinc-800" : "border-zinc-300"}',
          [
            div(classes: 'w-12 h-12 mx-auto mb-3 rounded-2xl bg-zinc-800/50 flex items-center justify-center text-zinc-500', [
              lIcon('wallet', cls: 'w-6 h-6'),
            ]),
            p(classes: 'text-sm font-bold ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
              Component.text('No transactions found in this category'),
            ]),
            p(classes: 'text-xs text-zinc-500 mt-1', [
              Component.text('Your top-ups, earnings, purchases, withdrawals, and cancelled requests will be displayed here.'),
            ]),
          ],
        )
      else ...[
        div(
          classes:
              'rounded-[2rem] border overflow-hidden $cardCls divide-y ${isDark ? "divide-zinc-800" : "divide-zinc-200"}',
          [
            for (final tx in pagedTransactions)
              () {
                final isTxCancelled = tx['type'] == 'cancelled' || tx['status'] == 'CANCELLED' || tx['status'] == 'REJECTED';
                final isTxRejected = tx['status'] == 'REJECTED';

                return div(
                  classes:
                      'p-5 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 hover:bg-zinc-500/5 transition-colors ${isTxCancelled ? "opacity-80" : ""}',
                  [
                    div(classes: 'flex items-start gap-4 flex-1', [
                      // Icon based on type (Cancelled vs Credit vs Debit)
                      div(
                        classes:
                            'w-11 h-11 rounded-2xl flex-shrink-0 flex items-center justify-center ${isTxCancelled ? "bg-rose-500/10 text-rose-400 border border-rose-500/20" : (tx['type'] == 'credit' ? "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20" : "bg-rose-500/10 text-rose-400 border border-rose-500/20")}',
                        [
                          lIcon(
                            isTxCancelled
                                ? (isTxRejected ? 'alert-triangle' : 'x-circle')
                                : (tx['type'] == 'credit'
                                    ? (tx['category'] == 'topup' ? 'arrow-down-left' : 'dollar-sign')
                                    : (tx['category'] == 'withdrawal' ? 'arrow-up-right' : 'shopping-bag')),
                            cls: 'w-5 h-5',
                          ),
                        ],
                      ),
                      div(classes: 'space-y-1 flex-1', [
                        div(classes: 'flex flex-wrap items-center gap-2', [
                          p(classes: 'font-bold text-sm ${isDark ? "text-zinc-100" : "text-zinc-800"} ${isTxCancelled ? "text-zinc-400" : ""}', [
                            Component.text(tx['title'] as String),
                          ]),
                          span(
                            classes:
                                'text-[10px] font-extrabold px-2 py-0.5 rounded-full ${isTxCancelled ? "bg-rose-500/15 text-rose-400 border border-rose-500/30" : (tx['type'] == 'credit' ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30" : "bg-zinc-800 text-zinc-300 border border-zinc-700")}',
                            [
                              Component.text(tx['categoryLabel'] as String),
                            ],
                          ),
                          if (tx['method'] != null && (tx['method'] as String).isNotEmpty)
                            span(
                              classes:
                                  'text-[10px] font-extrabold px-2 py-0.5 rounded-full ${tx['method'].toString().toLowerCase().contains('gcash') ? "bg-blue-500/15 text-blue-400 border border-blue-500/30" : (tx['method'].toString().toLowerCase().contains('maya') ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30" : (tx['method'].toString().toLowerCase().contains('solana') ? "bg-purple-500/15 text-purple-400 border border-purple-500/30" : "bg-indigo-500/10 text-indigo-400 border border-indigo-500/20"))}',
                              [
                                Component.text(tx['method'] as String),
                              ],
                            ),
                        ]),
                        p(classes: 'text-xs text-zinc-400', [
                          Component.text('${tx['desc']} • ${tx['date']}'),
                        ]),
                        if (tx['referenceNumber'] != null && (tx['referenceNumber'] as String).isNotEmpty)
                          div(classes: 'flex items-center gap-1.5 text-[11px] font-mono text-zinc-400 mt-1', [
                            span(classes: 'text-zinc-500 font-sans font-semibold', [Component.text('Ref:')]),
                            Component.text(tx['referenceNumber'] as String),
                          ]),
                        // Itemized Fee & Service Charge Breakdown Card
                        () {
                          final cat = tx['category'] as String?;
                          final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                          final base = (tx['baseAmount'] as num?)?.toDouble() ?? (tx['txFee'] != null ? (amt / 1.10) : (tx['commissionFee'] != null ? (amt / 0.97) : amt));
                          final txFee = (tx['txFee'] as num?)?.toDouble() ?? (tx['title'].toString().toLowerCase().contains('completion fee') ? base * 0.07 : null);
                          final convFee = (tx['convFee'] as num?)?.toDouble() ?? (tx['title'].toString().toLowerCase().contains('completion fee') ? base * 0.03 : null);
                          final commission = (tx['commissionFee'] as num?)?.toDouble() ?? (cat == 'earning' || cat == 'job_payout' ? base * 0.03 : null);
                          final serviceFee = (tx['serviceFeeAmount'] as num?)?.toDouble() ?? (tx['serviceFee'] as num?)?.toDouble();
                          final markup = (tx['markupAmount'] as num?)?.toDouble() ?? (tx['markup'] as num?)?.toDouble();
                          final bookingFee = (tx['bookingFee'] as num?)?.toDouble();
                          final listingFee = (tx['listingFee'] as num?)?.toDouble();
                          final holdback = (tx['holdbackAmount'] as num?)?.toDouble();
                          final driverFee = (tx['driverFee'] as num?)?.toDouble();

                          final txFeeRate = (tx['transactionFeeRate'] as num?)?.toDouble() ??
                              (tx['txFeeRate'] as num?)?.toDouble() ??
                              (txFee != null && base > 0 ? (txFee / base) : 0.07);
                          final convFeeRate = (tx['convenienceFeeRate'] as num?)?.toDouble() ??
                              (tx['convFeeRate'] as num?)?.toDouble() ??
                              (convFee != null && base > 0 ? (convFee / base) : 0.03);
                          final commissionRate = (tx['commissionRate'] as num?)?.toDouble() ??
                              (commission != null && base > 0 ? (commission / base) : 0.03);
                          final serviceFeeRate = (tx['serviceFeeRate'] as num?)?.toDouble() ??
                              (serviceFee != null && base > 0 ? (serviceFee / base) : 0.01);
                          final markupRate = (tx['markupRate'] as num?)?.toDouble() ??
                              (markup != null && base > 0 ? (markup / base) : 0.03);
                          final bookingFeeRate = (tx['bookingFeeRate'] as num?)?.toDouble() ??
                              (bookingFee != null && base > 0 ? (bookingFee / base) : 0.03);
                          final listingFeeRate = (tx['listingFeeRate'] as num?)?.toDouble() ?? 0.015;

                          final hasFees = txFee != null || convFee != null || commission != null || serviceFee != null || markup != null || bookingFee != null || listingFee != null || (holdback != null && holdback > 0) || (driverFee != null && driverFee > 0);

                          if (!hasFees && cat != 'refund' && cat != 'topup') {
                            return Component.empty();
                          }

                          return div(
                            classes: 'mt-2 p-3 rounded-xl ${isDark ? "bg-zinc-900/90 border border-zinc-800/80" : "bg-zinc-100/90 border border-zinc-200/80"} text-xs space-y-1.5 max-w-lg',
                            [
                              div(classes: 'flex items-center justify-between text-[10px] font-bold text-zinc-400 uppercase tracking-wider mb-1', [
                                span([Component.text('Itemized Fee Breakdown')]),
                                span(classes: 'text-indigo-400', [Component.text('Official Breakdown')]),
                              ]),
                              if (base > 0 && hasFees)
                                div(classes: 'flex justify-between text-zinc-400 text-[11px]', [
                                  span([Component.text('Base Contract / Rental Value:')]),
                                  span(classes: 'font-semibold ${isDark ? "text-zinc-200" : "text-zinc-700"}', [Component.text(formatCurrency(base))]),
                                ]),
                              if (txFee != null && txFee > 0)
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-zinc-400', [Component.text('Transaction Processing Fee (${PlatformFeeConfig.formatPercent(txFeeRate)}):')]),
                                  span(classes: 'font-semibold text-rose-400', [Component.text('+ ${formatCurrency(txFee)}')]),
                                ]),
                              if (convFee != null && convFee > 0)
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-zinc-400', [Component.text('Platform Convenience Fee (${PlatformFeeConfig.formatPercent(convFeeRate)}):')]),
                                  span(classes: 'font-semibold text-rose-400', [Component.text('+ ${formatCurrency(convFee)}')]),
                                ]),
                              if (serviceFee != null && serviceFee > 0)
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-zinc-400', [Component.text('Service Fee (${PlatformFeeConfig.formatPercent(serviceFeeRate)}):')]),
                                  span(classes: 'font-semibold text-rose-400', [Component.text('+ ${formatCurrency(serviceFee)}')]),
                                ]),
                              if (markup != null && markup > 0)
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-zinc-400', [Component.text('Markup (${PlatformFeeConfig.formatPercent(markupRate)}):')]),
                                  span(classes: 'font-semibold text-rose-400', [Component.text('+ ${formatCurrency(markup)}')]),
                                ]),
                              if (commission != null && commission > 0)
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-zinc-400', [Component.text('Platform Commission (${PlatformFeeConfig.formatPercent(commissionRate)}):')]),
                                  span(classes: 'font-semibold text-rose-400', [Component.text('− ${formatCurrency(commission)}')]),
                                ]),
                              if (bookingFee != null && bookingFee > 0)
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-zinc-400', [Component.text('Platform Booking Fee (${PlatformFeeConfig.formatPercent(bookingFeeRate)}):')]),
                                  span(classes: 'font-semibold text-rose-400', [Component.text('+ ${formatCurrency(bookingFee)}')]),
                                ]),
                              if (listingFee != null && listingFee > 0)
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-zinc-400', [Component.text('Listing Fee (${PlatformFeeConfig.formatPercent(listingFeeRate)} Upfront):')]),
                                  span(classes: 'font-semibold text-zinc-300', [Component.text(formatCurrency(listingFee))]),
                                ]),
                              if (driverFee != null && driverFee > 0)
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-zinc-400', [Component.text('Driver Services Add-on:')]),
                                  span(classes: 'font-semibold text-indigo-400', [Component.text('+ ${formatCurrency(driverFee)}')]),
                                ]),
                              if (holdback != null && holdback > 0)
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-amber-400', [Component.text('Inspection Holdback (10% - 48h):')]),
                                  span(classes: 'font-semibold text-amber-400', [Component.text('− ${formatCurrency(holdback)}')]),
                                ]),
                              if (cat == 'refund')
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-emerald-400', [Component.text('Full Escrow Refund:')]),
                                  span(classes: 'font-semibold text-emerald-400', [Component.text('100% Principal (0% Fee)')]),
                                ]),
                              if (cat == 'topup' && !hasFees)
                                div(classes: 'flex justify-between text-[11px]', [
                                  span(classes: 'text-emerald-400', [Component.text('Top-Up Processing:')]),
                                  span(classes: 'font-semibold text-emerald-400', [Component.text('0% Fee (Free)')]),
                                ]),
                            ],
                          );
                        }(),
                        // Proof of Receipt for P2P Transactions
                        if (tx['originRail'] == 'manual_p2p') ...[
                          () {
                            final proofUrl = tx['proofImageUrl'] as String?;
                            final hasProofImg = proofUrl != null && proofUrl.isNotEmpty;
                            final isCompleted = tx['isCompleted'] == true ||
                                tx['status'] == 'APPROVED' ||
                                tx['status'] == 'COMPLETED' ||
                                tx['status'] == 'SUCCESSFUL';

                            if (hasProofImg) {
                              return a(
                                href: proofUrl,
                                target: Target.blank,
                                classes:
                                    'inline-flex items-center gap-1.5 text-[11px] font-bold text-indigo-400 hover:text-indigo-300 transition-colors mt-1 mr-3',
                                [
                                  lIcon('receipt', cls: 'w-3.5 h-3.5 text-indigo-400'),
                                  Component.text('View Proof of Receipt'),
                                  lIcon('external-link', cls: 'w-3 h-3 text-indigo-400/70'),
                                ],
                              );
                            } else if (isCompleted) {
                              return a(
                                href: '#',
                                events: {
                                  'click': (e) {
                                    e.preventDefault();
                                    component.state.alertDialog(
                                      'P2P Transaction Receipt',
                                      'Transaction: ${tx['title']}\nMethod: ${tx['method']}\nAmount: ₱${(tx['amount'] as num).toDouble().toStringAsFixed(2)}\nReference: ${tx['referenceNumber'] ?? "Verified by Payment Agent"}\nStatus: Verified & Credited to Balance',
                                    );
                                  }
                                },
                                classes:
                                    'inline-flex items-center gap-1.5 text-[11px] font-bold text-indigo-400 hover:text-indigo-300 transition-colors mt-1 mr-3 cursor-pointer',
                                [
                                  lIcon('receipt', cls: 'w-3.5 h-3.5 text-indigo-400'),
                                  Component.text('View Proof of Receipt'),
                                ],
                              );
                            }
                            return Component.empty();
                          }(),
                        ] else if (tx['proofImageUrl'] != null && (tx['proofImageUrl'] as String).isNotEmpty) ...[
                          a(
                            href: tx['proofImageUrl'] as String,
                            target: Target.blank,
                            classes:
                                    'inline-flex items-center gap-1 text-[11px] font-bold text-indigo-400 hover:text-indigo-300 mt-1 mr-3',
                            [
                              lIcon('receipt', cls: 'w-3.5 h-3.5 text-indigo-400'),
                              Component.text('View Proof of Receipt'),
                              lIcon('external-link', cls: 'w-3 h-3'),
                            ],
                          ),
                        ],
                        // Prominent Rejection Reason Callout Banner
                        if (tx['rejectionReason'] != null && (tx['rejectionReason'] as String).trim().isNotEmpty)
                          div(
                            classes:
                                'mt-2 px-3 py-2 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-400 text-xs font-medium flex items-start gap-2 max-w-lg',
                            [
                              lIcon('alert-circle', cls: 'w-4 h-4 flex-shrink-0 text-rose-400 mt-0.5'),
                              div([
                                span(classes: 'font-bold mr-1', [Component.text('Rejection Reason:')]),
                                span([Component.text(tx['rejectionReason'] as String)]),
                              ]),
                            ],
                          ),
                        if (tx['originRail'] == 'mwa_on_chain' &&
                            tx['solanaTxSignature'] != null &&
                            (tx['solanaTxSignature'] as String).isNotEmpty &&
                            !tx['method'].toString().toLowerCase().contains('gcash') &&
                            !tx['method'].toString().toLowerCase().contains('maya'))
                          a(
                            href: WalletTransaction.getSolanaExplorerUrl(
                              signature: tx['solanaTxSignature'] as String,
                              environment: 'dev',
                            ),
                            target: Target.blank,
                            classes:
                                'inline-flex items-center gap-1 text-[11px] font-bold text-purple-400 hover:text-purple-300 mt-1',
                            [
                              Component.text('View on Solana Explorer'),
                              lIcon('external-link', cls: 'w-3 h-3'),
                            ],
                          ),

                        // 5-Minute Cancellation Action for Active P2P Deposits
                        if (tx['originRail'] == 'manual_p2p' &&
                            (tx['status'] == 'WAITING_FOR_AGENT' ||
                                tx['status'] == 'AWAITING_PAYMENT' ||
                                tx['status'] == 'PENDING_VERIFICATION')) ...[
                          () {
                            final now = DateTime.now().millisecondsSinceEpoch;
                            final createdAt = (tx['createdAt'] as num?)?.toInt() ?? (tx['timestamp'] as num?)?.toInt() ?? now;
                            final elapsedMs = now - createdAt;
                            final canCancel = elapsedMs >= 5 * 60 * 1000;
                            final remainingSec = canCancel ? 0 : (((5 * 60 * 1000) - elapsedMs) / 1000).ceil();
                            final remainMin = remainingSec ~/ 60;
                            final remainSec = remainingSec % 60;
                            final timeRemainingText = '${remainMin}m ${remainSec.toString().padLeft(2, '0')}s';
                            final reqId = tx['id'] as String? ?? '';

                            if (canCancel && reqId.isNotEmpty) {
                              return button(
                                classes:
                                    'mt-2 px-3 py-1.5 rounded-lg text-xs font-bold text-rose-400 hover:text-rose-300 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/30 transition cursor-pointer',
                                events: {
                                  'click': (_) async {
                                    await s.handleCancelP2pOrder(reqId);
                                    _loadRentalHistory();
                                  },
                                },
                                [
                                  div(classes: 'flex items-center gap-1.5', [
                                    lIcon('x-circle', cls: 'w-3.5 h-3.5'),
                                    Component.text('Cancel Request (5m Timeout Passed)'),
                                  ]),
                                ],
                              );
                            } else {
                              return span(
                                classes:
                                    'inline-block mt-2 px-2.5 py-1 rounded-md text-[10px] font-semibold text-zinc-500 bg-zinc-800/40 border border-zinc-800',
                                [
                                  Component.text('Cancel unlocks in $timeRemainingText if not credited'),
                                ],
                              );
                            }
                          }(),
                        ],
                      ]),
                    ]),

                    // Amount and Running Balance on Right
                    div(classes: 'text-left sm:text-right flex-shrink-0 space-y-1', [
                      if (isTxCancelled)
                        p(
                          classes: 'font-bold text-base text-zinc-500 line-through',
                          [
                            Component.text(formatCurrency((tx['amount'] as num).toDouble())),
                          ],
                        )
                      else
                        p(
                          classes:
                              'font-black text-base ${tx['type'] == 'credit' ? "text-emerald-400" : "text-rose-400"}',
                          [
                            Component.text(
                              '${tx['type'] == 'credit' ? "+" : "−"} ${formatCurrency((tx['amount'] as num).toDouble())}',
                            ),
                          ],
                        ),
                      // Running Balance Badge (for active/completed transactions)
                      if (!isTxCancelled)
                        div(classes: 'flex items-center sm:justify-end gap-1.5', [
                          span(
                            classes:
                                'text-[11px] font-bold px-2.5 py-0.5 rounded-lg ${isDark ? "bg-zinc-800/80 text-zinc-300 border border-zinc-700/60" : "bg-zinc-100 text-zinc-700 border border-zinc-200"}',
                            [
                              Component.text(
                                'Balance: ${formatCurrency((tx['runningBalance'] as num?)?.toDouble() ?? liveTyxBalance)}',
                              ),
                            ],
                          ),
                        ]),
                      if (tx['status'] != null)
                        span(
                          classes:
                              'inline-block text-[10px] font-bold px-2 py-0.5 rounded-full ${isTxCancelled ? "bg-rose-500/15 text-rose-400 border border-rose-500/30 font-extrabold uppercase" : (tx['status'] == 'Completed' || tx['status'] == 'Released' || tx['status'] == 'Successful' || tx['status'] == 'APPROVED' ? "bg-emerald-500/10 text-emerald-400" : (tx['status'] == 'PENDING' || tx['status'] == 'PENDING_VERIFICATION' ? "bg-amber-500/10 text-amber-400" : "bg-zinc-500/10 text-zinc-400"))}',
                          [
                            Component.text(tx['status'] as String),
                          ],
                        ),
                    ]),
                  ],
                );
              }(),
          ],
        ),

        // 4. PAGINATION CONTROLS
        if (totalItems > 0)
          div(
            classes:
                'p-4 rounded-[1.75rem] border $cardCls flex flex-col sm:flex-row items-center justify-between gap-4 mt-2 shadow-sm',
            [
              // Showing range and page size selector
              div(classes: 'flex flex-wrap items-center gap-3', [
                span(classes: 'text-xs text-zinc-400 font-medium flex items-center gap-1.5', [
                  Component.text('Showing'),
                  span(classes: 'font-bold ${isDark ? "text-white" : "text-zinc-900"}', [
                    Component.text('${totalItems == 0 ? 0 : startIndex + 1}–$endIndex'),
                  ]),
                  Component.text('of'),
                  span(classes: 'font-bold ${isDark ? "text-white" : "text-zinc-900"}', [
                    Component.text('$totalItems'),
                  ]),
                  Component.text('records'),
                ]),
                div(classes: 'flex items-center gap-1.5 text-xs text-zinc-500 font-medium', [
                  Component.text('• Per page:'),
                  for (final size in [10, 25, 50])
                    button(
                      classes:
                          'px-2 py-0.5 rounded-lg text-[11px] font-bold transition-all cursor-pointer ${itemsPerPage == size ? "bg-indigo-600 text-white shadow-sm" : "bg-zinc-800/60 hover:bg-zinc-800 text-zinc-400 hover:text-zinc-200 border border-zinc-700/60"}',
                      events: {
                        'click': (_) => setState(() {
                          itemsPerPage = size;
                          currentPage = 1;
                        })
                      },
                      [Component.text('$size')],
                    ),
                ]),
              ]),

              // Page navigation buttons
              if (totalPages > 1)
                div(classes: 'flex items-center gap-2', [
                  // Previous button
                  button(
                    classes:
                        'px-3 py-1.5 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 ${safePage > 1 ? "bg-zinc-800 hover:bg-zinc-700 text-white cursor-pointer border border-zinc-700" : "bg-zinc-800/40 text-zinc-600 border border-zinc-800/60 cursor-not-allowed"}',
                    events: safePage > 1
                        ? {'click': (_) => setState(() => currentPage = safePage - 1)}
                        : {},
                    [
                      lIcon('chevron-left', cls: 'w-4 h-4'),
                      Component.text('Previous'),
                    ],
                  ),

                  // Page numbers chips
                  div(classes: 'flex items-center gap-1', [
                    for (int p = 1; p <= totalPages; p++)
                      if (totalPages <= 7 ||
                          p == 1 ||
                          p == totalPages ||
                          (p >= safePage - 1 && p <= safePage + 1))
                        button(
                          classes:
                              'w-8 h-8 rounded-xl text-xs font-bold transition-all flex items-center justify-center cursor-pointer ${p == safePage ? "bg-indigo-600 text-white shadow-md shadow-indigo-600/30 font-black" : "bg-zinc-800/80 hover:bg-zinc-800 text-zinc-400 hover:text-white border border-zinc-700/60"}',
                          events: {'click': (_) => setState(() => currentPage = p)},
                          [Component.text('$p')],
                        )
                      else if (p == safePage - 2 || p == safePage + 2)
                        span(classes: 'w-5 text-center text-xs text-zinc-500 font-bold', [
                          Component.text('…'),
                        ]),
                  ]),

                  // Next button
                  button(
                    classes:
                        'px-3 py-1.5 rounded-xl text-xs font-bold transition-all flex items-center gap-1.5 ${safePage < totalPages ? "bg-indigo-600 hover:bg-indigo-500 text-white cursor-pointer shadow-md shadow-indigo-600/20" : "bg-zinc-800/40 text-zinc-600 border border-zinc-800/60 cursor-not-allowed"}',
                    events: safePage < totalPages
                        ? {'click': (_) => setState(() => currentPage = safePage + 1)}
                        : {},
                    [
                      Component.text('Next'),
                      lIcon('chevron-right', cls: 'w-4 h-4'),
                    ],
                  ),
                ]),
            ],
          ),
      ],
    ]);
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final showP2pAdmin = s.userProfile?.isAdmin == true || s.userProfile?.role == 'admin' || s.userProfile?.role == 'staff';
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    return div(classes: 'space-y-6', [
      div(classes: 'flex items-center justify-between gap-4 flex-wrap', [
        subViewHeader(
          title: activeTab == 'p2p_admin' ? 'P2P Desk & Admin' : 'Wallet Ledger & Transactions',
          isDark: isDark,
          onBack: () => s.setState(() => s.profileView = ProfileView.main),
        ),
        if (showP2pAdmin)
          button(
            classes:
                'px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-2 ${activeTab == 'p2p_admin' ? "bg-indigo-600 text-white shadow-md shadow-indigo-600/30" : "bg-zinc-800 text-zinc-300 hover:text-white border border-zinc-700"}',
            events: {'click': (_) => setState(() => activeTab = activeTab == 'p2p_admin' ? 'all_transactions' : 'p2p_admin')},
            [
              lIcon(activeTab == 'p2p_admin' ? 'wallet' : 'shield-check', cls: 'w-4 h-4 ${activeTab == 'p2p_admin' ? "text-white" : "text-emerald-400"}'),
              Component.text(activeTab == 'p2p_admin' ? 'Back to Wallet Ledger' : 'P2P Desk & Admin'),
              if (s.pendingDepositRequests.where((r) => r.status.toUpperCase() == 'PENDING_VERIFICATION').isNotEmpty)
                span(
                  classes:
                      'px-1.5 py-0.5 rounded-full text-[10px] font-bold bg-amber-500/20 text-amber-400 border border-amber-500/30',
                  [
                    Component.text(
                      '${s.pendingDepositRequests.where((r) => r.status.toUpperCase() == "PENDING_VERIFICATION").length}',
                    ),
                  ],
                ),
            ],
          ),
      ]),

      if (activeTab == 'p2p_admin' && showP2pAdmin)
        P2pAdminPanelComponent(state: s)
      else
        _buildAllTransactionsLedger(isDark, s, cardCls),
    ]);
  }
}

class _ReviewsView extends StatefulComponent {
  final TranyxAppState state;
  const _ReviewsView({required this.state});

  @override
  State<_ReviewsView> createState() => _ReviewsViewState();
}

class _ReviewsViewState extends State<_ReviewsView> {
  List<Map<String, dynamic>> reviews = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    if (token == null || uid == null) {
      setState(() {
        isLoading = false;
        errorMessage = 'Not logged in';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final svc = FirestoreService(token, component.state.handleTokenRefresh);
      final fetched = await svc.getReviews(uid);
      setState(() {
        reviews = fetched;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load reviews: $e';
        isLoading = false;
      });
    }
  }

  String _obfuscateName(String? name) {
    if (name == null || name.trim().isEmpty) return 'Anonymous';
    final parts = name.trim().split(' ');
    return parts
        .map((part) {
          if (part.isEmpty) return '';
          if (part.length == 1) return '${part[0]}***';
          return '${part[0]}***';
        })
        .join(' ');
  }

  String _formatDate(int? ms) {
    if (ms == null) return 'Unknown Date';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day.toString().padLeft(2, '0')}, ${dt.year}';
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    final textCls = isDark ? 'text-zinc-100' : 'text-zinc-800';
    final textMuted = isDark ? 'text-zinc-400' : 'text-zinc-500';

    final rating = s.userProfile?.rating;
    final ratingDisplay = rating != null ? rating.toStringAsFixed(1) : 'Unrated';
    final count = reviews.length;

    return div(classes: 'space-y-6', [
      // Header with Back arrow on mobile
      div(classes: 'flex items-center gap-3 md:gap-0', [
        button(
          classes:
              'md:hidden p-2 rounded-xl border ${isDark ? "border-zinc-800 text-zinc-300" : "border-zinc-200 text-zinc-600"}',
          events: {'click': (_) => s.setState(() => s.profileView = ProfileView.main)},
          [lIcon('arrow-left', cls: 'w-5 h-5')],
        ),
        h2(classes: 'text-2xl font-bold $textCls', [Component.text('Ratings & Reviews')]),
      ]),

      if (isLoading)
        div(classes: 'py-12 flex flex-col items-center justify-center gap-3', [
          div(classes: 'w-10 h-10 border-4 border-indigo-500 border-t-transparent rounded-full animate-spin', []),
          p(classes: 'text-sm $textMuted', [Component.text('Loading your reviews...')]),
        ])
      else if (errorMessage != null)
        div(classes: 'p-6 rounded-[2rem] border border-red-500/20 bg-red-500/5 text-center', [
          p(classes: 'text-red-400 font-medium', [Component.text(errorMessage!)]),
          button(
            classes:
                'mt-4 px-6 py-2 bg-zinc-800 hover:bg-zinc-700 text-white font-bold rounded-2xl text-xs transition-colors',
            events: {'click': (_) => _loadReviews()},
            [Component.text('Try Again')],
          ),
        ])
      else ...[
        // Summary Card
        div(classes: 'p-6 rounded-[2rem] border $cardCls flex flex-col sm:flex-row items-center gap-6 justify-between', [
          div(classes: 'flex items-center gap-4', [
            div(
              classes:
                  'w-16 h-16 rounded-2xl bg-amber-500/10 flex items-center justify-center text-amber-400 ${rating != null ? "text-3xl font-black" : "text-xs font-black"}',
              [
                Component.text(ratingDisplay),
              ],
            ),
            div([
              h3(classes: 'font-bold text-lg $textCls', [Component.text('Your Average Rating')]),
              div(classes: 'flex items-center gap-2 mt-1', [
                div(classes: 'flex text-amber-400 gap-0.5', [
                  for (int i = 1; i <= 5; i++)
                    lIcon(
                      'star',
                      cls: 'w-4 h-4 ${rating != null && i <= rating.round() ? "fill-amber-400 text-amber-400" : "text-zinc-600"}',
                    ),
                ]),
                span(classes: 'text-xs $textMuted', [
                  Component.text(count > 0 ? 'Based on $count ${count == 1 ? "review" : "reviews"}' : 'No reviews yet'),
                ]),
              ]),
            ]),
          ]),
          button(
            classes:
                'px-5 py-3 rounded-2xl border ${isDark ? "border-zinc-800 text-zinc-300 hover:bg-zinc-800" : "border-zinc-200 text-zinc-600 hover:bg-zinc-50"} font-bold text-sm transition-all',
            events: {'click': (_) => _loadReviews()},
            [Component.text('Refresh Reviews')],
          ),
        ]),

        // Review list header
        h3(classes: 'text-lg font-bold mt-8 $textCls', [
          Component.text('Recent Feedback'),
        ]),

        if (reviews.isEmpty)
          div(
            classes:
                'p-12 text-center rounded-[2rem] border border-dashed ${isDark ? "border-zinc-800" : "border-zinc-200"}',
            [
              div(
                classes:
                    'w-12 h-12 rounded-full bg-zinc-500/10 flex items-center justify-center text-zinc-400 mx-auto mb-4',
                [
                  lIcon('message-square', cls: 'w-6 h-6'),
                ],
              ),
              p(classes: 'font-bold $textCls', [Component.text('No reviews yet')]),
              p(classes: 'text-sm $textMuted mt-1', [
                Component.text('Completed gigs will show feedback here once rated.'),
              ]),
            ],
          )
        else
          div(classes: 'space-y-4', [
            for (final r in reviews)
              div(classes: 'p-6 rounded-[2rem] border $cardCls transition-all hover:translate-y-[-2px] hover:shadow-lg', [
                div(classes: 'flex items-start justify-between gap-4', [
                  div(classes: 'flex items-center gap-3', [
                    div(
                      classes:
                          'w-10 h-10 rounded-full bg-indigo-500/10 flex items-center justify-center font-bold text-indigo-400',
                      [
                        Component.text((r['reviewerName'] as String? ?? 'A')[0].toUpperCase()),
                      ],
                    ),
                    div([
                      p(classes: 'font-bold text-sm $textCls', [
                        Component.text(_obfuscateName(r['reviewerName'] as String?)),
                      ]),
                      p(classes: 'text-xs $textMuted mt-0.5', [
                        Component.text(_formatDate(r['timestamp'] as int?)),
                      ]),
                    ]),
                  ]),
                  // Score
                  div(classes: 'flex text-amber-400 gap-0.5', [
                    for (int i = 1; i <= 5; i++)
                      lIcon(
                        'star',
                        cls:
                            'w-4 h-4 ${i <= (r['score'] as int? ?? 0) ? "fill-amber-400 text-amber-400" : "text-zinc-600"}',
                      ),
                  ]),
                ]),
                if (r['comment'] != null && (r['comment'] as String).isNotEmpty)
                  p(classes: 'mt-4 text-sm leading-relaxed ${isDark ? "text-zinc-300" : "text-zinc-600"} italic', [
                    Component.text('"${r['comment']}"'),
                  ]),
              ]),
          ]),
      ],
    ]);
  }
}

class _RewardsView extends StatefulComponent {
  final TranyxAppState state;
  const _RewardsView({required this.state});

  @override
  State<_RewardsView> createState() => _RewardsViewState();
}

class _RewardsViewState extends State<_RewardsView> {
  List<Map<String, dynamic>> pointsHistory = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRewardsData();
  }

  Future<void> _loadRewardsData() async {
    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    if (token == null || uid == null) {
      setState(() {
        isLoading = false;
        errorMessage = 'Not logged in';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final svc = FirestoreService(token, component.state.handleTokenRefresh);
      // Automatically run verification to credit points if any quests are newly met
      await svc.checkAndAwardOnboardingQuests(uid);

      // Reload user profile to ensure state updates points in UI
      final updatedProfile = await svc.getUser(uid);
      if (updatedProfile != null) {
        component.state.userProfile = updatedProfile;
      }

      // Fetch history
      final history = await svc.getUserPointsHistory(uid);
      setState(() {
        pointsHistory = history;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to load rewards: $e';
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    final textCls = isDark ? 'text-zinc-100' : 'text-zinc-800';
    final subTextCls = isDark ? 'text-zinc-400' : 'text-zinc-500';

    final userPoints = s.userProfile?.terraPoints ?? 0;
    final earnedList = s.userProfile?.earnedRewards ?? const [];

    if (isLoading) {
      return div(classes: 'flex flex-col items-center justify-center p-12 space-y-4', [
        div(classes: 'animate-spin rounded-full h-10 w-10 border-t-2 border-indigo-650', []),
        p(classes: 'text-sm $subTextCls', [Component.text('Loading rewards dashboard...')]),
      ]);
    }

    if (errorMessage != null) {
      return div(classes: 'p-6 text-center border border-red-500/20 rounded-2xl bg-red-500/10 text-red-500', [
        p([Component.text(errorMessage!)]),
        button(
          onClick: _loadRewardsData,
          classes:
              'mt-3 px-4 py-2 bg-red-600 text-white rounded-xl text-xs font-bold hover:bg-red-700 transition-colors',
          [Component.text('Try Again')],
        ),
      ]);
    }

    return div(classes: 'space-y-6', [
      // Banner / Balance Section
      div(
        classes:
            'relative overflow-hidden rounded-3xl p-6 md:p-8 bg-gradient-to-r from-indigo-700 via-purple-700 to-indigo-800 text-white shadow-xl',
        [
          // Decorative graphics
          div(
            classes:
                'absolute top-0 right-0 w-64 h-64 bg-white/10 rounded-full blur-3xl transform translate-x-20 -translate-y-20',
            [],
          ),
          div(
            classes:
                'absolute bottom-0 left-0 w-48 h-48 bg-purple-500/20 rounded-full blur-2xl transform -translate-x-10 translate-y-10',
            [],
          ),

          div(classes: 'relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6', [
            div(classes: 'space-y-2', [
              span(
                classes:
                    'px-3 py-1 bg-white/15 backdrop-blur-md rounded-full text-xs font-black tracking-widest uppercase text-yellow-300 border border-white/10',
                [
                  Component.text('⭐ Terra Rewards Member'),
                ],
              ),
              h2(classes: 'text-3xl font-extrabold tracking-tight', [Component.text('Your Terra Points')]),
              p(classes: 'text-indigo-100 max-w-md text-sm', [
                Component.text(
                  'Earn TP by using the Tranyx ecosystem for payments, services, and property rentals. Redeem points for perks and discounts!',
                ),
              ]),
            ]),
            div(
              classes:
                  'flex items-center gap-4 bg-white/10 backdrop-blur-md border border-white/20 p-4 md:p-6 rounded-2xl shadow-inner min-w-[200px]',
              [
                div(
                  classes:
                      'p-3 bg-yellow-400 rounded-2xl text-zinc-900 text-2xl font-bold flex items-center justify-center shadow-lg',
                  [
                    Component.text('🪙'),
                  ],
                ),
                div(classes: 'flex flex-col', [
                  span(classes: 'text-3xl font-black tracking-tight text-yellow-300', [
                    Component.text(userPoints.toString()),
                  ]),
                  span(classes: 'text-[11px] font-bold text-indigo-200 uppercase tracking-wider', [
                    Component.text('TP Balance'),
                  ]),
                ]),
              ],
            ),
          ]),
        ],
      ),

      // Main grid: Quests vs History
      div(classes: 'grid grid-cols-1 lg:grid-cols-3 gap-6', [
        // Quests List (2 cols)
        div(classes: 'lg:col-span-2 space-y-6', [
          // Onboarding Quests
          _buildQuestSection(
            'Onboarding Milestones',
            RewardQuest.quests.where((q) => q.category == 'Onboarding').toList(),
            earnedList,
            isDark,
            cardCls,
            s,
          ),

          // Activity Quests
          _buildQuestSection(
            'Service Activities',
            RewardQuest.quests.where((q) => q.category == 'Services').toList(),
            earnedList,
            isDark,
            cardCls,
            s,
          ),

          // Rental Quests
          _buildQuestSection(
            'Rental Activities',
            RewardQuest.quests.where((q) => q.category == 'Rental').toList(),
            earnedList,
            isDark,
            cardCls,
            s,
          ),
        ]),

        // History Ledger (1 col)
        div(classes: 'space-y-4', [
          h3(classes: 'text-lg font-bold $textCls px-1', [Component.text('Points History')]),
          div(classes: 'rounded-2xl border p-4 $cardCls space-y-4 max-h-[600px] overflow-y-auto', [
            if (pointsHistory.isEmpty)
              div(classes: 'py-12 text-center text-sm $subTextCls', [
                span(classes: 'text-3xl block mb-2', [Component.text('📜')]),
                Component.text('No points transactions logged yet.'),
              ])
            else
              for (final tx in pointsHistory)
                div(
                  classes:
                      'flex items-center justify-between border-b pb-3 last:border-b-0 last:pb-0 ${isDark ? "border-zinc-800/80" : "border-zinc-150"}',
                  [
                    div(classes: 'space-y-1', [
                      p(classes: 'text-xs font-bold $textCls', [Component.text(tx['title'] ?? 'Points Reward')]),
                      p(classes: 'text-[10px] $subTextCls', [
                        Component.text(_formatTime(tx['createdAt'] as int?)),
                      ]),
                    ]),
                    span(
                      classes:
                          'px-2 py-0.5 bg-yellow-400/10 text-yellow-500 text-xs font-bold rounded-lg border border-yellow-400/20',
                      [
                        Component.text('+${tx['points']} TP'),
                      ],
                    ),
                  ],
                ),
          ]),
        ]),
      ]),
    ]);
  }

  Component _buildQuestSection(
    String title,
    List<RewardQuest> quests,
    List<String> earned,
    bool isDark,
    String cardCls,
    TranyxAppState s,
  ) {
    final textCls = isDark ? 'text-zinc-100' : 'text-zinc-800';
    final subTextCls = isDark ? 'text-zinc-400' : 'text-zinc-500';

    return div(classes: 'space-y-3', [
      h3(classes: 'text-lg font-extrabold $textCls px-1', [Component.text(title)]),
      div(classes: 'rounded-3xl border overflow-hidden $cardCls divide-y divide-zinc-200/50 dark:divide-zinc-800/50', [
        for (final q in quests) _buildQuestRow(q, earned.contains(q.id), isDark, subTextCls, textCls, s),
      ]),
    ]);
  }

  Component _buildQuestRow(
    RewardQuest q,
    bool isCompleted,
    bool isDark,
    String subTextCls,
    String textCls,
    TranyxAppState s,
  ) {
    final accountType = s.accountType;
    final isEmployerOnly = accountType == AccountType.employer;
    final isNyxianOnly = accountType == AccountType.nyxian;

    // Determine if this quest is locked due to account type
    // Quests only Employer + Hybrid can do (locked for Nyxian-only)
    const employerOnlyQuests = {'post_first_service', 'hire_applicant', 'employer_complete_transaction'};
    // Quests only Nyxian + Hybrid can do (locked for Employer-only)
    const nyxianOnlyQuests = {'add_skills_bio', 'apply_first_job', 'be_hired', 'jobseeker_complete_transaction'};

    final bool isLockedForEmployer = nyxianOnlyQuests.contains(q.id) && isEmployerOnly;
    final bool isLockedForNyxian = employerOnlyQuests.contains(q.id) && isNyxianOnly;
    final bool isLocked = isLockedForEmployer || isLockedForNyxian;

    // Determine if this is the deposit quest
    final bool isDepositQuest = q.id == 'deposit_any_amount';

    final String? lockNote = isLocked ? 'Become Hybrid to unlock this milestone' : null;

    // Map quest to its navigation action
    void Function()? onTap;
    if (!isLocked) {
      if (isDepositQuest && !isCompleted) {
        onTap = () => s.setState(() {
          s.profileView = ProfileView.payment;
          s.showDepositModal = true;
        });
      } else if (q.id == 'register_account' ||
          q.id == 'verify_account' ||
          q.id == 'complete_profile_trust' ||
          q.id == 'connect_solana_wallet') {
        onTap = () => s.setState(() => s.profileView = ProfileView.trust);
      } else if (q.id == 'subscribe_hybrid_pro') {
        onTap = () => s.setState(() => s.profileView = ProfileView.main);
      } else if (q.id == 'add_skills_bio') {
        onTap = () => s.setState(() => s.profileView = ProfileView.professional);
      } else if (q.category == 'Services') {
        onTap = () => s.setState(() => s.activeTab = AppTab.jobs);
      } else if (q.category == 'Rental') {
        onTap = () => s.setState(() => s.activeTab = AppTab.transit);
      }
    }

    return div(
      classes:
          'p-4 flex items-center justify-between gap-4 transition-colors ${isLocked ? "cursor-default" : "cursor-pointer hover:bg-zinc-50 dark:hover:bg-zinc-900/30"}',
      events: onTap != null ? {'click': (_) => onTap!()} : {},
      [
        // Left: quest info — dimmed when locked
        div(classes: 'flex-1 space-y-1 ${isLocked ? "opacity-50" : ""}', [
          div(classes: 'flex items-center gap-2', [
            span(classes: 'text-sm font-bold $textCls', [Component.text(q.title)]),
            if (isLocked)
              span(
                classes:
                    'px-1.5 py-0.5 bg-orange-500/10 text-orange-400 text-[9px] font-black uppercase rounded tracking-wider border border-orange-500/20',
                [
                  Component.text('🔒 Locked'),
                ],
              )
            else if (q.limit == 'Once')
              span(
                classes:
                    'px-1.5 py-0.5 bg-indigo-500/10 text-indigo-400 text-[9px] font-black uppercase rounded tracking-wider border border-indigo-500/20',
                [
                  Component.text('Once'),
                ],
              )
            else
              span(
                classes:
                    'px-1.5 py-0.5 bg-emerald-500/10 text-emerald-400 text-[9px] font-black uppercase rounded tracking-wider border border-emerald-500/20',
                [
                  Component.text('Repeatable'),
                ],
              ),
          ]),
          if (lockNote != null) p(classes: 'text-xs text-orange-400/80', [Component.text(lockNote)]),
        ]),

        // Right: action area — always full opacity so Subscribe Now is clickable
        div(classes: 'flex items-center gap-3 shrink-0', [
          if (!isLocked)
            span(classes: 'text-xs font-bold text-yellow-500 flex items-center gap-1', [
              Component.text('🪙 +${q.points} TP'),
            ])
          else
            span(classes: 'text-xs font-bold text-yellow-500/40 flex items-center gap-1', [
              Component.text('🪙 +${q.points} TP'),
            ]),
          if (isLocked)
            button(
              classes:
                  'inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-500/15 text-amber-400 border border-amber-500/30 shadow-sm hover:bg-amber-500/25 transition-colors cursor-pointer',
              events: {
                'click': (_) => s.setState(() {
                  s.profileView = ProfileView.subscription;
                }),
              },
              [Component.text('🔓 Subscribe Now')],
            )
          else if (isCompleted)
            span(
              classes:
                  'inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold bg-green-500/15 text-green-400 border border-green-500/20 shadow-sm',
              [
                Component.text('✓ Completed'),
              ],
            )
          else if (isDepositQuest)
            span(
              classes:
                  'inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold bg-indigo-500/15 text-indigo-400 border border-indigo-500/20 shadow-sm',
              [
                Component.text('→ Top Up'),
              ],
            )
          else
            span(
              classes:
                  'inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold bg-zinc-500/15 text-zinc-400 border border-zinc-500/20 shadow-sm',
              [
                Component.text('Pending'),
              ],
            ),
        ]),
      ],
    );
  }

  String _formatTime(int? ts) {
    if (ts == null) return 'Recent';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
