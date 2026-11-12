import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';
import '../../state/app_state.dart';
import '../widgets/auth_brand_shell.dart';
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
      AuthView.forgotPassword => _ForgotPasswordScreen(state: s),
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
  bool _showPassword = false;

  @override
  // ignore: invalid_use_of_protected_member
  void setState(void Function() fn) => super.setState(fn);

  // ── Shared pieces ───────────────────────────────────────────

  Component _w01Field({
    required String label,
    required String placeholder,
    required String iconSrc,
    required String value,
    required void Function(String) onChange,
    required bool isDark,
    String idPrefix = '',
    String type = 'text',
    bool isPassword = false,
    bool isPasswordVisible = false,
    void Function()? onTogglePassword,
  }) {
    final inputId =
        '$idPrefix${label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
    final controlBorder = isDark
        ? 'bg-zinc-900 border-zinc-700 focus-within:border-[#4f46e5]'
        : 'bg-white border-[#d4d4d8] focus-within:border-[#4f46e5]';
    final labelCls = isDark
        ? 'font-semibold leading-5 text-sm text-zinc-100 tracking-[0.1px] m-0'
        : 'font-semibold leading-5 text-sm text-[#18181b] tracking-[0.1px] m-0';
    final inputCls = isDark
        ? 'bg-transparent border-none outline-none flex-1 min-w-0 text-[15px] leading-[22px] text-zinc-50 placeholder:text-zinc-500'
        : 'bg-transparent border-none outline-none flex-1 min-w-0 text-[15px] leading-[22px] text-[#18181b] placeholder:text-[#71717a]';
    return div(classes: 'flex flex-col gap-1.5 items-start w-full', [
      p(classes: labelCls, [Component.text(label)]),
      div(
        classes: '$controlBorder border flex gap-2.5 h-12 items-center px-3.5 relative rounded-xl w-full',
        [
          img(
            src: iconSrc,
            classes: 'size-[18px] shrink-0 ${isDark ? "opacity-80" : ""}',
            attributes: {'alt': '', 'aria-hidden': 'true'},
          ),
          input<String>(
            classes: inputCls,
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
              attributes: {
                'type': 'button',
                'aria-label': isPasswordVisible ? 'Hide password' : 'Show password',
              },
              [
                img(
                  src: '/images/w01/932ea.svg',
                  classes: 'size-[18px] ${isDark ? "opacity-80 invert" : ""}',
                  attributes: {'alt': '', 'aria-hidden': 'true'},
                ),
              ],
            ),
        ],
      ),
    ]);
  }

  Component _legalLinks({
    required bool isDark,
    required String link,
    required String textMuted,
  }) {
    return div(
      key: Key('terms-link-login'),
      classes: 'flex font-medium gap-2 items-center text-xs leading-4 flex-wrap justify-center',
      [
        button(
          classes: '$link bg-transparent border-0 cursor-pointer p-0 hover:underline',
          attributes: {'type': 'button'},
          events: {'click': (_) => web.window.location.assign('/terms-of-use')},
          [Component.text('Terms of Use')],
        ),
        span(classes: textMuted, [Component.text('•')]),
        button(
          classes: '$link bg-transparent border-0 cursor-pointer p-0 hover:underline',
          attributes: {'type': 'button'},
          events: {'click': (_) => web.window.location.assign('/privacy-policy')},
          [Component.text('Privacy Policy')],
        ),
        span(classes: textMuted, [Component.text('•')]),
        button(
          classes: '$link bg-transparent border-0 cursor-pointer p-0 hover:underline',
          attributes: {'type': 'button'},
          events: {'click': (_) => web.window.location.assign('/about')},
          [Component.text('About')],
        ),
      ],
    );
  }

  Component _signInCard({
    required TranyxAppState s,
    required bool isDark,
    required String formCard,
    required String textPrimary,
    required String textSecondary,
    required String textMuted,
    required String divider,
    required String secondaryBtn,
    required String link,
    String idPrefix = '',
    String cardWidthCls = 'w-full max-w-[440px]',
    String cardPadCls = 'p-8',
  }) {
    final errorMsg = _localError ?? s.authError;
    return div(
      classes: '$formCard flex flex-col gap-4 items-start $cardPadCls relative rounded-3xl $cardWidthCls',
      [
        div(classes: 'flex flex-col gap-1 items-start', [
          p(
            classes: 'm-0 font-bold text-2xl leading-8 tracking-[-0.4px] $textPrimary',
            [Component.text('Sign In')],
          ),
          p(
            classes: 'm-0 font-normal text-sm leading-5 $textSecondary',
            [Component.text('Welcome back to Tranyx.')],
          ),
        ]),
        if (errorMsg != null)
          div(
            key: Key('error-msg'),
            classes: 'w-full p-3 rounded-xl bg-red-500/10 border border-red-500/30 text-red-500 text-sm',
            [Component.text(errorMsg)],
          ),
        if (_localInfo != null)
          div(
            classes: 'w-full p-3 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-indigo-400 text-sm',
            [Component.text(_localInfo!)],
          ),
        _w01Field(
          label: 'Email',
          placeholder: 'you@example.com',
          iconSrc: '/images/w01/b7212.svg',
          type: 'email',
          value: _email,
          onChange: (v) => setState(() => _email = v),
          isDark: isDark,
          idPrefix: idPrefix,
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
          isDark: isDark,
          idPrefix: idPrefix,
        ),
        div(key: Key('forgot-pwd-btn'), classes: 'flex items-center justify-end w-full', [
          button(
            classes:
                'font-semibold text-sm leading-5 tracking-[0.1px] $link bg-transparent border-0 cursor-pointer p-0 hover:underline',
            attributes: {'type': 'button'},
            events: {
              'click': (_) {
                s.setState(() {
                  if (_email.trim().isNotEmpty) {
                    s.pendingVerifyEmail = _email.trim();
                  }
                  s.authView = AuthView.forgotPassword;
                  s.authError = null;
                });
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
          div(classes: 'flex-1 h-px $divider', []),
          span(classes: 'font-medium text-xs leading-4 $textMuted', [Component.text('or continue with')]),
          div(classes: 'flex-1 h-px $divider', []),
        ]),
        div(classes: 'flex gap-3 items-center w-full', [
          button(
            classes:
                'flex-1 h-12 rounded-xl font-semibold text-sm tracking-[0.1px] border $secondaryBtn transition-colors flex items-center justify-center gap-2 cursor-pointer',
            attributes: {'type': 'button'},
            events: {'click': (_) => s.handleGoogleSignIn()},
            [googleSvgIcon(size: 'w-5 h-5'), Component.text('Google')],
          ),
          button(
            classes:
                'flex-1 h-12 rounded-xl font-semibold text-sm tracking-[0.1px] border $secondaryBtn transition-colors flex items-center justify-center gap-2 cursor-pointer',
            attributes: {'type': 'button'},
            events: {'click': (_) => s.handlePhantomSignIn()},
            [
              solanaLogo(cls: 'w-5 h-5'),
              Component.text('Solana Wallet'),
            ],
          ),
        ]),
        div(classes: 'h-px w-full $divider', []),
        button(
          classes:
              'w-full h-12 rounded-xl font-semibold text-sm tracking-[0.1px] $link bg-transparent border-0 cursor-pointer hover:underline',
          attributes: {'type': 'button'},
          events: {'click': (_) => s.enterGuestBrowse()},
          [Component.text('Browse as guest')],
        ),
        p(
          key: Key('register-link'),
          classes: 'w-full m-0 flex gap-1 items-center justify-center text-sm leading-5 flex-wrap',
          [
            span(classes: textSecondary, [Component.text("Don't have an account?")]),
            button(
              classes:
                  'font-semibold tracking-[0.1px] $link bg-transparent border-0 cursor-pointer p-0 hover:underline',
              attributes: {'type': 'button'},
              events: {'click': (_) => s.setState(() => s.authView = AuthView.registerPath)},
              [Component.text('Get Started')],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;

    final formCard = isDark
        ? 'bg-zinc-900 border border-zinc-800 shadow-[0px_8px_24px_-4px_rgba(0,0,0,0.45)]'
        : 'bg-white border border-[#e4e4e7] shadow-[0px_8px_24px_-4px_rgba(9,9,11,0.08)]';
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textSecondary = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    final textMuted = isDark ? 'text-zinc-500' : 'text-[#71717a]';
    final divider = isDark ? 'bg-zinc-800' : 'bg-[#e4e4e7]';
    final secondaryBtn = isDark
        ? 'bg-zinc-900 border-zinc-700 text-zinc-100 hover:bg-zinc-800'
        : 'bg-white border-[#d4d4d8] text-[#18181b] hover:bg-zinc-50';
    const link = 'text-[#4f46e5]';

    final card = _signInCard(
      s: s,
      isDark: isDark,
      formCard: formCard,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      divider: divider,
      secondaryBtn: secondaryBtn,
      link: link,
      idPrefix: 'd-',
    );
    final cardTablet = _signInCard(
      s: s,
      isDark: isDark,
      formCard: formCard,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      divider: divider,
      secondaryBtn: secondaryBtn,
      link: link,
      idPrefix: 't-',
      cardWidthCls: 'w-full max-w-[480px]',
    );
    final cardMobile = _signInCard(
      s: s,
      isDark: isDark,
      formCard: formCard,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      divider: divider,
      secondaryBtn: secondaryBtn,
      link: link,
      idPrefix: 'm-',
      cardWidthCls: 'w-full',
      cardPadCls: 'px-5 py-8',
    );
    final legal = _legalLinks(isDark: isDark, link: link, textMuted: textMuted);

    // Shared AuthBrandShell: white brand panel + animated CSS/SVG blobs.
    return AuthBrandShell(
      isDark: isDark,
      card: card,
      cardTablet: cardTablet,
      cardMobile: cardMobile,
      legal: legal,
    );
  }
}

// ── Register Path Screen (W02 Join) ───────────────────────────
class _RegisterPathScreen extends StatefulComponent {
  final TranyxAppState state;
  const _RegisterPathScreen({required this.state});

  @override
  State<_RegisterPathScreen> createState() => _RegisterPathScreenState();
}

class _RegisterPathScreenState extends State<_RegisterPathScreen> {
  // Figma defaults to Nyxian selected
  AccountType _selected = AccountType.nyxian;

  @override
  // ignore: invalid_use_of_protected_member
  void setState(void Function() fn) => super.setState(fn);

  @override
  void initState() {
    super.initState();
    final pending = component.state.pendingAccountType;
    if (pending == AccountType.employer || pending == AccountType.nyxian) {
      _selected = pending!;
    }
  }

  void _continue() {
    final s = component.state;
    if (s.pendingGoogleAuthResult != null) {
      s.handleGoogleRegisterComplete(_selected);
      return;
    }
    s.setState(() {
      s.pendingAccountType = _selected;
      s.authView = AuthView.registerDetails;
      s.authError = null;
    });
  }

  Component _roleCard({
    required AccountType type,
    required String letter,
    required String title,
    required String subtitle,
    required String avatarBg,
    required String avatarFg,
    required bool isDark,
  }) {
    final selected = _selected == type;
    final border = selected
        ? 'border-2 border-[#4f46e5] bg-[#eef2ff]/60 dark:bg-indigo-500/10'
        : (isDark
            ? 'border border-zinc-700 bg-zinc-900'
            : 'border border-[#e4e4e7] bg-white');
    return button(
      classes: 'w-full flex flex-col items-start overflow-clip p-5 relative rounded-[20px] $border text-left cursor-pointer bg-transparent transition-colors',
      attributes: {'type': 'button'},
      events: {'click': (_) => setState(() => _selected = type)},
      [
        div(classes: 'flex gap-3 items-center w-full', [
          div(
            classes: '$avatarBg flex items-center justify-center overflow-clip relative rounded-[22px] shrink-0 size-11',
            [
              p(classes: 'm-0 font-bold text-[17px] $avatarFg', [Component.text(letter)]),
            ],
          ),
          div(classes: 'flex flex-1 flex-col gap-0.5 items-start min-w-0', [
            p(
              classes: 'm-0 font-semibold text-[17px] leading-6 ${isDark ? "text-zinc-50" : "text-[#18181b]"}',
              [Component.text(title)],
            ),
            p(
              classes: 'm-0 font-normal text-sm leading-5 ${isDark ? "text-zinc-400" : "text-[#52525b]"}',
              [Component.text(subtitle)],
            ),
          ]),
          if (selected)
            div(
              classes:
                  'bg-[#4f46e5] border-2 border-[#4f46e5] flex items-center justify-center rounded-[11px] shrink-0 size-[22px]',
              [
                img(
                  src: '/images/w01/e5c29.svg',
                  classes: 'size-3.5',
                  attributes: {'alt': '', 'aria-hidden': 'true'},
                ),
              ],
            )
          else
            div(
              classes:
                  'border-2 ${isDark ? "border-zinc-600" : "border-[#d4d4d8]"} rounded-[11px] shrink-0 size-[22px]',
              [],
            ),
        ]),
      ],
    );
  }

  Component _joinCard({required bool isDark, String widthCls = 'w-full max-w-[480px]'}) {
    final s = component.state;
    final formCard = isDark
        ? 'bg-zinc-900 border border-zinc-700 shadow-[0px_8px_24px_-4px_rgba(0,0,0,0.45)]'
        : 'bg-white border border-[#e4e4e7] shadow-[0px_8px_24px_-4px_rgba(9,9,11,0.08)]';
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textSecondary = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    final link = 'text-[#4f46e5]';

    return div(
      classes: '$formCard flex flex-col gap-4 items-start p-8 relative rounded-3xl $widthCls',
      [
        div(classes: 'flex flex-col gap-1 items-start', [
          p(classes: 'm-0 font-bold text-2xl leading-8 tracking-[-0.4px] $textPrimary', [
            Component.text('Join Tranyx'),
          ]),
          p(classes: 'm-0 font-normal text-sm leading-5 $textSecondary', [
            Component.text('Choose your account type to get started'),
          ]),
        ]),
        if (s.authError != null)
          div(
            classes: 'w-full p-3 rounded-xl bg-red-500/10 border border-red-500/30 text-red-500 text-sm',
            [Component.text(s.authError!)],
          ),
        _roleCard(
          type: AccountType.nyxian,
          letter: 'N',
          title: 'Nyxian Worker',
          subtitle: 'Offer your skills and earn on your own schedule',
          avatarBg: isDark ? 'bg-emerald-500/15' : 'bg-[#f0fdf4]',
          avatarFg: isDark ? 'text-emerald-400' : 'text-[#15803d]',
          isDark: isDark,
        ),
        _roleCard(
          type: AccountType.employer,
          letter: 'E',
          title: 'Employer',
          subtitle: 'Post jobs and find skilled Nyxians for your tasks',
          avatarBg: isDark ? 'bg-blue-500/15' : 'bg-[#eff6ff]',
          avatarFg: isDark ? 'text-blue-400' : 'text-[#1d4ed8]',
          isDark: isDark,
        ),
        div(classes: 'flex gap-2 items-center pl-1 w-full', [
          span(
            classes:
                'px-2.5 h-6 inline-flex items-center rounded-full text-xs font-semibold ${isDark ? "bg-amber-500/15 text-amber-300" : "bg-[#fffbeb] text-[#b45309]"}',
            [Component.text('Hybrid PRO')],
          ),
          p(classes: 'm-0 flex-1 font-medium text-xs leading-4 $textSecondary', [
            Component.text('Do both later — upgrade to Pro from your profile.'),
          ]),
        ]),
        button(
          classes:
              'w-full h-12 rounded-xl font-semibold text-sm tracking-[0.1px] text-white bg-[#4f46e5] shadow-[0px_8px_10px_rgba(79,70,229,0.25)] hover:opacity-90 transition-opacity flex items-center justify-center border-0 cursor-pointer',
          attributes: {'type': 'button'},
          events: {'click': (_) => _continue()},
          [Component.text('Continue')],
        ),
        div(classes: 'flex gap-1 items-center justify-center w-full text-sm', [
          span(classes: textSecondary, [Component.text('Already have an account?')]),
          button(
            classes: 'font-semibold $link bg-transparent border-0 cursor-pointer p-0 hover:underline',
            attributes: {'type': 'button'},
            events: {'click': (_) => s.setState(() => s.authView = AuthView.login)},
            [Component.text('Sign In')],
          ),
        ]),
      ],
    );
  }

  Component? _walletBanner({required bool isDark}) {
    final s = component.state;
    final key = s.pendingWalletPublicKey;
    if (key == null) return null;
    final short = key.length > 10 ? '${key.substring(0, 4)}…${key.substring(key.length - 4)}' : key;
    return div(classes: 'w-full max-w-[480px] flex flex-col gap-2', [
      p(
        classes:
            'm-0 font-semibold text-[11px] tracking-[0.8px] uppercase ${isDark ? "text-zinc-500" : "text-[#52525b]"}',
        [Component.text('Solana sign-up state')],
      ),
      div(
        classes:
            'w-full flex gap-3 items-start px-4 py-3.5 rounded-2xl border ${isDark ? "bg-emerald-500/10 border-emerald-500/30" : "bg-[#ecfdf5] border-[#e4e4e7]"}',
        [
          img(src: '/images/w01/bfc38.svg', classes: 'size-5 mt-0.5', attributes: {'alt': ''}),
          div(classes: 'flex flex-col gap-0.5 min-w-0', [
            p(
              classes: 'm-0 font-semibold text-[15px] ${isDark ? "text-zinc-50" : "text-[#18181b]"}',
              [Component.text('Wallet verified 🎉')],
            ),
            p(
              classes: 'm-0 text-sm ${isDark ? "text-zinc-400" : "text-[#52525b]"}',
              [Component.text('Wallet $short is verified. Pick an account type, then add your email and password so you can sign in with either.')],
            ),
          ]),
        ],
      ),
    ]);
  }

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;
    return AuthBrandShell(
      isDark: isDark,
      card: _joinCard(isDark: isDark),
      cardTablet: _joinCard(isDark: isDark, widthCls: 'w-full max-w-[480px]'),
      cardMobile: _joinCard(isDark: isDark, widthCls: 'w-full'),
      belowCard: _walletBanner(isDark: isDark),
    );
  }
}

// ── Register Details (W03 Create account) ─────────────────────
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
  bool get _passwordsMatch =>
      _confirmPassword.isNotEmpty && _password == _confirmPassword;
  bool get _canSubmit =>
      _name.trim().isNotEmpty &&
      _email.trim().isNotEmpty &&
      _isPasswordValid &&
      _passwordsMatch;

  @override
  // ignore: invalid_use_of_protected_member
  void setState(void Function() fn) => super.setState(fn);

  Component _field({
    required String label,
    required String placeholder,
    required String iconSrc,
    required String value,
    required void Function(String) onChange,
    required bool isDark,
    String type = 'text',
    bool isPassword = false,
    bool isPasswordVisible = false,
    void Function()? onTogglePassword,
    bool danger = false,
    String? helper,
  }) {
    final border = danger
        ? 'border-2 border-[#ef4444]'
        : (isDark ? 'border border-zinc-600' : 'border border-[#d4d4d8]');
    final inputId = 'reg_${label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
    return div(classes: 'flex flex-col gap-1.5 items-start w-full', [
      p(
        classes:
            'm-0 font-semibold text-sm tracking-[0.1px] ${isDark ? "text-zinc-50" : "text-[#18181b]"}',
        [Component.text(label)],
      ),
      div(
        classes:
            'bg-transparent $border flex gap-2.5 h-12 items-center overflow-clip px-3.5 relative rounded-xl w-full ${isDark ? "bg-zinc-950" : "bg-white"}',
        [
          img(src: iconSrc, classes: 'size-[18px] shrink-0 ${isDark ? "opacity-70 invert" : ""}', attributes: {'alt': ''}),
          input(
            id: inputId,
            classes:
                'bg-transparent border-0 outline-none flex-1 text-[15px] leading-[22px] min-w-0 ${isDark ? "text-zinc-50 placeholder-zinc-500" : "text-[#18181b] placeholder-[#a1a1aa]"}',
            type: type == 'email'
                ? InputType.email
                : (isPassword && !isPasswordVisible ? InputType.password : InputType.text),
            attributes: {
              'placeholder': placeholder,
              'value': value,
              'autocomplete': isPassword ? 'new-password' : (type == 'email' ? 'email' : 'name'),
            },
            events: {
              'input': (e) => onChange(getInputValue(e.target)),
            },
          ),
          if (isPassword && onTogglePassword != null)
            button(
              classes: 'bg-transparent border-0 cursor-pointer p-0 shrink-0',
              attributes: {'type': 'button'},
              events: {'click': (_) => onTogglePassword()},
              [
                img(
                  src: '/images/w01/932ea.svg',
                  classes: 'size-[18px] ${isDark ? "opacity-70 invert" : ""}',
                  attributes: {'alt': isPasswordVisible ? 'Hide' : 'Show'},
                ),
              ],
            ),
        ],
      ),
      if (helper != null)
        div(classes: 'flex gap-1.5 items-center w-full', [
          img(src: '/images/w01/03198.svg', classes: 'size-3.5', attributes: {'alt': ''}),
          p(classes: 'm-0 flex-1 font-medium text-xs leading-4 text-[#dc2626]', [Component.text(helper)]),
        ]),
    ]);
  }

  Component _reqRow(bool ok, String label, bool isDark) {
    return div(classes: 'flex gap-2 items-center', [
      div(
        classes:
            '${ok ? "bg-[#ecfdf5]" : (isDark ? "bg-zinc-800" : "bg-[#fafafa]")} flex items-center justify-center rounded-[9px] size-[18px]',
        [
          img(
            src: ok ? '/images/w01/bfc38.svg' : '/images/w01/4633f.svg',
            classes: 'size-3',
            attributes: {'alt': ''},
          ),
        ],
      ),
      p(
        classes:
            'm-0 text-sm leading-5 ${ok ? "text-[#047857]" : (isDark ? "text-zinc-400" : "text-[#52525b]")}',
        [Component.text(label)],
      ),
    ]);
  }

  Component _createCard({required bool isDark, String widthCls = 'w-full max-w-[460px]'}) {
    final s = component.state;
    final formCard = isDark
        ? 'bg-zinc-900 border border-zinc-700 shadow-[0px_8px_24px_-4px_rgba(0,0,0,0.45)]'
        : 'bg-white border border-[#e4e4e7] shadow-[0px_8px_24px_-4px_rgba(9,9,11,0.08)]';
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textSecondary = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    final type = s.pendingAccountType ?? AccountType.nyxian;
    final typeLabel = type == AccountType.nyxian ? 'Nyxian' : 'Employer';
    final badgeBg = type == AccountType.nyxian
        ? (isDark ? 'bg-emerald-500/15 text-emerald-300' : 'bg-[#f0fdf4] text-[#15803d]')
        : (isDark ? 'bg-blue-500/15 text-blue-300' : 'bg-[#eff6ff] text-[#1d4ed8]');
    final errorMsg = _localError ?? s.authError;
    final confirmDanger =
        _confirmPassword.isNotEmpty && _password != _confirmPassword;

    return div(
      classes: '$formCard flex flex-col gap-4 items-start p-8 relative rounded-3xl $widthCls',
      [
        div(classes: 'flex flex-col gap-1 items-start', [
          p(classes: 'm-0 font-bold text-2xl leading-8 tracking-[-0.4px] $textPrimary', [
            Component.text('Create Your Account'),
          ]),
          div(classes: 'flex gap-2 items-center', [
            p(classes: 'm-0 text-sm $textSecondary', [
              Component.text('Setting up your $typeLabel profile'),
            ]),
            span(
              classes: 'px-2.5 h-6 inline-flex items-center rounded-full text-xs font-semibold $badgeBg',
              [Component.text(typeLabel)],
            ),
          ]),
        ]),
        button(
          classes:
              'text-sm font-semibold text-[#4f46e5] bg-transparent border-0 cursor-pointer p-0 hover:underline',
          attributes: {'type': 'button'},
          events: {'click': (_) => s.setState(() => s.authView = AuthView.registerPath)},
          [Component.text('← Change account type')],
        ),
        if (errorMsg != null)
          div(
            classes: 'w-full p-3 rounded-xl bg-red-500/10 border border-red-500/30 text-red-500 text-sm',
            [Component.text(errorMsg)],
          ),
        _field(
          label: 'Full Name',
          placeholder: 'Juan Dela Cruz',
          iconSrc: '/images/w01/65364.svg',
          value: _name,
          onChange: (v) => setState(() => _name = v),
          isDark: isDark,
        ),
        _field(
          label: 'Email',
          placeholder: 'juan@example.com',
          iconSrc: '/images/w01/b7212.svg',
          type: 'email',
          value: _email,
          onChange: (v) => setState(() => _email = v),
          isDark: isDark,
        ),
        _field(
          label: 'Password',
          placeholder: '••••••••••',
          iconSrc: '/images/w01/a5857.svg',
          value: _password,
          onChange: (v) => setState(() => _password = v),
          isDark: isDark,
          isPassword: true,
          isPasswordVisible: _showPassword,
          onTogglePassword: () => setState(() => _showPassword = !_showPassword),
        ),
        if (_password.isNotEmpty)
          div(
            classes:
                'w-full flex flex-col gap-2 px-3.5 py-3 rounded-xl ${isDark ? "bg-zinc-950" : "bg-[#fafafa]"}',
            [
              p(
                classes: 'm-0 font-semibold text-sm tracking-[0.1px] $textPrimary',
                [Component.text('Password Requirements')],
              ),
              _reqRow(_hasMinLength, 'At least 8 characters', isDark),
              _reqRow(_hasUppercase, 'At least one uppercase letter (A-Z)', isDark),
              _reqRow(_hasNumber, 'At least one number (0-9)', isDark),
            ],
          ),
        _field(
          label: 'Confirm Password',
          placeholder: '••••••••',
          iconSrc: '/images/w01/a5857.svg',
          value: _confirmPassword,
          onChange: (v) => setState(() => _confirmPassword = v),
          isDark: isDark,
          isPassword: true,
          isPasswordVisible: _showConfirmPassword,
          onTogglePassword: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
          danger: confirmDanger,
          helper: confirmDanger ? 'Passwords do not match.' : null,
        ),
        button(
          classes:
              'w-full h-12 rounded-xl font-semibold text-sm tracking-[0.1px] flex items-center justify-center gap-2 border-0 '
              '${_canSubmit && !s.isAuthLoading ? "text-white bg-[#4f46e5] shadow-[0px_8px_10px_rgba(79,70,229,0.25)] hover:opacity-90 cursor-pointer" : "text-[#a1a1aa] bg-[#e4e4e7] cursor-not-allowed"}',
          attributes: {'type': 'button', if (!_canSubmit || s.isAuthLoading) 'disabled': 'true'},
          events: {
            'click': (_) async {
              if (!_canSubmit || s.isAuthLoading) return;
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
                name: _name.trim(),
                email: _email.trim(),
                password: _password,
                type: s.pendingAccountType ?? AccountType.nyxian,
              );
            },
          },
          [
            if (s.isAuthLoading) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
            Component.text(s.isAuthLoading ? ' Creating...' : 'Create Account'),
          ],
        ),
        p(
          classes: 'm-0 w-full text-center font-medium text-xs leading-4 $textSecondary',
          [
            Component.text('By creating an account you agree to our '),
            button(
              classes: 'underline bg-transparent border-0 cursor-pointer p-0 font-medium text-[#4f46e5]',
              attributes: {'type': 'button'},
              events: {'click': (_) => web.window.location.assign('/terms-of-use')},
              [Component.text('Terms of Use')],
            ),
            Component.text(' and '),
            button(
              classes: 'underline bg-transparent border-0 cursor-pointer p-0 font-medium text-[#4f46e5]',
              attributes: {'type': 'button'},
              events: {'click': (_) => web.window.location.assign('/privacy-policy')},
              [Component.text('Privacy Policy')],
            ),
            Component.text('.'),
          ],
        ),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final isDark = component.state.isDark;
    return AuthBrandShell(
      isDark: isDark,
      card: _createCard(isDark: isDark),
      cardMobile: _createCard(isDark: isDark, widthCls: 'w-full'),
    );
  }
}

// ── Verification Pending (W04) ────────────────────────────────
class _KycPendingScreen extends StatelessComponent {
  final TranyxAppState state;
  const _KycPendingScreen({required this.state});

  Component _card({required bool isDark, String widthCls = 'w-full max-w-[440px]'}) {
    final s = state;
    final formCard = isDark
        ? 'bg-zinc-900 border border-zinc-700 shadow-[0px_8px_24px_-4px_rgba(0,0,0,0.45)]'
        : 'bg-white border border-[#e4e4e7] shadow-[0px_8px_24px_-4px_rgba(9,9,11,0.08)]';
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textSecondary = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    final email = s.pendingVerifyEmail ?? s.userEmail;
    final emailBit = email.isNotEmpty ? ' to $email' : '';

    return div(
      classes: '$formCard flex flex-col gap-4 items-start p-8 relative rounded-3xl $widthCls',
      [
        div(classes: 'flex flex-col gap-3 items-center pt-2 w-full', [
          div(
            classes:
                '${isDark ? "bg-indigo-500/15" : "bg-[#eef2ff]"} flex items-center justify-center rounded-[36px] size-[72px]',
            [
              img(
                src: '/images/w01/00ef3.svg',
                classes: 'size-8 ${isDark ? "invert opacity-80" : ""}',
                attributes: {'alt': ''},
              ),
            ],
          ),
          p(
            classes: 'm-0 font-bold text-2xl leading-8 tracking-[-0.4px] text-center $textPrimary',
            [Component.text('Verification Pending')],
          ),
          p(
            classes: 'm-0 text-[15px] leading-[22px] text-center $textSecondary w-full',
            [
              Component.text(
                'Check your inbox for updates. We sent a verification link$emailBit.',
              ),
            ],
          ),
        ]),
        button(
          classes:
              'w-full h-12 rounded-xl font-semibold text-sm tracking-[0.1px] border flex items-center justify-center cursor-pointer '
              '${isDark ? "bg-zinc-900 border-zinc-600 text-zinc-50 hover:bg-zinc-800" : "bg-white border-[#d4d4d8] text-[#18181b] hover:bg-zinc-50"}',
          attributes: {'type': 'button'},
          events: {
            'click': (_) async {
              await s.handleResendVerificationEmail();
            },
          },
          [Component.text(s.isAuthLoading ? 'Sending…' : 'Resend email')],
        ),
        button(
          classes:
              'w-full h-12 rounded-xl font-semibold text-sm tracking-[0.1px] text-[#4f46e5] bg-transparent border-0 cursor-pointer hover:underline',
          attributes: {'type': 'button'},
          events: {
            'click': (_) => s.setState(() {
              s.authView = AuthView.login;
              s.isAuthenticated = false;
            }),
          },
          [Component.text('Back to Login')],
        ),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final isDark = state.isDark;
    return AuthBrandShell(
      isDark: isDark,
      card: _card(isDark: isDark),
      cardMobile: _card(isDark: isDark, widthCls: 'w-full'),
    );
  }
}

// ── Forgot Password (W01 styling + live reset) ────────────────
class _ForgotPasswordScreen extends StatefulComponent {
  final TranyxAppState state;
  const _ForgotPasswordScreen({required this.state});

  @override
  State<_ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<_ForgotPasswordScreen> {
  String _email = '';
  String? _localError;
  String? _localInfo;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    final seed = component.state.pendingVerifyEmail ?? '';
    if (seed.isNotEmpty) _email = seed;
  }

  @override
  // ignore: invalid_use_of_protected_member
  void setState(void Function() fn) => super.setState(fn);

  Component _card({required bool isDark, String widthCls = 'w-full max-w-[440px]'}) {
    final s = component.state;
    final formCard = isDark
        ? 'bg-zinc-900 border border-zinc-700 shadow-[0px_8px_24px_-4px_rgba(0,0,0,0.45)]'
        : 'bg-white border border-[#e4e4e7] shadow-[0px_8px_24px_-4px_rgba(9,9,11,0.08)]';
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textSecondary = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    final border = isDark ? 'border border-zinc-600' : 'border border-[#d4d4d8]';

    return div(
      classes: '$formCard flex flex-col gap-4 items-start p-8 relative rounded-3xl $widthCls',
      [
        div(classes: 'flex flex-col gap-1 items-start', [
          p(classes: 'm-0 font-bold text-2xl leading-8 tracking-[-0.4px] $textPrimary', [
            Component.text('Reset Password'),
          ]),
          p(classes: 'm-0 text-sm leading-5 $textSecondary', [
            Component.text('Enter your email and we’ll send a reset link.'),
          ]),
        ]),
        if (_localError != null)
          div(
            classes: 'w-full p-3 rounded-xl bg-red-500/10 border border-red-500/30 text-red-500 text-sm',
            [Component.text(_localError!)],
          ),
        if (_sent || _localInfo != null)
          div(
            key: Key('forgot-sent'),
            classes: 'w-full p-3 rounded-xl bg-green-500/10 border border-green-500/30 text-green-600 text-sm',
            [Component.text(_localInfo ?? 'Password reset email sent! Check your inbox.')],
          ),
        div(classes: 'flex flex-col gap-1.5 w-full', [
          p(classes: 'm-0 font-semibold text-sm tracking-[0.1px] $textPrimary', [Component.text('Email')]),
          div(
            classes: 'flex gap-2.5 h-12 items-center px-3.5 rounded-xl $border ${isDark ? "bg-zinc-950" : "bg-white"}',
            [
              img(
                src: '/images/w01/b7212.svg',
                classes: 'size-[18px] ${isDark ? "opacity-70 invert" : ""}',
                attributes: {'alt': ''},
              ),
              input(
                classes:
                    'bg-transparent border-0 outline-none flex-1 text-[15px] ${isDark ? "text-zinc-50 placeholder-zinc-500" : "text-[#18181b] placeholder-[#a1a1aa]"}',
                type: InputType.email,
                attributes: {'placeholder': 'you@example.com', 'value': _email},
                events: {'input': (e) => setState(() => _email = getInputValue(e.target))},
              ),
            ],
          ),
        ]),
        button(
          classes:
              'w-full h-12 rounded-xl font-semibold text-sm text-white bg-[#4f46e5] shadow-[0px_8px_10px_rgba(79,70,229,0.25)] hover:opacity-90 border-0 cursor-pointer',
          attributes: {'type': 'button'},
          events: {
            'click': (_) async {
              if (_email.trim().isEmpty) {
                setState(() {
                  _localError = 'Enter your email to reset password.';
                  _localInfo = null;
                  _sent = false;
                });
                return;
              }
              setState(() {
                _localError = null;
                _localInfo = null;
              });
              await s.handleForgotPassword(_email.trim());
              setState(() {
                _sent = true;
                _localInfo = 'Password reset email sent! Check your inbox.';
              });
            },
          },
          [Component.text('Send reset link')],
        ),
        button(
          classes:
              'w-full h-12 rounded-xl font-semibold text-sm text-[#4f46e5] bg-transparent border-0 cursor-pointer hover:underline',
          attributes: {'type': 'button'},
          events: {'click': (_) => s.setState(() => s.authView = AuthView.login)},
          [Component.text('Back to Login')],
        ),
      ],
    );
  }

  @override
  Component build(BuildContext context) {
    final isDark = component.state.isDark;
    return AuthBrandShell(
      isDark: isDark,
      card: _card(isDark: isDark),
      cardMobile: _card(isDark: isDark, widthCls: 'w-full'),
    );
  }
}
