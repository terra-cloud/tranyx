import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
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
      ProfileView.trust => _TrustVerification(state: s),
      ProfileView.support => _HelpSupport(state: s),
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

    final items = [
      (ProfileView.personal, 'user', 'Personal Information'),
      (ProfileView.professional, 'briefcase', 'Professional Info'),
      (ProfileView.payment, 'credit-card', 'Payment Methods'),
      (ProfileView.trust, 'shield-check', 'Trust & Verification'),
      (ProfileView.support, 'help-circle', 'Help & Support'),
    ];

    return div(classes: 'rounded-3xl border p-4 $cardCls', [
      // Avatar + name header
      div(classes: 'p-4 text-center mb-4', [
        div(classes: 'relative inline-block mb-3', [
          div(
            classes:
                'w-20 h-20 rounded-full overflow-hidden gradient-border flex items-center justify-center bg-indigo-600/20',
            [
              if (s.userPhotoUrl != null)
                img(src: s.userPhotoUrl!, classes: 'w-full h-full object-cover')
              else
                span(classes: 'text-2xl font-bold text-indigo-400', [
                  Component.text(s.userName.isNotEmpty ? s.userName[0].toUpperCase() : '?'),
                ]),
            ],
          ),
        ]),
        p(classes: 'font-bold text-lg', [Component.text(s.userName.isNotEmpty ? s.userName : 'User')]),
        span(
          classes: 'inline-block px-3 py-1 rounded-md text-xs font-bold mt-1 ${s.accountType.badgeClasses}',
          [Component.text(s.accountType.label)],
        ),
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
      events: {'click': (_) => s.setState(() => s.profileView = view)},
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
class _ProfileMain extends StatelessComponent {
  final TranyxAppState state;
  const _ProfileMain({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    return div(classes: 'space-y-6', [
      h2(classes: 'text-2xl font-bold hidden md:block', [Component.text('Account Settings')]),

      // Stats row
      div(
        classes:
            'grid grid-cols-2 md:grid-cols-${s.accountType == AccountType.hybrid ? "4" : (s.accountType == AccountType.nyxian ? "3" : "2")} gap-4',
        [
          // Rating - Always shown
          _stat(
            (s.userProfile?.rating ?? 5.0).toStringAsFixed(1),
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

          // Earned - Shown for Nyxian and Hybrid
          if (s.accountType != AccountType.employer)
            _stat(
              '₱ ${(s.userProfile?.totalEarned ?? 0.0).toStringAsFixed(2)}',
              'Earned',
              'trending-up',
              'text-emerald-400',
              isDark,
            ),

          // Balance - Shown for Employer and Hybrid
          if (s.accountType != AccountType.nyxian)
            _stat(
              '₱ ${(s.userProfile?.tyxBalance ?? 0.0).toStringAsFixed(2)}',
              'Balance',
              'wallet',
              'text-blue-400',
              isDark,
              actionLabel: 'Top Up',
              onAction: (_) => s.setState(() => s.showDepositModal = true),
            ),
        ],
      ),

      // Upgrade to Hybrid PRO Banner
      if (s.accountType != AccountType.hybrid)
        div(
          classes:
              'p-5 rounded-2xl border flex flex-col md:flex-row items-center gap-4 border-amber-500/30 bg-amber-500/10',
          [
            div(classes: 'p-3 rounded-xl bg-amber-500/20 text-amber-500', [
              lIcon('crown', cls: 'w-6 h-6'),
            ]),
            div(classes: 'flex-1 text-center md:text-left', [
              p(classes: 'font-bold text-amber-500', [Component.text('Upgrade to Hybrid PRO')]),
              p(classes: 'text-sm mt-1 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                Component.text(
                  'Unlock the ability to both hire and work. Get the full Tranyx experience with an active subscription.',
                ),
              ]),
              if (s.profileSaveError != null)
                p(classes: 'text-xs text-red-400 mt-2 font-semibold', [Component.text(s.profileSaveError!)]),
            ]),
            button(
              classes:
                  'px-6 py-2.5 rounded-xl font-bold bg-amber-500 text-white shadow-lg hover:bg-amber-400 transition-colors',
              events: {
                'click': (_) {
                  s.setState(() {
                    s.profileSaveError = 'Hybrid PRO subscriptions are coming soon. Stay tuned!';
                  });
                },
              },
              [Component.text('Subscribe Now')],
            ),
          ],
        ),

      // Switch account type (dev helper)
      div(classes: 'p-5 rounded-2xl border $cardCls', [
        p(
          classes: 'text-xs font-semibold uppercase tracking-wider mb-3 ${isDark ? "text-zinc-500" : "text-zinc-400"}',
          [Component.text('Switch Account Type (Dev)')],
        ),
        div(classes: 'flex gap-2 flex-wrap', [
          for (final t in AccountType.values)
            button(
              classes:
                  'px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${s.accountType == t ? t.badgeClasses : (isDark ? "bg-zinc-800 text-zinc-400" : "bg-zinc-100 text-zinc-600")}',
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
    ]);
  }

  Component _stat(
    String value,
    String label,
    String icon,
    String iconCls,
    bool isDark, {
    String? actionLabel,
    void Function(Event)? onAction,
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
    return div(classes: 'space-y-6', [
      subViewHeader(
        title: 'Personal Information',
        isDark: s.isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),
      div(classes: 'space-y-4', [
        inputField(
          label: 'Full Name',
          placeholder: 'Alex Rivera',
          iconName: 'user-circle',
          isDark: s.isDark,
          value: s.userProfile?.name ?? s.userName,
          onChange: (v) => s.setState(() => s.editName = v),
        ),
        inputField(
          label: 'Email Address',
          placeholder: 'alex@example.com',
          iconName: 'mail',
          type: 'email',
          isDark: s.isDark,
          value: s.userProfile?.email ?? s.userEmail,
          onChange: (v) => s.setState(() => s.editEmail = v),
        ),
        inputField(
          label: 'Phone Number',
          placeholder: '+63 917 000 0000',
          iconName: 'phone',
          type: 'tel',
          isDark: s.isDark,
          value: s.userProfile?.phoneNumber ?? '',
          onChange: (v) => s.setState(() => s.editPhone = v),
        ),
      ]),
      if (s.profileSaveError != null)
        p(classes: 'text-sm text-red-400 text-center', [Component.text(s.profileSaveError!)]),
      button(
        classes:
            'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
        events: {'click': (_) => s.handleSavePersonalInfo()},
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
    final isDark = s.isDark;
    final isNyxian = s.accountType == AccountType.nyxian || s.accountType == AccountType.hybrid;
    final isEmployer = s.accountType == AccountType.employer || s.accountType == AccountType.hybrid;
    final sectionCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';
    final skills = s.editSkills.isNotEmpty ? s.editSkills : (s.userProfile?.skills ?? []);

    return div(classes: 'space-y-6', [
      subViewHeader(
        title: 'Professional Info',
        isDark: isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),

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
            value: s.editHeadline.isNotEmpty ? s.editHeadline : (s.userProfile?.headline ?? ''),
            onChange: (v) => s.setState(() => s.editHeadline = v),
          ),
          inputField(
            label: 'Hourly Rate (₱)',
            placeholder: '250',
            iconName: 'wallet',
            isDark: isDark,
            value: s.editHourlyRate.isNotEmpty
                ? s.editHourlyRate
                : (s.userProfile?.hourlyRate?.toStringAsFixed(0) ?? ''),
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
                  attributes: {'placeholder': '+ Add skill', 'value': s.newSkillInput},
                  events: {
                    'input': (e) {
                      // ignore: avoid_dynamic_calls
                      final v = (e as dynamic).target?.value as String? ?? '';
                      s.setState(() => s.newSkillInput = v);
                    },
                    'keydown': (e) {
                      // ignore: avoid_dynamic_calls
                      final key = (e as dynamic).key as String? ?? '';
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
            label: 'Company / Business Name',
            placeholder: 'Rivera Constructions',
            iconName: 'building',
            isDark: isDark,
            value: s.editBusinessName.isNotEmpty ? s.editBusinessName : (s.userProfile?.businessName ?? ''),
            onChange: (v) => s.setState(() => s.editBusinessName = v),
          ),
          inputField(
            label: 'Industry',
            placeholder: 'Construction & Real Estate',
            iconName: 'briefcase',
            isDark: isDark,
            value: s.editIndustry.isNotEmpty ? s.editIndustry : (s.userProfile?.industry ?? ''),
            onChange: (v) => s.setState(() => s.editIndustry = v),
          ),
          inputField(
            label: 'Tax ID / TIN',
            placeholder: '000-000-000-000',
            iconName: 'file-text',
            isDark: isDark,
            value: s.editTaxId.isNotEmpty ? s.editTaxId : (s.userProfile?.taxId ?? ''),
            onChange: (v) => s.setState(() => s.editTaxId = v),
          ),
        ]),
      ],

      if (s.profileSaveError != null)
        p(classes: 'text-sm text-red-400 text-center', [Component.text(s.profileSaveError!)]),
      button(
        classes:
            'w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
        events: {'click': (_) => s.handleSaveProfessionalInfo()},
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
                Component.text(s.walletBalance.toStringAsFixed(2)),
              ]),
              p(classes: 'text-xs opacity-60 mt-2 font-mono tracking-widest uppercase', [
                Component.text('tranyx-tyxbit-v1 :: ${s.userProfile?.uid.substring(0, 8) ?? "tx-9921"}'),
              ]),
            ]),

            div(classes: 'flex gap-3', [
              button(
                classes:
                    'flex-1 py-3.5 rounded-2xl bg-white/10 backdrop-blur-md border border-white/20 font-bold text-sm hover:bg-white/20 transition-all flex items-center justify-center gap-2',
                events: {'click': (_) => s.setState(() => s.showDepositModal = true)},
                [lIcon('arrow-down-left', cls: 'w-4 h-4'), Component.text('Deposit')],
              ),
              button(
                classes:
                    'flex-1 py-3.5 rounded-2xl bg-black/20 backdrop-blur-md border border-white/10 font-bold text-sm hover:bg-black/30 transition-all flex items-center justify-center gap-2',
                events: {'click': (_) => s.handleWithdrawTyx()},
                [
                  if (s.isSavingProfile) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                  lIcon('arrow-up-right', cls: 'w-4 h-4'),
                  Component.text(s.isSavingProfile ? 'Processing...' : 'Withdraw'),
                ],
              ),
            ]),
          ]),
        ],
      ),

      // Phantom wallet section
      _phantomWallet(s, isDark),

      // Add payment method
      button(
        classes:
            'w-full flex items-center justify-center gap-2 py-4 rounded-2xl border border-dashed ${isDark ? "border-zinc-700 text-zinc-500 hover:border-indigo-500 hover:text-indigo-400" : "border-zinc-300 text-zinc-400 hover:border-indigo-400"} transition-colors',
        events: {},
        [lIcon('plus', cls: 'w-5 h-5'), Component.text('  Add Payment Method')],
      ),
    ]);
  }

  Component _phantomWallet(TranyxAppState s, bool isDark) {
    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    if (s.walletState == WalletState.disconnected) {
      return div(classes: 'p-5 rounded-2xl border $cardCls', [
        div(classes: 'flex items-center justify-between', [
          div(classes: 'flex items-center gap-3', [
            div(classes: 'p-2.5 rounded-xl phantom-gradient', [
              lIcon('wallet', cls: 'w-5 h-5 text-white'),
            ]),
            div([
              p(classes: 'font-semibold', [Component.text('Phantom Wallet')]),
              p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
                Component.text('Connect your Solana wallet'),
              ]),
            ]),
          ]),
          button(
            classes:
                'px-4 py-2.5 rounded-xl text-sm font-bold text-white phantom-gradient hover:opacity-90 transition-opacity',
            events: {'click': (_) => s.handleConnectWallet()},
            [Component.text('Connect')],
          ),
        ]),
      ]);
    }

    if (s.walletState == WalletState.connecting) {
      return div(classes: 'p-5 rounded-2xl border $cardCls', [
        div(classes: 'flex items-center gap-3', [
          div(classes: 'p-2.5 rounded-xl phantom-gradient animate-pulse', [
            lIcon('wallet', cls: 'w-5 h-5 text-white'),
          ]),
          div([
            p(classes: 'font-semibold', [Component.text('Connecting Phantom...')]),
            p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
              Component.text('Please approve in your browser extension'),
            ]),
          ]),
          lIcon('loader-2', cls: 'w-5 h-5 ml-auto animate-spin ${isDark ? "text-zinc-500" : "text-zinc-400"}'),
        ]),
      ]);
    }

    // Connected
    return div(classes: 'p-5 rounded-2xl border border-purple-500/30 bg-purple-500/10', [
      div(classes: 'flex items-center justify-between mb-3', [
        div(classes: 'flex items-center gap-3', [
          div(classes: 'p-2.5 rounded-xl phantom-gradient', [
            lIcon('wallet', cls: 'w-5 h-5 text-white'),
          ]),
          div([
            p(classes: 'font-semibold text-purple-300', [Component.text('Phantom Connected')]),
            p(classes: 'text-xs text-purple-400 font-mono', [Component.text(s.walletAddress)]),
          ]),
        ]),
        span(classes: 'px-2 py-0.5 rounded text-[10px] font-bold bg-purple-500/20 text-purple-300', [
          Component.text('SOL'),
        ]),
      ]),
      div(classes: 'flex items-center justify-between', [
        div([
          p(classes: 'text-xs text-purple-400', [Component.text('Balance')]),
          p(classes: 'text-2xl font-bold text-purple-200', [
            Component.text('${s.walletBalance.toStringAsFixed(2)} SOL'),
          ]),
        ]),
        div(classes: 'flex gap-2', [
          button(
            classes: 'p-2.5 rounded-xl bg-purple-500/20 text-purple-300 hover:bg-purple-500/30 transition-colors',
            events: {'click': (_) => s.handleRefreshBalance()},
            [
              lIcon(
                s.isRefreshingBalance ? 'loader-2' : 'refresh-cw',
                cls: 'w-4 h-4 ${s.isRefreshingBalance ? "animate-spin" : ""}',
              ),
            ],
          ),
          button(
            classes: 'p-2.5 rounded-xl bg-red-500/10 text-red-400 hover:bg-red-500/20 transition-colors',
            events: {
              'click': (_) => s.setState(() {
                s.walletState = WalletState.disconnected;
                s.walletAddress = '';
                s.walletBalance = 0;
              }),
            },
            [lIcon('log-out', cls: 'w-4 h-4')],
          ),
        ]),
      ]),
    ]);
  }
}

