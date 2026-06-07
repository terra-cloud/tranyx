import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import '../../services/firebase_service.dart';
import '../../services/web_interop.dart';
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
      ProfileView.history => _HistoryView(state: s),
      ProfileView.reviews => _ReviewsView(state: s),
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

    final String historyLabel;
    switch (s.accountType) {
      case AccountType.employer:
        historyLabel = 'Purchase History';
        break;
      case AccountType.nyxian:
        final hasRentals = s.realtimeRentals.any((r) => r['renteeId'] == s.userProfile?.uid);
        final hasPayments = s.userTransactions.any((tx) => tx['type'] == 'payment');
        historyLabel = (hasRentals || hasPayments) ? 'History & Earnings' : 'Earning History';
        break;
      case AccountType.hybrid:
        historyLabel = 'History & Earnings';
        break;
    }

    final items = [
      (ProfileView.personal, 'user', 'Personal Information'),
      (ProfileView.professional, 'briefcase', 'Professional Info'),
      (ProfileView.payment, 'credit-card', 'Payment Methods'),
      (ProfileView.trust, 'shield-check', 'Trust & Verification'),
      (ProfileView.support, 'help-circle', 'Help & Support'),
      (ProfileView.history, 'activity', historyLabel),
      (ProfileView.reviews, 'star', 'Ratings & Reviews'),
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
          s.profileView = view;
          s.initializeProfileEditing();
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
            (s.userProfile?.rating ?? 0.0).toStringAsFixed(1),
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
            classes: 'p-4 rounded-2xl border text-center transition-all duration-300 group '
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
                      p(classes: 'text-[9px] text-amber-500 font-extrabold flex items-center justify-center gap-0.5 animate-pulse', [
                        lIcon('clock', cls: 'w-3 h-3'),
                        Component.text('+ ₱${pendingTotal.toStringAsFixed(2)} Pending'),
                      ]),
                      for (final holdback in s.pendingHoldbacks)
                        Builder(
                          builder: (context) {
                            final amt = (holdback['amount'] as num?)?.toDouble() ?? 0.0;
                            final relAt = holdback['releaseAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
                            final hrs = ((relAt - DateTime.now().millisecondsSinceEpoch) / (1000 * 60 * 60)).ceil();
                            final hrsStr = hrs <= 0 ? 'processing release' : 'releases in $hrs hr${hrs == 1 ? "" : "s"}';
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
                  classes: 'px-2 py-1 text-[10px] uppercase font-bold text-indigo-400 hover:text-indigo-300 border border-indigo-500/20 rounded-lg bg-indigo-500/5 transition-colors cursor-pointer',
                  events: {'click': (_) => s.setState(() => s.showDepositModal = true)},
                  [Component.text('Top Up')],
                ),
                button(
                  classes: 'px-2 py-1 text-[10px] uppercase font-bold text-emerald-400 hover:text-emerald-300 border border-emerald-500/20 rounded-lg bg-emerald-500/5 transition-colors cursor-pointer',
                  events: {'click': (_) => s.handleWithdrawTyx()},
                  [Component.text('Withdraw')],
                ),
              ]),
            ],
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

    final currentName = s.editName.isNotEmpty ? s.editName : (s.userProfile?.name ?? s.userName);
    final currentEmail = s.editEmail.isNotEmpty ? s.editEmail : (s.userProfile?.email ?? s.userEmail);
    final currentTaxId = s.editTaxId.isNotEmpty ? s.editTaxId : (s.userProfile?.taxId ?? '');

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
      div(classes: 'space-y-4', [
        inputField(
          label: 'Full Name',
          placeholder: 'Juan Dela Cruz',
          iconName: 'user-circle',
          isDark: s.isDark,
          value: currentName,
          onChange: (v) => s.setState(() => s.editName = v),
        ),
        inputField(
          label: 'Email Address',
          placeholder: 'juan@example.com',
          iconName: 'mail',
          type: 'email',
          isDark: s.isDark,
          value: currentEmail,
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
          value: s.formatTIN(currentTaxId),
          onChange: (v) {
            final digits = v.replaceAll(RegExp(r'\D'), '');
            final tin = digits.substring(0, digits.length > 12 ? 12 : digits.length);
            s.setState(() => s.editTaxId = tin);
          },
        ),
      ]),
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
    final isDark = s.isDark;
    final isNyxian = s.accountType == AccountType.nyxian || s.accountType == AccountType.hybrid;
    final isEmployer = s.accountType == AccountType.employer || s.accountType == AccountType.hybrid;
    final sectionCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    final currentHeadline = s.editHeadline.isNotEmpty ? s.editHeadline : (s.userProfile?.headline ?? '');
    final currentHourlyRate = s.editHourlyRate.isNotEmpty
        ? s.editHourlyRate
        : (s.userProfile?.hourlyRate?.toStringAsFixed(0) ?? '');
    final skills = s.editSkills.isNotEmpty ? s.editSkills : (s.userProfile?.skills ?? []);
    final currentBusinessName = s.editBusinessName.isNotEmpty
        ? s.editBusinessName
        : (s.userProfile?.businessName ?? '');
    final currentIndustry = s.editIndustry.isNotEmpty ? s.editIndustry : (s.userProfile?.industry ?? '');
    final currentTaxId = s.editTaxId.isNotEmpty ? s.editTaxId : (s.userProfile?.taxId ?? '');

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
            value: currentHeadline,
            onChange: (v) => s.setState(() => s.editHeadline = v),
          ),
          inputField(
            label: 'Hourly Rate (₱)',
            placeholder: '250',
            iconName: 'wallet',
            isDark: isDark,
            value: currentHourlyRate,
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
                      a(href: url, target: Target.blank, classes: 'text-indigo-400 hover:underline truncate max-w-[70%]', [
                        Component.text('Certificate Document ${s.userProfile!.certificationUrls!.indexOf(url) + 1}'),
                      ]),
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
            value: currentBusinessName,
            onChange: (v) => s.setState(() => s.editBusinessName = v),
          ),
          inputField(
            label: 'Industry',
            placeholder: 'Construction & Real Estate',
            iconName: 'briefcase',
            isDark: isDark,
            value: currentIndustry,
            onChange: (v) => s.setState(() => s.editIndustry = v),
          ),
          inputField(
            label: 'Tax ID / TIN (Philippines)',
            placeholder: '000-000-000-000',
            iconName: 'file-text',
            isDark: isDark,
            value: s.formatTIN(currentTaxId),
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
                      Component.text('In-app payments are held temporarily to protect users from incomplete jobs. Payouts release automatically after their inspection periods.'),
                    ]),
                    div(classes: 'space-y-1.5 pt-1.5 border-t border-amber-500/20', [
                      for (final holdback in s.pendingHoldbacks)
                        Builder(
                          builder: (context) {
                            final amt = (holdback['amount'] as num?)?.toDouble() ?? 0.0;
                            final relAt = holdback['releaseAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
                            final hrs = ((relAt - DateTime.now().millisecondsSinceEpoch) / (1000 * 60 * 60)).ceil();
                            final hrsStr = hrs <= 0 ? 'processing release' : 'releases in $hrs hr${hrs == 1 ? "" : "s"}';
                            return p(classes: 'text-[10px] text-amber-300 font-medium flex justify-between items-center', [
                              Component.text('• Php ${amt.toStringAsFixed(2)}'),
                              span(classes: 'text-[9px] px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-400 font-bold', [
                                Component.text(hrsStr),
                              ]),
                            ]);
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
    final walletName = s.selectedWalletType != null
        ? '${s.selectedWalletType!.substring(0, 1).toUpperCase()}${s.selectedWalletType!.substring(1)}'
        : 'Solana';

    Component getWalletIcon({String size = 'w-5 h-5'}) {
      if (s.selectedWalletType == 'phantom') return img(src: '/images/PhantomWallet.png', classes: '$size object-contain rounded-md');
      if (s.selectedWalletType == 'solflare') return img(src: '/images/Solflare.png', classes: '$size object-contain rounded-md');
      if (s.selectedWalletType == 'trust') return img(src: '/images/TrustWallet.jpeg', classes: '$size object-contain rounded-md');
      if (s.selectedWalletType == 'backpack') return img(src: '/images/BackPack.png', classes: '$size object-contain rounded-md');
      return lIcon('wallet', cls: '$size text-white');
    }

    if (s.walletState == WalletState.disconnected) {
      return div(classes: 'p-5 rounded-2xl border $cardCls', [
        div(classes: 'flex items-center justify-between', [
          div(classes: 'flex items-center gap-3', [
            div(classes: 'p-2.5 rounded-xl phantom-gradient', [
              getWalletIcon(size: 'w-5 h-5'),
            ]),
            div([
              p(classes: 'font-semibold', [Component.text('Solana Wallet')]),
              p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
                Component.text('Connect Phantom, Trust, Solflare, or Backpack'),
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
            getWalletIcon(size: 'w-5 h-5'),
          ]),
          div([
            p(classes: 'font-semibold', [Component.text('Connecting $walletName...')]),
            p(classes: 'text-xs ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
              Component.text('Please approve in your browser extension'),
            ]),
          ]),
          lIcon('loader-2', cls: 'w-5 h-5 ml-auto animate-spin ${isDark ? "text-zinc-500" : "text-zinc-400"}'),
        ]),
      ]);
    }

    // Connected
    final displayAddr = s.walletAddress.length > 8
        ? '${s.walletAddress.substring(0, 4)}...${s.walletAddress.substring(s.walletAddress.length - 4)}'
        : s.walletAddress;

    // Compile all assets to show in the list
    final assets = <Map<String, dynamic>>[];

    if (s.ethAddress.isNotEmpty) {
      assets.add({
        'symbol': 'ETH',
        'name': 'Ethereum',
        'address': s.ethAddress,
        'amount': s.ethBalance,
        'decimals': 4,
        'icon': 'coins',
        'color': 'purple',
      });
    }

    if (s.suiAddress.isNotEmpty) {
      assets.add({
        'symbol': 'SUI',
        'name': 'Sui',
        'address': s.suiAddress,
        'amount': s.suiBalance,
        'decimals': 2,
        'icon': 'coins',
        'color': 'blue',
      });
    }

    for (final t in s.walletCollectibles) {
      final mint = t['mint'] as String;
      final amount = t['amount'] as double;
      final decimals = t['decimals'] as int;
      final symVal = t['symbol'] as String?;
      final nameVal = t['name'] as String?;

      String symbol = (symVal != null && symVal.isNotEmpty) ? symVal : 'SPL Token';
      String name = (nameVal != null && nameVal.isNotEmpty) ? nameVal : symbol;
      String icon = 'coins';
      String color = 'zinc';

      if (mint == 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB') {
        symbol = 'USDT';
        name = 'USDT';
        icon = 'dollar-sign';
        color = 'green';
      } else if (mint == '2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo' || mint == 'CXk2AMBfi3TwaEL2468s6zP8xq9NxTXjp9gjMgzeUynM') {
        symbol = 'PYUSD';
        name = 'PYUSD';
        icon = 'dollar-sign';
        color = 'green';
      } else if (decimals == 0 && amount == 1) {
        symbol = 'NFT';
        name = 'NFT';
        icon = 'image';
        color = 'purple';
      }

      assets.add({
        'symbol': symbol,
        'name': name,
        'address': mint,
        'amount': amount,
        'decimals': decimals,
        'icon': icon,
        'color': color,
      });
    }

    return div(
      classes:
          'p-6 rounded-[2rem] border transition-all duration-300 '
          '${isDark ? "bg-[#18181b]/60 border-zinc-800/80 text-white" : "bg-white border-zinc-200 text-zinc-800 shadow-sm"} space-y-6',
      [
        div(classes: 'flex items-center justify-between', [
          div(classes: 'flex items-center gap-4', [
            div(
              classes:
                  'w-12 h-12 rounded-full bg-[#512da8] flex items-center justify-center text-white shadow-lg shadow-purple-500/20',
              [getWalletIcon(size: 'w-6 h-6')],
            ),
            div([
              p(classes: 'font-extrabold text-indigo-400 tracking-tight text-base', [Component.text('$walletName Wallet')]),
              p(classes: 'text-xs text-zinc-500 font-mono mt-0.5', [Component.text(displayAddr)]),
            ]),
          ]),
          button(
            classes:
                'p-2 rounded-xl text-zinc-400 hover:text-red-400 hover:bg-red-500/10 transition-all cursor-pointer',
            events: {
              'click': (_) => s.setState(() {
                s.walletState = WalletState.disconnected;
                s.walletAddress = '';
                s.walletBalance = 0;
                s.walletCollectibles = [];
                s.ethAddress = '';
                s.suiAddress = '';
                s.ethBalance = 0;
                s.suiBalance = 0;
              }),
            },
            [lIcon('log-out', cls: 'w-5 h-5')],
          ),
        ]),

        div(classes: 'flex items-end justify-between pt-1', [
          div([
            p(classes: 'text-[9px] font-black uppercase tracking-[0.2em] text-zinc-500 mb-1', [
              Component.text('Balance'),
            ]),
            p(
              classes:
                  'text-3xl font-black flex items-baseline gap-1.5 '
                  '${isDark ? "text-white" : "text-zinc-900"}',
              [
                Component.text(s.walletBalance.toStringAsFixed(2)),
                span(classes: 'text-xs font-black text-zinc-500 tracking-wider', [Component.text('SOL')]),
              ],
            ),
          ]),
          button(
            classes:
                'p-3 rounded-2xl transition-all flex items-center justify-center border shadow-sm '
                '${isDark ? "bg-zinc-800/80 border-zinc-700/60 hover:bg-zinc-800 text-zinc-300" : "bg-zinc-50 border-zinc-200 hover:bg-zinc-100 text-zinc-600"}',
            events: {'click': (_) => s.handleRefreshBalance()},
            [
              lIcon(
                s.isRefreshingBalance ? 'loader-2' : 'refresh-cw',
                cls: 'w-5 h-5 ${s.isRefreshingBalance ? "animate-spin" : ""}',
              ),
            ],
          ),
        ]),

        if (assets.isNotEmpty) ...[
          div(classes: 'border-t border-zinc-800/60 pt-4 mt-2 space-y-3', [
            p(classes: 'text-[9px] font-black uppercase tracking-[0.2em] text-zinc-500', [
              Component.text('Token Assets & Collectibles'),
            ]),
            div(
              classes: 'grid grid-cols-1 gap-2.5 max-h-56 overflow-y-auto pr-1 custom-scrollbar',
              assets.map((t) {
                final name = t['name'] as String;
                final addr = t['address'] as String;
                final shortAddr = addr.length > 8 ? '${addr.substring(0, 4)}...${addr.substring(addr.length - 4)}' : addr;
                final amount = t['amount'] as double;
                final decimals = t['decimals'] as int;
                final icon = t['icon'] as String;
                final color = t['color'] as String;

                String iconBgCls = 'bg-zinc-500/10 text-zinc-400';
                if (color == 'purple') {
                  iconBgCls = 'bg-purple-500/10 text-purple-400';
                } else if (color == 'blue') {
                  iconBgCls = 'bg-blue-500/10 text-blue-400';
                } else if (color == 'green') {
                  iconBgCls = 'bg-green-500/10 text-green-400';
                }

                return div(
                  classes: 'flex items-center justify-between p-3 rounded-2xl border ${isDark ? "bg-zinc-950/40 border-zinc-850" : "bg-zinc-50 border-zinc-200"}',
                  [
                    div(classes: 'flex items-center gap-3', [
                      div(
                        classes: 'w-8 h-8 rounded-xl $iconBgCls flex items-center justify-center',
                        [lIcon(icon, cls: 'w-4 h-4')],
                      ),
                      div([
                        p(classes: 'text-xs font-bold ${isDark ? "text-zinc-200" : "text-zinc-800"}', [Component.text(name)]),
                        p(classes: 'text-[10px] text-zinc-500 font-mono mt-0.5', [Component.text(shortAddr)]),
                      ]),
                    ]),
                    p(classes: 'text-xs font-black ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
                      Component.text(amount.toStringAsFixed(decimals == 0 ? 0 : decimals)),
                    ]),
                  ],
                );
              }).toList(),
            ),
          ]),
        ],
      ],
    );
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
                  '${displayStatus == "approved" ? "bg-green-500/10 text-green-400" : displayStatus == "pending" ? "bg-amber-500/10 text-amber-400" : displayStatus == "rejected" ? "bg-red-500/10 text-red-400" : "bg-zinc-500/10 text-zinc-400"}',
              [lIcon(displayStatus == "approved" ? 'check-circle' : displayStatus == "pending" ? 'clock' : displayStatus == "rejected" ? 'alert-circle' : 'circle', cls: 'w-5 h-5')],
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
            classes: 'mt-1 p-3 rounded-xl bg-red-500/5 border border-red-500/10 text-[10.5px] text-red-400 font-medium flex items-start gap-1.5',
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
    switch (type) {
      case AccountType.employer:
        return [
          {
            'title': 'How do I post a gig?',
            'icon': 'briefcase',
            'answer':
                'Navigate to the "Find Workers" tab or dashboard. Click the "Post a Gig" button to open the creation modal. Enter a catchy job title, choose a category, specify required skills, set the budget in Tyx, and complete the escrow. The gig will instantly become visible to qualified Nyxian workers!',
          },
          {
            'title': 'How does payment and Escrow work?',
            'icon': 'credit-card',
            'answer':
                'Tranyx utilizes a secure, trustless in-app Escrow system. When you post a job, the designated funds are safely held in a project escrow. Once the worker delivers their work and you review and approve it, the funds are instantly released to their wallet. No delayed payouts, no hidden fees.',
          },
          {
            'title': 'Why should I verify my TIN ID?',
            'icon': 'shield-check',
            'answer':
                'Verifying your Tax Identification Number (TIN) unlocks the "Verified Employer" status. This dramatically boosts worker trust, increases the visibility of your gig listings, and qualifies you for posting higher-tier contracts.',
          },
          {
            'title': 'How do I review and hire applicants?',
            'icon': 'users',
            'answer':
                'Under "Manage Jobs", click on your posted gig to view the active applicants. You can inspect their profile, reviews, and verified skills. Once you find the perfect match, click "Hire" to lock in the escrow and begin!',
          },
          {
            'title': 'How does the Escrow dispute system work?',
            'icon': 'alert-circle',
            'answer':
                'If a worker fails to deliver or the output does not meet your project specification, you can raise a dispute. Our decentralized moderation team will examine the deliverables and the agreement, settling the escrow fairly.',
          },
        ];
      case AccountType.nyxian:
        return [
          {
            'title': 'How do I apply for jobs?',
            'icon': 'briefcase',
            'answer':
                'Explore the active gig listings under "Find Jobs". When you find a gig matching your expertise, click "Apply Now". Present a brief proposal showing why you are the best fit. If the employer approves, they will hire you and the escrow goes active!',
          },
          {
            'title': 'How and when do I get paid?',
            'icon': 'credit-card',
            'answer':
                'Your payout is completely secured by our in-app Escrow. The moment you submit the gig deliverables and the employer approves them, the funds are instantly released from escrow directly into your virtual Tyx balance.',
          },
          {
            'title': 'What is the minimum withdrawal limit?',
            'icon': 'wallet',
            'answer':
                'To withdraw Tyx to your connected Solana or GCash wallet, a minimum balance of 100 Tyx is required. Withdrawals are processed safely through our payment bridge.',
          },
          {
            'title': 'How do I increase my profile rating?',
            'icon': 'star',
            'answer':
                'Completing jobs on time, communicating professionally, and delivering high-quality results will earn you stellar ratings (up to 5 stars). Higher ratings boost your visibility and make you a preferred choice for premium gigs!',
          },
          {
            'title': 'What are verified skills and how do I add them?',
            'icon': 'zap',
            'answer':
                'Go to your Profile and manage your skills list. Highlighting verified skills that match search criteria helps employers discover you automatically when searching for Nyxian professionals.',
          },
        ];
      case AccountType.hybrid:
        return [
          {
            'title': 'What is a Hybrid PRO account?',
            'icon': 'zap',
            'answer':
                'A Hybrid account gives you the ultimate flexibility to act as both an Employer (posting jobs) and a Nyxian Worker (applying for gigs) using a single, unified profile and balance!',
          },
          {
            'title': 'How do I switch between Employer and Worker views?',
            'icon': 'refresh-cw',
            'answer':
                'You can seamlessly toggle your active mode using the role selector in the dashboard or sidebar. This dynamically switches your views, custom tabs, and actions so you can hire or apply on the fly.',
          },
          {
            'title': 'Are my balance and ratings shared?',
            'icon': 'credit-card',
            'answer':
                'Yes! Your Tyx balance is shared across both roles, meaning you can immediately use earnings from your completed gigs to post new jobs. However, your rating system is split into "Employer Rating" and "Worker Rating" to represent your reputation in both roles accurately.',
          },
          {
            'title': 'Do I need to verify both profiles?',
            'icon': 'shield-check',
            'answer':
                'No, a single verification process validates your identity globally. Verifying your email, phone number, or TIN ID applies premium badges to both your Employer and Worker interfaces.',
          },
          {
            'title': 'How do fees work on a Hybrid account?',
            'icon': 'wallet',
            'answer':
                'Posting a gig as an employer locks in the escrow budget, while receiving payouts as a worker is subject to standard minimal network processing fees upon withdrawal.',
          },
        ];
    }
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
      'thank you', 'thanks', 'thank u', 'no more questions', 'no more question', 
      'no questions', "i'm good", 'im good', 'satisfied', 'all good', 'that is all', 
      'thats all', "that's all", 'nothing else', 'no need',
      'salamat', 'maraming salamat', 'wala na', 'ok na', 'okay na', 'ayos na', 
      'sapat na', 'walang anuman',
      'damo nga salamat', 'waray na', 'igo na', 'tolda na'
    ];
    final isTerminating = terminationKeywords.any((k) => cleanText.contains(k) || cleanText == k);

    if (isTerminating) {
      String partingMsg = "You're welcome! Glad I could help. Terminating the support session now. Have a great day!";
      if (cleanText.contains('damo') || cleanText.contains('waray na') || cleanText.contains('igo na')) {
        partingMsg = 'Waray anuman! Malipayon ako nga nakabulig. Awtomatiko ko na nga tatapuson ini nga chat. Maopay nga adlaw!';
      } else if (cleanText.contains('salamat') || cleanText.contains('wala na') || cleanText.contains('ok na') || cleanText.contains('okay na') || cleanText.contains('ayos na')) {
        partingMsg = 'Walang anuman! Masaya akong makatolong. Awtomatiko ko nang tatapusin ang chat na ito. Magandang araw!';
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
                'text': 'You have run out of free support questions. A new free question token will recover in $minutesLeft minutes. Other services like title, description, and cover note generation remain unlimited!',
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
      final response = await gemini.askSupportQuestion(history);

      // Successfully connected to server AI and got response!
      // Now decrement token if this was a new conversation.
      if (isNewConversation && tokensToUpdate != null && timestampToUpdate != null) {
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
        chatMessages.add({
          'isUser': false,
          'text': 'Oops, I hit a snag: $e. Please feel free to raise a support ticket below!',
          'time': 'Just now',
        });
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

      if (showChat) ...[
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
                      Component.text(supportTokens != null
                          ? 'Online Now • Tokens: ${supportTokens! % 1 == 0 ? supportTokens!.toInt() : supportTokens!.toStringAsFixed(1)}/5'
                          : 'Online Now'),
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
        div(classes: 'grid grid-cols-2 gap-4', [
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
              }
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
  String activeTab = 'earnings';
  String activeFilter = 'daily';
  int hoveredBarIndex = -1;

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

  List<Map<String, dynamic>> earningsTransactions = [];
  List<Map<String, dynamic>> purchaseTransactions = [];
  List<Map<String, dynamic>> depositTransactions = [];
  List<Map<String, dynamic>> _dbRentalHistory = [];
  double totalEarningsSum = 0.0;
  int completedGigsCount = 0;

  void _loadRentalHistory() async {
    final uid = component.state.userProfile?.uid;
    if (uid == null) return;
    try {
      final list = await component.state.firestore.getMyRentalHistory(uid);
      setState(() {
        _dbRentalHistory = list;
        _loadDbHistory();
      });
    } catch (e) {
      print('Error loading db rental history: $e');
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
          final payout = price * 0.95; // 5% host commission fee deducted
          earningsSum += payout;
          gigsCount++;
          eTrans.add({
            'title': title,
            'desc': 'Completed vehicle rental',
            'date': _formatDate(createdAtMs),
            'amount': payout,
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

    // Process DB Vehicle Rentals
    for (final rentalMap in _dbRentalHistory) {
      final rental = VehicleRental.fromMap(rentalMap, rentalMap['id'] ?? '');
      final creatorId = rental.hostId;
      final applicantId = rental.renteeId;
      final title = '${rental.year} ${rental.brand} ${rental.model}';
      final price = rental.totalCost ?? 0.0;
      final createdAtMs = rental.createdAt.millisecondsSinceEpoch;

      // If the user was the host -> earnings
      if (creatorId == uid) {
        final payout = price * 0.95; // 5% host commission fee deducted
        earningsSum += payout;
        gigsCount++;

        final alreadyAdded = eTrans.any((e) => e['timestamp'] == createdAtMs && e['title'] == title);
        if (!alreadyAdded) {
          eTrans.add({
            'title': title,
            'desc': 'Completed vehicle rental',
            'date': _formatDate(createdAtMs),
            'amount': payout,
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
        final alreadyAdded = pTrans.any((p) => p['timestamp'] == createdAtMs && p['title'] == title);
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
    }

    // Process userTransactions for deposits (or any other types)
    for (final tx in component.state.userTransactions) {
      final type = tx['type'] as String?;
      final createdAt = (tx['createdAt'] as num?)?.toInt();
      if (type == 'deposit') {
        dTrans.add({
          'title': tx['title'] ?? 'Top-Up',
          'desc': tx['desc'] ?? 'Deposit',
          'date': _formatDate(createdAt),
          'amount': (tx['amount'] as num?)?.toDouble() ?? 0.0,
          'method': tx['method'] ?? 'Unknown',
          'timestamp': createdAt ?? 0,
        });
      }
    }

    // Check if we have any dynamic earnings; if yes, overwrite the static graph data!
    final hasDynamicEarnings = eTrans.isNotEmpty;
    if (hasDynamicEarnings) {
      earningsData['daily'] = dailyAgg.entries.map((e) => {'label': e.key, 'value': e.value}).toList();
      earningsData['weekly'] = weeklyAgg.entries.map((e) => {'label': e.key, 'value': e.value}).toList();
      earningsData['monthly'] = monthlyAgg.entries.map((e) => {'label': e.key, 'value': e.value}).toList();
      earningsData['yearly'] = yearlyAgg.entries.map((e) => {'label': e.key, 'value': e.value}).toList();
    } else {
      // Restore fallback default mock data so it's not completely blank
      earningsData['daily'] = [
        {'label': 'Mon', 'value': 1200.0},
        {'label': 'Tue', 'value': 800.0},
        {'label': 'Wed', 'value': 1500.0},
        {'label': 'Thu', 'value': 2100.0},
        {'label': 'Fri', 'value': 950.0},
        {'label': 'Sat', 'value': 3000.0},
        {'label': 'Sun', 'value': 2400.0},
      ];
      earningsData['weekly'] = [
        {'label': 'Week 1', 'value': 8500.0},
        {'label': 'Week 2', 'value': 12000.0},
        {'label': 'Week 3', 'value': 9800.0},
        {'label': 'Week 4', 'value': 15400.0},
      ];
      earningsData['monthly'] = [
        {'label': 'Jan', 'value': 38000.0},
        {'label': 'Feb', 'value': 45000.0},
        {'label': 'Mar', 'value': 42000.0},
        {'label': 'Apr', 'value': 58000.0},
        {'label': 'May', 'value': 64000.0},
        {'label': 'Jun', 'value': 72000.0},
      ];
      earningsData['yearly'] = [
        {'label': '2024', 'value': 450000.0},
        {'label': '2025', 'value': 680000.0},
        {'label': '2026', 'value': 320000.0},
      ];
    }

    // Sort descending by timestamp (latest first)
    eTrans.sort((t1, t2) => (t2['timestamp'] as int).compareTo(t1['timestamp'] as int));
    pTrans.sort((t1, t2) => (t2['timestamp'] as int).compareTo(t1['timestamp'] as int));
    dTrans.sort((t1, t2) => (t2['timestamp'] as int).compareTo(t1['timestamp'] as int));

    setState(() {
      earningsTransactions = eTrans;
      purchaseTransactions = pTrans;
      depositTransactions = dTrans;
      totalEarningsSum = hasDynamicEarnings ? earningsSum : 19900.0;
      completedGigsCount = hasDynamicEarnings ? gigsCount : 4;
    });
  }

  @override
  void initState() {
    super.initState();
    final type = component.state.accountType;
    if (type == AccountType.employer) {
      activeTab = 'purchases';
    } else {
      activeTab = 'earnings';
    }
    _loadRentalHistory();
    component.state.loadUserProfile();
  }

  @override
  void didUpdateComponent(_HistoryView oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.state.myJobs != component.state.myJobs ||
        oldComponent.state.userTransactions != component.state.userTransactions ||
        oldComponent.state.realtimeRentals != component.state.realtimeRentals) {
      _loadRentalHistory();
      component.state.loadUserProfile();
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

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final type = s.accountType;

    final hasPurchaseHistory = purchaseTransactions.isNotEmpty;
    final showEarnings = true;
    final showPurchases =
        (type == AccountType.employer ||
        type == AccountType.hybrid ||
        (type == AccountType.nyxian && hasPurchaseHistory));
    final showDeposits =
        (type == AccountType.employer ||
        type == AccountType.hybrid ||
        (type == AccountType.nyxian && hasPurchaseHistory));

    final activeData = earningsData[activeFilter] ?? [];
    double totalEarnedInFilter = 0.0;
    double maxVal = 1.0;
    for (final item in activeData) {
      final v = (item['value'] as num).toDouble();
      totalEarnedInFilter += v;
      if (v > maxVal) maxVal = v;
    }

    final cardCls = isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm';

    return div(classes: 'space-y-6', [
      subViewHeader(
        title: type == AccountType.employer
            ? 'Purchase History'
            : ((type == AccountType.nyxian && !hasPurchaseHistory) ? 'Earning History' : 'History & Earnings'),
        isDark: isDark,
        onBack: () => s.setState(() => s.profileView = ProfileView.main),
      ),

      div(
        classes: 'flex border-b ${isDark ? "border-zinc-800" : "border-zinc-200"} gap-6',
        [
          if (showEarnings)
            button(
              classes:
                  'pb-3 text-sm font-bold transition-all border-b-2 '
                  '${activeTab == 'earnings' ? "border-indigo-500 text-indigo-400" : "border-transparent text-zinc-400 hover:text-zinc-200"}',
              events: {'click': (_) => setState(() => activeTab = 'earnings')},
              [Component.text('Earnings & Analytics')],
            ),
          if (showPurchases)
            button(
              classes:
                  'pb-3 text-sm font-bold transition-all border-b-2 '
                  '${activeTab == 'purchases' ? "border-indigo-500 text-indigo-400" : "border-transparent text-zinc-400 hover:text-zinc-200"}',
              events: {'click': (_) => setState(() => activeTab = 'purchases')},
              [Component.text('Subscriptions & Purchases')],
            ),
          if (showDeposits)
            button(
              classes:
                  'pb-3 text-sm font-bold transition-all border-b-2 '
                  '${activeTab == 'deposits' ? "border-indigo-500 text-indigo-400" : "border-transparent text-zinc-400 hover:text-zinc-200"}',
              events: {'click': (_) => setState(() => activeTab = 'deposits')},
              [Component.text('Added Funds')],
            ),
        ],
      ),

      if (activeTab == 'earnings' && showEarnings) ...[
        div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-4', [
          div(classes: 'p-6 rounded-[2rem] border $cardCls flex items-center gap-4', [
            div(classes: 'w-12 h-12 rounded-2xl bg-indigo-500/10 flex items-center justify-center text-indigo-400', [
              lIcon('dollar-sign', cls: 'w-6 h-6'),
            ]),
            div([
              span(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider', [
                Component.text(activeFilter == 'daily'
                    ? 'This Week\'s Earnings'
                    : activeFilter == 'weekly'
                        ? 'This Month\'s Earnings'
                        : activeFilter == 'monthly'
                            ? 'This Year\'s Earnings'
                            : 'Total Earnings'),
              ]),
              p(classes: 'text-2xl font-black mt-0.5 ${isDark ? "text-white" : "text-zinc-900"}', [
                Component.text(formatCurrency(totalEarnedInFilter)),
              ]),
            ]),
          ]),
          div(classes: 'p-6 rounded-[2rem] border $cardCls flex items-center gap-4', [
            div(classes: 'w-12 h-12 rounded-2xl bg-emerald-500/10 flex items-center justify-center text-emerald-400', [
              lIcon('wallet', cls: 'w-6 h-6'),
            ]),
            div([
              span(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider', [
                Component.text('Available TyxBalance'),
              ]),
              p(classes: 'text-2xl font-black mt-0.5 ${isDark ? "text-white" : "text-zinc-900"}', [
                Component.text(formatCurrency(s.userProfile?.tyxBalance ?? 0.0)),
              ]),
              Builder(
                builder: (context) {
                  final pendingTotal = s.pendingHoldbacks.fold<double>(0.0, (sum, item) {
                    final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
                    return sum + amt;
                  });
                  if (pendingTotal > 0) {
                    return div(classes: 'mt-1.5 space-y-1', [
                      span(classes: 'text-xs text-amber-500 font-bold flex items-center gap-1', [
                        lIcon('clock', cls: 'w-3.5 h-3.5'),
                        Component.text('+ ${formatCurrency(pendingTotal)} Pending Release'),
                      ]),
                      for (final holdback in s.pendingHoldbacks)
                        Builder(
                          builder: (context) {
                            final amt = (holdback['amount'] as num?)?.toDouble() ?? 0.0;
                            final relAt = holdback['releaseAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
                            final hrs = ((relAt - DateTime.now().millisecondsSinceEpoch) / (1000 * 60 * 60)).ceil();
                            final hrsStr = hrs <= 0 ? 'processing release' : 'releases in $hrs hr${hrs == 1 ? "" : "s"}';
                            return p(classes: 'text-[10px] text-amber-500/80 font-bold pl-4', [
                              Component.text('• Php ${amt.toStringAsFixed(2)} $hrsStr'),
                            ]);
                          },
                        ),
                    ]);
                  }
                  return div([]);
                },
              ),
            ]),
          ]),
          div(classes: 'p-6 rounded-[2rem] border $cardCls flex items-center gap-4', [
            div(classes: 'w-12 h-12 rounded-2xl bg-violet-500/10 flex items-center justify-center text-violet-400', [
              lIcon('check-circle', cls: 'w-6 h-6'),
            ]),
            div([
              span(classes: 'text-xs text-zinc-500 font-bold uppercase tracking-wider', [
                Component.text('Completed Jobs'),
              ]),
              p(classes: 'text-2xl font-black mt-0.5 ${isDark ? "text-white" : "text-zinc-900"}', [
                Component.text('$completedGigsCount Gigs'),
              ]),
            ]),
          ]),
        ]),

        div(classes: 'p-6 rounded-[2rem] border $cardCls space-y-6', [
          div(classes: 'flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4', [
            div([
              h4(classes: 'text-lg font-black tracking-tight ${isDark ? "text-zinc-150" : "text-zinc-800"}', [
                Component.text('Earnings Chart'),
              ]),
              p(classes: 'text-xs text-zinc-500 font-medium', [
                Component.text('Interactive visualization of your Nyxian revenue stream'),
              ]),
            ]),

            div(classes: 'flex gap-1.5 p-1 rounded-xl bg-zinc-950/20 border border-zinc-800/40', [
              for (final filter in ['daily', 'weekly', 'monthly', 'yearly'])
                button(
                  classes:
                      'px-3 py-1.5 text-xs font-bold rounded-lg transition-all '
                      '${activeFilter == filter ? "bg-indigo-600 text-white shadow-md" : "text-zinc-400 hover:text-zinc-200"}',
                  events: {'click': (_) => setState(() => activeFilter = filter)},
                  [Component.text(filter.substring(0, 1).toUpperCase() + filter.substring(1))],
                ),
            ]),
          ]),

          div(
            classes:
                'relative h-64 w-full flex items-end justify-between px-2 pt-8 pb-8 rounded-2xl bg-zinc-950/30 overflow-visible',
            [
              div(classes: 'absolute inset-x-0 bottom-8 top-4 flex flex-col justify-between pointer-events-none', [
                for (int grid = 0; grid < 4; grid++)
                  div(
                    classes:
                        'w-full border-b border-dashed ${isDark ? "border-zinc-900/80" : "border-zinc-200/50"} h-0',
                    [],
                  ),
              ]),

              for (int i = 0; i < activeData.length; i++) _buildBar(i, activeData[i], maxVal),
            ],
          ),

          div(
            classes:
                'flex justify-between items-center pt-2 text-xs font-bold text-zinc-500 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"}',
            [
              Component.text('Total in selected period:'),
              span(classes: '${isDark ? "text-white" : "text-zinc-800"} text-sm font-black', [
                Component.text(formatCurrency(totalEarnedInFilter)),
              ]),
            ],
          ),
        ]),

        div(classes: 'space-y-3', [
          p(classes: 'text-xs font-black uppercase tracking-[0.2em] opacity-60', [
            Component.text('Completed Gig Payouts'),
          ]),
          div(
            classes:
                'rounded-[2rem] border overflow-hidden $cardCls divide-y ${isDark ? "divide-zinc-800" : "divide-zinc-200"}',
            [
              for (final tx in earningsTransactions)
                div(classes: 'p-5 flex justify-between items-center hover:bg-zinc-500/5 transition-colors', [
                  div(classes: 'flex items-center gap-4', [
                    div(
                      classes:
                          'w-10 h-10 rounded-xl bg-emerald-500/10 flex items-center justify-center text-emerald-400',
                      [
                        lIcon('arrow-down-left', cls: 'w-5 h-5'),
                      ],
                    ),
                    div([
                      p(classes: 'font-bold text-sm ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
                        Component.text(tx['title'] as String),
                      ]),
                      p(classes: 'text-xs text-zinc-500 mt-0.5', [
                        Component.text('${tx['desc']} • ${tx['date']}'),
                      ]),
                      if (tx['commissionFee'] != null) ...[
                        p(classes: 'text-xs text-zinc-500 mt-1', [
                          Component.text('Base Payout: ${formatCurrency((tx['baseAmount'] as num).toDouble())}'),
                        ]),
                        p(classes: 'text-xs text-amber-500/80 mt-0.5', [
                          lIcon('receipt', cls: 'w-3 h-3 inline mr-0.5'),
                          Component.text(
                            'Platform Commission (3%): − ${formatCurrency((tx['commissionFee'] as num).toDouble())}',
                          ),
                        ]),
                      ],
                    ]),
                  ]),
                  div(classes: 'text-right', [
                    p(classes: 'font-black text-sm text-emerald-400', [
                      Component.text('+ ${formatCurrency((tx['amount'] as num).toDouble())}'),
                    ]),
                    span(
                      classes:
                          'inline-block mt-1 text-[10px] font-bold px-2 py-0.5 rounded bg-emerald-500/10 text-emerald-400',
                      [
                        Component.text(tx['status'] as String),
                      ],
                    ),
                  ]),
                ]),
            ],
          ),
        ]),
      ] else if (activeTab == 'purchases' && showPurchases) ...[
        div(classes: 'space-y-3', [
          p(classes: 'text-xs font-black uppercase tracking-[0.2em] opacity-60', [
            Component.text('Subscription & Platform Payments'),
          ]),
          div(
            classes:
                'rounded-[2rem] border overflow-hidden $cardCls divide-y ${isDark ? "divide-zinc-800" : "divide-zinc-200"}',
            [
              for (final tx in purchaseTransactions)
                div(classes: 'p-5 flex justify-between items-start hover:bg-zinc-500/5 transition-colors', [
                  div(classes: 'flex items-center gap-4', [
                    div(classes: 'w-10 h-10 rounded-xl bg-rose-500/10 flex items-center justify-center text-rose-400', [
                      lIcon('arrow-up-right', cls: 'w-5 h-5'),
                    ]),
                    div([
                      p(classes: 'font-bold text-sm ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
                        Component.text(tx['title'] as String),
                      ]),
                      p(classes: 'text-xs text-zinc-500 mt-0.5', [
                        Component.text('${tx['desc']} • ${tx['date']}'),
                      ]),
                      // Fee breakdown if available
                      if (tx['bookingFee'] != null) ...[
                        p(classes: 'text-xs text-zinc-500 mt-1', [
                          Component.text('Rental: ${formatCurrency((tx['baseAmount'] as num).toDouble())}'),
                        ]),
                        p(classes: 'text-xs text-amber-500/80 mt-0.5', [
                          lIcon('receipt', cls: 'w-3 h-3 inline mr-0.5'),
                          Component.text(
                            'Platform fee (3%): − ${formatCurrency((tx['bookingFee'] as num).toDouble())}',
                          ),
                        ]),
                      ],
                      if (tx['txFee'] != null) ...[
                        p(classes: 'text-xs text-zinc-500 mt-1', [
                          Component.text('Base Gig Price: ${formatCurrency((tx['baseAmount'] as num).toDouble())}'),
                        ]),
                        p(classes: 'text-xs text-amber-500/80 mt-0.5', [
                          lIcon('receipt', cls: 'w-3 h-3 inline mr-0.5'),
                          Component.text(
                            'Transaction Fee (7%): + ${formatCurrency((tx['txFee'] as num).toDouble())}',
                          ),
                        ]),
                        p(classes: 'text-xs text-amber-500/80 mt-0.5', [
                          lIcon('receipt', cls: 'w-3 h-3 inline mr-0.5'),
                          Component.text(
                            'Convenience Fee (3%): + ${formatCurrency((tx['convFee'] as num).toDouble())}',
                          ),
                        ]),
                      ],
                    ]),
                  ]),
                  div(classes: 'text-right', [
                    p(classes: 'font-black text-sm ${isDark ? "text-zinc-100" : "text-zinc-900"}', [
                      Component.text('− ${formatCurrency((tx['amount'] as num).toDouble())}'),
                    ]),
                    span(
                      classes:
                          'inline-block mt-1 text-[10px] font-bold px-2 py-0.5 rounded bg-indigo-500/10 text-indigo-400',
                      [
                        Component.text(tx['status'] as String),
                      ],
                    ),
                  ]),
                ]),
            ],
          ),
        ]),
      ] else if (activeTab == 'deposits' && showDeposits) ...[
        div(classes: 'space-y-3', [
          p(classes: 'text-xs font-black uppercase tracking-[0.2em] opacity-60', [
            Component.text('Top-Up & Deposit History'),
          ]),
          div(
            classes:
                'rounded-[2rem] border overflow-hidden $cardCls divide-y ${isDark ? "divide-zinc-800" : "divide-zinc-200"}',
            [
              for (final tx in depositTransactions)
                div(classes: 'p-5 flex justify-between items-center hover:bg-zinc-500/5 transition-colors', [
                  div(classes: 'flex items-center gap-4', [
                    div(
                      classes: 'w-10 h-10 rounded-xl bg-violet-500/10 flex items-center justify-center text-violet-400',
                      [
                        lIcon('plus-circle', cls: 'w-5 h-5'),
                      ],
                    ),
                    div([
                      p(classes: 'font-bold text-sm ${isDark ? "text-zinc-200" : "text-zinc-800"}', [
                        Component.text(tx['title'] as String),
                      ]),
                      p(classes: 'text-xs text-zinc-500 mt-0.5', [
                        Component.text('${tx['desc']} • ${tx['date']}'),
                      ]),
                    ]),
                  ]),
                  div(classes: 'text-right', [
                    p(classes: 'font-black text-sm text-indigo-400', [
                      Component.text('+ ${formatCurrency((tx['amount'] as num).toDouble())}'),
                    ]),
                    span(
                      classes:
                          'inline-block mt-1 text-[10px] font-bold px-2 py-0.5 rounded bg-violet-500/10 text-violet-400',
                      [
                        Component.text(tx['method'] as String),
                      ],
                    ),
                  ]),
                ]),
            ],
          ),
        ]),
      ],
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

    final rating = s.userProfile?.rating ?? 0.0;
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
        div(classes: 'p-6 rounded-3xl border border-red-500/20 bg-red-500/5 text-center', [
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
                  'w-16 h-16 rounded-2xl bg-amber-500/10 flex items-center justify-center text-amber-400 text-3xl font-black',
              [
                Component.text(rating.toStringAsFixed(1)),
              ],
            ),
            div([
              h3(classes: 'font-bold text-lg $textCls', [Component.text('Your Average Rating')]),
              div(classes: 'flex items-center gap-2 mt-1', [
                div(classes: 'flex text-amber-400 gap-0.5', [
                  for (int i = 1; i <= 5; i++)
                    lIcon(
                      'star',
                      cls: 'w-4 h-4 ${i <= rating.round() ? "fill-amber-400 text-amber-400" : "text-zinc-600"}',
                    ),
                ]),
                span(classes: 'text-xs $textMuted', [
                  Component.text('Based on $count ${count == 1 ? "review" : "reviews"}'),
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
