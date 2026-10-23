import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';
import 'package:shared/shared.dart';

class AuthViewComponent extends StatelessComponent {
  final TranyxAppState state;
  const AuthViewComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    return switch (s.authView) {
      AuthView.login => _LoginScreen(state: s),
      AuthView.registerPath => _RegisterPathScreen(state: s),
      AuthView.registerDetails => _RegisterDetailsScreen(state: s),
      AuthView.kycPending => _KycPendingScreen(state: s),
    };
  }
}

// ── Login Screen ──────────────────────────────────────────────
class _LoginScreen extends StatefulComponent {
  final TranyxAppState state;
  const _LoginScreen({required this.state});

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  String _email = '';
  String _password = '';
  String? _localError;
  String? _localInfo;
  bool _showForgotSent = false;
  bool _showPassword = false;

  @override
  // ignore: invalid_use_of_protected_member
  void setState(void Function() fn) => super.setState(fn);

  Component _featureRow(String iconSrc, String label) {
    return div(classes: 'flex gap-3 items-center', [
      div(
        classes: 'bg-[#eef2ff] flex items-center justify-center rounded-[10px] shrink-0 size-9',
        [
          img(
            src: iconSrc,
            classes: 'size-[18px]',
            attributes: {'alt': '', 'aria-hidden': 'true'},
          ),
        ],
      ),
      p(
        classes: 'font-semibold leading-[22px] text-[15px] text-[#18181b] m-0',
        [Component.text(label)],
      ),
    ]);
  }