// ── Trust & Verification ──────────────────────────────────────
class _TrustVerification extends StatelessComponent {
  final TranyxAppState state;
  const _TrustVerification({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    return div(classes: 'space-y-6', [
      subViewHeader(
        title: 'Trust & Verification',
        isDark: isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),
      div(
        classes:
            'p-5 rounded-2xl border ${isDark ? "bg-zinc-900 border-zinc-800" : "bg-white border-zinc-200"} text-center',
        [
          lIcon('shield-check', cls: 'w-10 h-10 text-green-400 mx-auto mb-2'),
          p(classes: 'font-bold text-lg', [Component.text('Identity Verification')]),
          p(classes: 'text-sm ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
            Component.text('Complete verification to unlock all features'),
          ]),
        ],
      ),
      div(classes: 'space-y-3', [
        verificationItem(title: 'Government ID', status: 'Verified', isDark: isDark),
        verificationItem(title: 'Phone Number', status: 'Verified', isDark: isDark),
        verificationItem(title: 'Email Address', status: 'Verified', isDark: isDark),
        verificationItem(title: 'Background Check', status: 'Pending', isDark: isDark),
      ]),
    ]);
  }
}

// ── Help & Support ────────────────────────────────────────────
class _HelpSupport extends StatelessComponent {
  final TranyxAppState state;
  const _HelpSupport({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    return div(classes: 'space-y-6', [
      subViewHeader(
        title: 'Help & Support',
        isDark: isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),
      button(
        classes:
            'w-full flex items-center justify-center gap-3 py-4 rounded-2xl logo-gradient text-white font-semibold hover:opacity-90 transition-opacity',
        events: {},
        [lIcon('message-square', cls: 'w-5 h-5'), Component.text(' Start Live Chat')],
      ),
      div(classes: 'space-y-3', [
        supportFaq(title: 'How do I post a job?', iconName: 'briefcase', isDark: isDark),
        supportFaq(title: 'How does payment work?', iconName: 'credit-card', isDark: isDark),
        supportFaq(title: 'How do I verify my identity?', iconName: 'shield-check', isDark: isDark),
        supportFaq(title: 'What is a Nyxian Worker?', iconName: 'zap', isDark: isDark),
        supportFaq(title: 'How to dispute a transaction?', iconName: 'alert-circle', isDark: isDark),
      ]),
    ]);
  }
}