  Component _w01Field({
    required String label,
    required String placeholder,
    required String iconSrc,
    required String value,
    required void Function(String) onChange,
    String type = 'text',
    bool isPassword = false,
    bool isPasswordVisible = false,
    void Function()? onTogglePassword,
  }) {
    final inputId = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return div(classes: 'flex flex-col gap-1.5 items-start w-full', [
      p(
        classes: 'font-semibold leading-5 text-sm text-[#18181b] tracking-[0.1px] m-0',
        [Component.text(label)],
      ),
      div(
        classes:
            'bg-white border border-[#d4d4d8] flex gap-2.5 h-12 items-center px-3.5 relative rounded-xl w-full focus-within:border-[#4f46e5]',
        [
          img(
            src: iconSrc,
            classes: 'size-[18px] shrink-0',
            attributes: {'alt': '', 'aria-hidden': 'true'},
          ),
          input<String>(
            classes:
                'bg-transparent border-none outline-none flex-1 min-w-0 text-[15px] leading-[22px] text-[#18181b] placeholder:text-[#71717a]',
            type: (isPassword && isPasswordVisible)
                ? InputType.text
                : (type == 'password'
                    ? InputType.password
                    : (type == 'email' ? InputType.email : InputType.text)),
            value: value,
            attributes: {
              'placeholder': placeholder,
              'value': value,
              'id': inputId,
              'name': inputId,
              'autocomplete': isPassword ? 'current-password' : 'email',
            },
            onInput: onChange,
          ),
          if (isPassword && onTogglePassword != null)
            button(
              classes:
                  'p-0 bg-transparent border-0 cursor-pointer shrink-0 flex items-center justify-center size-[18px]',
              events: {'click': (_) => onTogglePassword()},
              attributes: {'type': 'button', 'aria-label': isPasswordVisible ? 'Hide password' : 'Show password'},
              [
                img(
                  src: '/images/w01/932ea.svg',
                  classes: 'size-[18px]',
                  attributes: {'alt': '', 'aria-hidden': 'true'},
                ),
              ],
            ),
        ],
      ),
    ]);
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final errorMsg = _localError ?? s.authError;

    return div(
      classes: 'w01-signin flex w-full min-h-screen items-stretch bg-[#f4f4f5] font-dm-sans',
      [
        // Left brand panel
        div(
          classes:
              'hidden lg:flex relative w-[680px] shrink-0 flex-col justify-between overflow-hidden bg-white px-[72px] py-16',
          [
            // Gradient blobs
            img(
              src: '/images/w01/05633.svg',
              classes: 'pointer-events-none absolute left-[-60px] top-[380px] size-[420px] max-w-none',
              attributes: {'alt': '', 'aria-hidden': 'true'},
            ),
            img(
              src: '/images/w01/54cd1.svg',
              classes: 'pointer-events-none absolute left-[360px] top-[120px] size-[300px] max-w-none',
              attributes: {'alt': '', 'aria-hidden': 'true'},
            ),
            img(
              src: '/images/w01/1a12a.svg',
              classes: 'pointer-events-none absolute left-[300px] top-[640px] size-[260px] max-w-none',
              attributes: {'alt': '', 'aria-hidden': 'true'},
            ),
            // Logo
            div(classes: 'relative z-10 flex items-center', [
              img(
                src: '/images/w01/fef74.png',
                classes: 'h-10 w-[51px] object-contain',
                attributes: {'alt': 'Tranyx'},
              ),
            ]),
            // Headline + features
            div(classes: 'relative z-10 flex flex-col gap-5 items-start', [
              div(classes: 'font-bold text-[48px] leading-[56px] tracking-[-1.2px] text-[#18181b]', [
                p(classes: 'm-0', [Component.text('Work. Earn. Rent.')]),
                p(classes: 'm-0', [Component.text('Discover.')]),
              ]),
              p(
                classes: 'm-0 font-normal text-base leading-6 text-[#52525b] w-full max-w-[480px]',
                [
                  Component.text(
                    'Find freelance gigs, rent vehicles and properties, and earn securely on the all-in-one P2P platform. Powered by Web3 escrow and verified Nyxians in the Philippines.',
                  ),
                ],
              ),
              div(classes: 'flex flex-col gap-3 items-start pt-2', [
                _featureRow('/images/w01/c1457.svg', 'Freelance gigs near you'),
                _featureRow('/images/w01/a193d.svg', 'Vehicle & space rentals'),
                _featureRow('/images/w01/d726a.svg', 'Escrow-protected payments'),
              ]),
            ]),
            p(
              classes:
                  'relative z-10 m-0 font-semibold text-[11px] leading-4 tracking-[0.8px] text-[#52525b] uppercase',
              [Component.text('One Platform. Endless Opportunities.')],
            ),
          ],
        ),

        // Right form side
        div(
          classes: 'flex flex-1 flex-col gap-6 items-center justify-center min-w-0 px-6 sm:px-12 py-10',
          [
            div(
              classes:
                  'bg-white border border-[#e4e4e7] flex flex-col gap-4 items-start p-8 relative rounded-3xl shadow-[0px_8px_24px_-4px_rgba(9,9,11,0.08)] w-full max-w-[440px]',
              [
                div(classes: 'flex flex-col gap-1 items-start', [
                  p(
                    classes: 'm-0 font-bold text-2xl leading-8 tracking-[-0.4px] text-[#18181b]',
                    [Component.text('Sign In')],
                  ),
                  p(
                    classes: 'm-0 font-normal text-sm leading-5 text-[#52525b]',
                    [Component.text('Welcome back to Tranyx.')],
                  ),
                ]),

                if (errorMsg != null)
                  div(
                    key: Key('error-msg'),
                    classes: 'w-full p-3 rounded-xl bg-red-500/10 border border-red-500/30 text-red-600 text-sm',
                    [Component.text(errorMsg)],
                  ),

                if (_localInfo != null)
                  div(
                    classes: 'w-full p-3 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-indigo-700 text-sm',
                    [Component.text(_localInfo!)],
                  ),

                if (_showForgotSent)
                  div(
                    key: Key('forgot-sent'),
                    classes: 'w-full p-3 rounded-xl bg-green-500/10 border border-green-500/30 text-green-700 text-sm',
                    [Component.text('Password reset email sent! Check your inbox.')],
                  ),

                _w01Field(
                  label: 'Email',
                  placeholder: 'you@example.com',
                  iconSrc: '/images/w01/b7212.svg',
                  type: 'email',
                  value: _email,
                  onChange: (v) => setState(() => _email = v),
                ),
                _w01Field(
                  label: 'Password',
                  placeholder: '••••••••',
                  iconSrc: '/images/w01/a5857.svg',
                  type: 'password',
                  value: _password,
                  onChange: (v) => setState(() => _password = v),
                  isPassword: true,
                  isPasswordVisible: _showPassword,
                  onTogglePassword: () => setState(() => _showPassword = !_showPassword),
                ),

                div(key: Key('forgot-pwd-btn'), classes: 'flex items-center justify-end w-full', [
                  button(
                    classes:
                        'font-semibold text-sm leading-5 tracking-[0.1px] text-[#4f46e5] bg-transparent border-0 cursor-pointer p-0 hover:underline',
                    attributes: {'type': 'button'},
                    events: {
                      'click': (_) async {
                        if (_email.isEmpty) {
                          setState(() {
                            _localError = 'Enter your email to reset password.';
                            _localInfo = null;
                          });
                          return;
                        }
                        setState(() {
                          _localError = null;
                          _localInfo = null;
                        });
                        await s.handleForgotPassword(_email);
                        setState(() => _showForgotSent = true);
                      },
                    },
                    [Component.text('Forgot password?')],
                  ),
                ]),

                button(
                  key: Key('signin-btn'),
                  classes:
                      'w-full h-12 rounded-xl font-semibold text-sm tracking-[0.1px] text-white bg-[#4f46e5] shadow-[0px_8px_10px_rgba(79,70,229,0.25)] hover:opacity-90 transition-opacity flex items-center justify-center gap-2 border-0 cursor-pointer',
                  attributes: {'type': 'button'},
                  events: {
                    'click': (_) async {
                      if (_email.isEmpty || _password.isEmpty) {
                        setState(() {
                          _localError = 'Please fill in all fields.';
                          _localInfo = null;
                        });
                        return;
                      }
                      setState(() {
                        _localError = null;
                        _localInfo = null;
                      });
                      await s.handleSignIn(_email, _password);
                    },
                  },
                  [
                    if (s.isAuthLoading) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                    Component.text(s.isAuthLoading ? ' Signing in...' : 'Sign In'),
                  ],
                ),

                div(key: Key('divider'), classes: 'flex gap-3 items-center w-full', [
                  div(classes: 'flex-1 h-px bg-[#e4e4e7]', []),
                  span(
                    classes: 'font-medium text-xs leading-4 text-[#71717a]',
                    [Component.text('or continue with')],
                  ),
                  div(classes: 'flex-1 h-px bg-[#e4e4e7]', []),
                ]),

                div(classes: 'flex gap-3 items-center w-full', [
                  button(
                    classes:
                        'flex-1 h-12 rounded-xl font-semibold text-sm tracking-[0.1px] text-[#18181b] bg-white border border-[#d4d4d8] hover:bg-zinc-50 transition-colors flex items-center justify-center gap-2 cursor-pointer',
                    attributes: {'type': 'button'},
                    events: {'click': (_) => s.handleGoogleSignIn()},
                    [
                      googleSvgIcon(size: 'w-5 h-5'),
                      Component.text('Google'),
                    ],
                  ),
                  button(
                    classes:
                        'flex-1 h-12 rounded-xl font-semibold text-sm tracking-[0.1px] text-[#18181b] bg-white border border-[#d4d4d8] hover:bg-zinc-50 transition-colors flex items-center justify-center gap-2 cursor-pointer',
                    attributes: {'type': 'button'},
                    events: {'click': (_) => s.handlePhantomSignIn()},
                    [
                      lIcon('wallet', cls: 'w-5 h-5 text-[#4f46e5]'),
                      Component.text('Solana Wallet'),
                    ],
                  ),
                ]),

                div(classes: 'h-px w-full bg-[#e4e4e7]', []),

                button(
                  classes:
                      'w-full h-12 rounded-xl font-semibold text-sm tracking-[0.1px] text-[#4f46e5] bg-transparent border-0 cursor-pointer hover:underline',
                  attributes: {'type': 'button'},
                  events: {
                    'click': (_) => setState(() {
                          _localInfo = 'Guest browse is coming in Batch A (W05).';
                          _localError = null;
                        }),
                  },
                  [Component.text('Browse as guest')],
                ),

                p(
                  key: Key('register-link'),
                  classes: 'w-full m-0 flex gap-1 items-center justify-center text-sm leading-5',
                  [
                    span(classes: 'text-[#52525b]', [Component.text("Don't have an account?")]),
                    button(
                      classes:
                          'font-semibold tracking-[0.1px] text-[#4f46e5] bg-transparent border-0 cursor-pointer p-0 hover:underline',
                      attributes: {'type': 'button'},
                      events: {'click': (_) => s.setState(() => s.authView = AuthView.registerPath)},
                      [Component.text('Get Started')],
                    ),
                  ],
                ),
              ],
            ),

            // Legal links under card
            div(
              key: Key('terms-link-login'),
              classes: 'flex font-medium gap-2 items-center text-xs leading-4',
              [
                button(
                  classes: 'text-[#4f46e5] bg-transparent border-0 cursor-pointer p-0 hover:underline',
                  attributes: {'type': 'button'},
                  events: {'click': (_) => web.window.location.assign('/terms-of-use')},
                  [Component.text('Terms of Use')],
                ),
                span(classes: 'text-[#71717a]', [Component.text('•')]),
                button(
                  classes: 'text-[#4f46e5] bg-transparent border-0 cursor-pointer p-0 hover:underline',
                  attributes: {'type': 'button'},
                  events: {'click': (_) => web.window.location.assign('/privacy-policy')},
                  [Component.text('Privacy Policy')],
                ),
                span(classes: 'text-[#71717a]', [Component.text('•')]),
                button(
                  classes: 'text-[#4f46e5] bg-transparent border-0 cursor-pointer p-0 hover:underline',
                  attributes: {'type': 'button'},
                  events: {
                    'click': (_) => setState(() {
                          _localInfo = 'About page coming soon.';
                          _localError = null;
                        }),
                  },
                  [Component.text('About')],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ── Register Path Screen ──────────────────────────────────────
class _RegisterPathScreen extends StatelessComponent {
  final TranyxAppState state;
  const _RegisterPathScreen({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;

    return div(classes: 'w-full animate-fade-up', [
      // Back + Logo header
      div(classes: 'flex flex-col items-center mb-10', [
        button(
          classes:
              'self-start mb-4 p-2 rounded-full ${isDark ? "bg-zinc-800 text-zinc-400 hover:text-white" : "bg-zinc-100 text-zinc-600 hover:text-zinc-900"} transition-colors',
          events: {'click': (_) => s.setState(() => s.authView = AuthView.login)},
          [lIcon('arrow-left')],
        ),
        svgLogo(size: 'w-10 h-10'),
        div(classes: 'mt-4 text-center', [
          h1(classes: 'text-2xl font-black ${isDark ? "text-white" : "text-zinc-900"}', [Component.text('Join Tranyx')]),
          p(classes: 'text-sm font-semibold tracking-wide mt-1.5 ${isDark ? "text-indigo-300/90" : "text-indigo-600/90"}', [
            Component.text('Choose your account type to get started'),
          ]),
        ]),
      ]),

      // Wallet linked banner
      if (s.pendingWalletPublicKey != null)
        div(classes: 'mb-4 p-4 rounded-2xl border border-purple-500/30 bg-purple-500/10 flex items-start gap-3', [
          lIcon('wallet', cls: 'w-5 h-5 text-purple-400 flex-shrink-0 mt-0.5'),
          div([
            p(classes: 'text-sm font-semibold text-purple-400', [Component.text('Phantom Wallet Connected 🎉')]),
            p(classes: 'text-xs mt-0.5 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
              Component.text(
                '${s.pendingWalletPublicKey!.substring(0, 6)}...${s.pendingWalletPublicKey!.substring(s.pendingWalletPublicKey!.length - 4)} — Your wallet will be linked after registration.',
              ),
            ]),
          ]),
        ]),

      // Account type cards
      div(classes: 'space-y-4', [
        if (s.authError != null)
          div(
            classes: 'p-3 rounded-xl bg-red-500/10 border border-red-500/30 text-red-400 text-sm mb-4',
            [Component.text(s.authError!)],
          ),

        _accountTypeCard(
          icon: 'briefcase',
          title: 'Employer',
          subtitle: 'Post jobs and find skilled Nyxians for your tasks',
          accentCls: 'text-blue-400',
          badgeCls: 'bg-blue-500/20 text-blue-400',
          badge: 'EMPLOYER',
          isDark: isDark,
          onTap: () {
            if (s.pendingGoogleAuthResult != null) {
              s.handleGoogleRegisterComplete(AccountType.employer);
            } else {
              s.setState(() {
                s.pendingAccountType = AccountType.employer;
                s.authView = AuthView.registerDetails;
              });
            }
          },
        ),
        _accountTypeCard(
          icon: 'zap',
          title: 'Nyxian Worker',
          subtitle: 'Offer your skills and earn on your own schedule',
          accentCls: 'text-green-400',
          badgeCls: 'bg-green-500/20 text-green-400',
          badge: 'NYXIAN',
          isDark: isDark,
          onTap: () {
            if (s.pendingGoogleAuthResult != null) {
              s.handleGoogleRegisterComplete(AccountType.nyxian);
            } else {
              s.setState(() {
                s.pendingAccountType = AccountType.nyxian;
                s.authView = AuthView.registerDetails;
              });
            }
          },
        ),
      ]),

      p(classes: 'text-center text-sm mt-6 ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
        Component.text('Already have an account? '),
        button(
          classes: 'font-semibold ${isDark ? "text-indigo-400" : "text-indigo-600"} hover:underline',
          events: {'click': (_) => s.setState(() => s.authView = AuthView.login)},
          [Component.text('Sign In')],
        ),
      ]),
    ]);
  }

  Component _accountTypeCard({
    required String icon,
    required String title,
    required String subtitle,
    required String accentCls,
    required String badgeCls,
    required String badge,
    required bool isDark,
    required void Function() onTap,
  }) {
    final cardCls = isDark
        ? 'bg-zinc-900 border-zinc-800 hover:border-zinc-700'
        : 'bg-white border-zinc-200 shadow-sm hover:shadow-md';
    return button(
      classes:
          'w-full flex items-center justify-between p-5 rounded-2xl border transition-all text-left card-hover $cardCls',
      events: {'click': (_) => onTap()},
      [
        div(classes: 'flex items-center gap-4', [
          div(classes: 'p-3 rounded-xl ${isDark ? "bg-zinc-800" : "bg-zinc-100"}', [
            lIcon(icon, cls: 'w-6 h-6 $accentCls'),
          ]),
          div([
            div(classes: 'flex items-center gap-2', [
              span(classes: 'font-semibold text-base', [Component.text(title)]),
              span(classes: 'px-2 py-0.5 rounded text-[10px] font-bold $badgeCls', [Component.text(badge)]),
            ]),
            p(classes: 'text-sm mt-0.5 ${isDark ? "text-zinc-500" : "text-zinc-500"}', [Component.text(subtitle)]),
          ]),
        ]),
        lIcon('chevron-right', cls: 'w-5 h-5 ${isDark ? "text-zinc-600" : "text-zinc-300"}'),
      ],
    );
  }
}

// ── Register Details Screen ───────────────────────────────────
class _RegisterDetailsScreen extends StatefulComponent {
  final TranyxAppState state;
  const _RegisterDetailsScreen({required this.state});

  @override
  State<_RegisterDetailsScreen> createState() => _RegisterDetailsScreenState();
}

class _RegisterDetailsScreenState extends State<_RegisterDetailsScreen> {
  String _name = '';
  String _email = '';
  String _password = '';
  String _confirmPassword = '';
  String? _localError;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  bool get _hasMinLength => _password.length >= 8;
  bool get _hasUppercase => _password.contains(RegExp(r'[A-Z]'));
  bool get _hasNumber => _password.contains(RegExp(r'[0-9]'));
  bool get _isPasswordValid => _hasMinLength && _hasUppercase && _hasNumber;

  @override
  // ignore: invalid_use_of_protected_member
  void setState(void Function() fn) => super.setState(fn);

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    final typeLabel = s.pendingAccountType?.label ?? 'Account';
    final cardCls = isDark ? 'bg-zinc-900/80 border-zinc-800' : 'bg-white border-zinc-200 shadow-xl';

    final errorMsg = _localError ?? s.authError;

    return div(classes: 'w-full animate-fade-up', [
      div(classes: 'flex flex-col items-center mb-10', [
        button(
          classes:
              'self-start mb-4 p-2 rounded-full ${isDark ? "bg-zinc-800 text-zinc-400 hover:text-white" : "bg-zinc-100 text-zinc-600"} transition-colors',
          events: {'click': (_) => s.setState(() => s.authView = AuthView.registerPath)},
          [lIcon('arrow-left')],
        ),
        svgLogo(size: 'w-10 h-10'),
        div(classes: 'mt-4 text-center', [
          h1(classes: 'text-2xl font-bold', [Component.text('Create Your Account')]),
          p(classes: 'text-sm mt-1 ${isDark ? "text-zinc-500" : "text-zinc-500"}', [
            Component.text('Setting up your $typeLabel profile'),
          ]),
        ]),
      ]),

      div(classes: 'rounded-3xl border p-8 $cardCls', [
        if (errorMsg != null)
          div(
            key: Key('error'),
            classes: 'mb-4 p-3 rounded-xl bg-red-500/10 border border-red-500/30 text-red-400 text-sm',
            [Component.text(errorMsg)],
          ),

        if (s.pendingWalletPublicKey != null)
          div(classes: 'mb-4 p-3 rounded-xl border border-purple-500/30 bg-purple-500/10 flex items-center gap-3', [
            lIcon('wallet', cls: 'w-4 h-4 text-purple-400 flex-shrink-0'),
            p(classes: 'text-xs text-purple-400', [
              Component.text(
                '🦊 Wallet: ${s.pendingWalletPublicKey!.substring(0, 6)}...${s.pendingWalletPublicKey!.substring(s.pendingWalletPublicKey!.length - 4)} will be linked',
              ),
            ]),
          ]),

        div(key: Key('inputs'), classes: 'space-y-4', [
          inputField(
            label: 'Full Name',
            placeholder: 'John Doe',
            iconName: 'user-circle',
            isDark: isDark,
            value: _name,
            onChange: (v) => setState(() => _name = v),
          ),
          inputField(
            label: 'Email',
            placeholder: 'you@example.com',
            iconName: 'mail',
            type: 'email',
            isDark: isDark,
            value: _email,
            onChange: (v) => setState(() => _email = v),
          ),
          inputField(
            label: 'Password',
            placeholder: '••••••••',
            iconName: 'lock',
            type: 'password',
            isDark: isDark,
            value: _password,
            onChange: (v) => setState(() => _password = v),
            isPassword: true,
            isPasswordVisible: _showPassword,
            onTogglePassword: () => setState(() => _showPassword = !_showPassword),
          ),
          if (_password.isNotEmpty)
            div(
              key: Key('pwd-checklist'),
              classes: 'p-3.5 rounded-2xl border text-xs space-y-2 ${isDark ? "bg-zinc-950/40 border-zinc-800 text-zinc-400" : "bg-zinc-50 border-zinc-200 text-zinc-600"}',
              [
                div(classes: 'font-semibold mb-1 text-[10px] uppercase tracking-wider ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                  Component.text('Password Requirements'),
                ]),
                div(classes: 'flex items-center gap-2', [
                  lIcon(_hasMinLength ? 'check' : 'circle', cls: 'w-3.5 h-3.5 ${_hasMinLength ? "text-emerald-500" : "text-zinc-500"}'),
                  span(classes: _hasMinLength ? 'text-emerald-500' : '', [Component.text('At least 8 characters')]),
                ]),
                div(classes: 'flex items-center gap-2', [
                  lIcon(_hasUppercase ? 'check' : 'circle', cls: 'w-3.5 h-3.5 ${_hasUppercase ? "text-emerald-500" : "text-zinc-500"}'),
                  span(classes: _hasUppercase ? 'text-emerald-500' : '', [Component.text('At least one uppercase letter (A-Z)')]),
                ]),
                div(classes: 'flex items-center gap-2', [
                  lIcon(_hasNumber ? 'check' : 'circle', cls: 'w-3.5 h-3.5 ${_hasNumber ? "text-emerald-500" : "text-zinc-500"}'),
                  span(classes: _hasNumber ? 'text-emerald-500' : '', [Component.text('At least one number (0-9)')]),
                ]),
              ],
            ),
          inputField(
            label: 'Confirm Password',
            placeholder: '••••••••',
            iconName: 'lock',
            type: 'password',
            isDark: isDark,
            value: _confirmPassword,
            onChange: (v) => setState(() => _confirmPassword = v),
            isPassword: true,
            isPasswordVisible: _showConfirmPassword,
            onTogglePassword: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
          ),
        ]),

        button(
          key: Key('register-btn'),
          classes:
              'mt-6 w-full py-4 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
          events: {
            'click': (_) async {
              if (_name.isEmpty || _email.isEmpty || _password.isEmpty) {
                setState(() => _localError = 'Please fill in all fields.');
                return;
              }
              if (!_isPasswordValid) {
                setState(() => _localError = 'Password does not meet the requirements.');
                return;
              }
              if (_password != _confirmPassword) {
                setState(() => _localError = 'Passwords do not match.');
                return;
              }
              setState(() => _localError = null);
              await s.handleRegister(
                name: _name,
                email: _email,
                password: _password,
                type: s.pendingAccountType ?? AccountType.employer,
              );
            },
          },
          [
            if (s.isAuthLoading) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
            Component.text(s.isAuthLoading ? ' Creating...' : 'Create Account'),
          ],
        ),

        p(key: Key('terms-link'), classes: 'text-center text-xs mt-4 ${isDark ? "text-zinc-650" : "text-zinc-400"}', [
          Component.text('By creating an account you agree to our '),
          button(
            classes: 'underline bg-transparent border-0 cursor-pointer text-zinc-450 hover:text-white transition-colors p-0 font-medium',
            events: {'click': (_) => web.window.location.assign('/terms-of-use')},
            [Component.text('Terms of Use')],
          ),
          Component.text(' and '),
          button(
            classes: 'underline bg-transparent border-0 cursor-pointer text-zinc-450 hover:text-white transition-colors p-0 font-medium',
            events: {'click': (_) => web.window.location.assign('/privacy-policy')},
            [Component.text('Privacy Policy')],
          ),
        ]),
      ]),
    ]);
  }
}

// ── KYC Pending Screen ────────────────────────────────────────
class _KycPendingScreen extends StatelessComponent {
  final TranyxAppState state;
  const _KycPendingScreen({required this.state});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final cardCls = isDark ? 'bg-zinc-900/80 border-zinc-800' : 'bg-white border-zinc-200 shadow-xl';

    return div(classes: 'w-full animate-fade-up', [
      div(classes: 'rounded-3xl border p-10 $cardCls text-center', [
        div(classes: 'flex justify-center mb-6', [
          div(classes: 'p-6 rounded-3xl bg-amber-500/10 border border-amber-500/20', [
            lIcon('hourglass', cls: 'w-12 h-12 text-amber-400 animate-pulse'),
          ]),
        ]),
        h1(classes: 'text-2xl font-bold mb-3', [Component.text('Verification Pending')]),
        p(classes: 'text-sm leading-relaxed ${isDark ? "text-zinc-400" : "text-zinc-600"} max-w-sm mx-auto', [
          Component.text(
            "Your account is under review. Our team will verify your details within 24–48 hours. "
            "You'll receive an email once approved.",
          ),
        ]),
        div(
          classes:
              'mt-8 p-4 rounded-2xl ${isDark ? "bg-zinc-800 border border-zinc-700" : "bg-zinc-50 border border-zinc-200"} text-sm ${isDark ? "text-zinc-400" : "text-zinc-600"}',
          [
            div(classes: 'flex items-center gap-3 justify-center', [
              lIcon('mail', cls: 'w-4 h-4'),
              Component.text('Check your inbox for updates'),
            ]),
          ],
        ),
        button(
          classes:
              'mt-6 px-6 py-3 rounded-xl ${isDark ? "bg-zinc-800 hover:bg-zinc-700 text-zinc-300" : "bg-zinc-100 hover:bg-zinc-200 text-zinc-700"} text-sm font-medium transition-colors',
          events: {'click': (_) => s.setState(() => s.authView = AuthView.login)},
          [Component.text('Back to Login')],
        ),
      ]),
    ]);
  }
}
