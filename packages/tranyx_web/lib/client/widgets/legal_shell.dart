import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;

import '../../services/web_interop.dart';

enum LegalTab { privacy, terms, about }

class LegalSectionData {
  final String id;
  final String title;
  final String? lead;
  final List<String> paragraphs;
  final List<String> bullets;

  const LegalSectionData({
    required this.id,
    required this.title,
    this.lead,
    this.paragraphs = const [],
    this.bullets = const [],
  });
}

/// W06 Legal chrome — public nav, TOC, segmented tabs.
/// Theme: stored preference, else system (same key as main app).
class LegalShell extends StatefulComponent {
  final LegalTab tab;
  final String title;
  final String? intro;
  final List<LegalSectionData> sections;

  const LegalShell({
    required this.tab,
    required this.title,
    this.intro,
    required this.sections,
    super.key,
  });

  @override
  State<LegalShell> createState() => _LegalShellState();
}

class _LegalShellState extends State<LegalShell> {
  late bool _isDark;
  String? _activeSectionId;

  @override
  // ignore: invalid_use_of_protected_member
  void setState(void Function() fn) => super.setState(fn);

  @override
  void initState() {
    super.initState();
    _isDark = _resolveDark();
    _syncDom(_isDark);
    if (component.sections.isNotEmpty) {
      _activeSectionId = component.sections.first.id;
    }
  }

  bool _systemPrefersDark() {
    try {
      return web.window.matchMedia('(prefers-color-scheme: dark)').matches;
    } catch (_) {
      return false;
    }
  }

  bool _resolveDark() {
    final pref = SessionStorage.themePreference;
    if (pref == 'dark') return true;
    if (pref == 'light') return false;
    return _systemPrefersDark();
  }

  void _syncDom(bool dark) {
    try {
      final root = web.document.documentElement;
      if (root == null) return;
      if (dark) {
        root.classList.add('dark');
        root.classList.remove('light');
      } else {
        root.classList.add('light');
        root.classList.remove('dark');
      }
      root.setAttribute('data-theme', dark ? 'dark' : 'light');
      final htmlEl = root as web.HTMLElement;
      htmlEl.style.setProperty('color-scheme', dark ? 'dark' : 'light');
      web.document.body?.style.setProperty('background-color', dark ? '#09090b' : '#f4f4f5');
      web.document.body?.style.setProperty('color', dark ? '#fafafa' : '#18181b');
    } catch (_) {}
  }

  void _toggleTheme() {
    final nextDark = !_isDark;
    SessionStorage.themePreference = nextDark ? 'dark' : 'light';
    setState(() => _isDark = nextDark);
    _syncDom(nextDark);
  }

  void _go(String path) => web.window.location.assign(path);

  void _scrollTo(String id) {
    setState(() => _activeSectionId = id);
    try {
      final el = web.document.getElementById(id);
      el?.scrollIntoView();
    } catch (_) {}
  }

  @override
  Component build(BuildContext context) {
    final isDark = _isDark;
    final canvas = isDark ? 'bg-zinc-950' : 'bg-[#f4f4f5]';
    final surface = isDark ? 'bg-zinc-900' : 'bg-white';
    final border = isDark ? 'border-zinc-800' : 'border-[#e4e4e7]';
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textSecondary = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    const link = 'text-[#4f46e5]';
    final subtle = isDark ? 'bg-zinc-800/80' : 'bg-[#fafafa]';
    final tocActive = isDark ? 'bg-indigo-500/15' : 'bg-[#eef2ff]';
    final strongBorder = isDark ? 'border-zinc-700' : 'border-[#d4d4d8]';
    final bodyMuted = isDark ? 'text-zinc-400' : 'text-[#52525b]';
    final bodyPrimary = isDark ? 'text-zinc-200' : 'text-[#18181b]';
    final bullet = isDark ? 'bg-indigo-400' : 'bg-[#a855f7]';

    Component navLink(String label, LegalTab tab, String href) {
      final active = component.tab == tab;
      return button(
        classes:
            'bg-transparent border-0 cursor-pointer p-0 text-sm leading-5 tracking-[0.1px] ${active ? "font-semibold $link" : "font-normal $textSecondary hover:text-[#4f46e5]"}',
        attributes: {'type': 'button'},
        events: {'click': (_) => _go(href)},
        [Component.text(label)],
      );
    }

    Component seg(String label, LegalTab tab, String href) {
      final active = component.tab == tab;
      return button(
        classes:
            'h-9 px-4 rounded-[10px] text-sm tracking-[0.1px] border-0 cursor-pointer whitespace-nowrap ${active ? "$surface font-semibold $textPrimary shadow-[0px_4px_12px_rgba(9,9,11,0.04),0px_1px_2px_rgba(9,9,11,0.06)]" : "bg-transparent font-semibold $textSecondary"}',
        attributes: {'type': 'button'},
        events: {'click': (_) => _go(href)},
        [Component.text(label)],
      );
    }

    final toc = div(
      classes: 'hidden lg:flex flex-col gap-1 items-start w-[260px] shrink-0 sticky top-24 self-start',
      [
        p(
          classes: 'm-0 mb-1 font-semibold text-[11px] leading-4 tracking-[0.8px] uppercase $textSecondary',
          [Component.text('On this page')],
        ),
        for (final s in component.sections)
          button(
            classes:
                'w-full h-10 pl-3 rounded-[10px] text-left text-sm leading-5 border-0 cursor-pointer ${s.id == _activeSectionId ? "$tocActive $link" : "bg-transparent $textSecondary"}',
            attributes: {'type': 'button'},
            events: {'click': (_) => _scrollTo(s.id)},
            [Component.text(s.title)],
          ),
        div(classes: 'h-px w-full my-2 ${isDark ? "bg-zinc-800" : "bg-[#e4e4e7]"}', []),
        if (component.tab != LegalTab.terms)
          button(
            classes: 'bg-transparent border-0 cursor-pointer p-0 text-sm $link text-left',
            attributes: {'type': 'button'},
            events: {'click': (_) => _go('/terms-of-use')},
            [Component.text('Terms of Use · 8 sections')],
          ),
        if (component.tab != LegalTab.privacy)
          button(
            classes: 'bg-transparent border-0 cursor-pointer p-0 text-sm $link text-left',
            attributes: {'type': 'button'},
            events: {'click': (_) => _go('/privacy-policy')},
            [Component.text('Privacy Policy · 7 sections')],
          ),
        if (component.tab != LegalTab.about)
          button(
            classes: 'bg-transparent border-0 cursor-pointer p-0 text-sm $link text-left mt-1',
            attributes: {'type': 'button'},
            events: {'click': (_) => _go('/about')},
            [Component.text('About Tranyx')],
          ),
      ],
    );

    return div(
      classes: 'w06-legal min-h-screen w-full $canvas font-dm-sans $textPrimary',
      [
        div(
          classes: 'w-full h-[72px] $surface border-b $border flex items-center gap-3 md:gap-8 px-4 md:px-12',
          [
            button(
              classes: 'flex items-center gap-2.5 bg-transparent border-0 cursor-pointer p-0 shrink-0',
              attributes: {'type': 'button'},
              events: {'click': (_) => _go('/')},
              [
                div(
                  classes:
                      'size-8 rounded-[10px] flex items-center justify-center text-white font-black text-lg bg-gradient-to-r from-[#6366f1] to-[#a855f7]',
                  [Component.text('T')],
                ),
                span(
                  classes: 'font-semibold text-xl leading-7 tracking-[-0.2px] $textPrimary',
                  [Component.text('Tranyx')],
                ),
              ],
            ),
            div(classes: 'flex-1 min-w-0', []),
            div(classes: 'hidden md:flex items-center gap-6 shrink-0', [
              navLink('Privacy Policy', LegalTab.privacy, '/privacy-policy'),
              navLink('Terms of Use', LegalTab.terms, '/terms-of-use'),
              navLink('About', LegalTab.about, '/about'),
            ]),
            button(
              classes:
                  'size-11 rounded-xl $subtle flex items-center justify-center border-0 cursor-pointer $textSecondary shrink-0',
              attributes: {'type': 'button', 'aria-label': 'Toggle theme'},
              events: {'click': (_) => _toggleTheme()},
              [Component.text(isDark ? '☀' : '☾')],
            ),
            button(
              classes:
                  'hidden sm:flex h-12 px-5 rounded-xl border $strongBorder $surface font-semibold text-sm tracking-[0.1px] $textPrimary cursor-pointer shrink-0',
              attributes: {'type': 'button'},
              events: {'click': (_) => _go('/')},
              [Component.text('Sign In')],
            ),
            button(
              classes:
                  'h-12 px-5 rounded-xl font-semibold text-sm tracking-[0.1px] text-white bg-[#4f46e5] shadow-[0px_8px_10px_rgba(79,70,229,0.25)] border-0 cursor-pointer shrink-0',
              attributes: {'type': 'button'},
              events: {'click': (_) => _go('/')},
              [Component.text('Get Started')],
            ),
          ],
        ),
        div(
          classes:
              'w-full max-w-[1440px] mx-auto flex gap-8 lg:gap-16 items-start px-4 md:px-10 xl:px-40 pt-10 md:pt-14 pb-20',
          [
            toc,
            div(
              classes: 'flex-1 min-w-0 flex flex-col gap-4 items-start',
              [
                div(
                  classes: 'inline-flex gap-1 items-center p-1 rounded-[14px] border $border $subtle overflow-x-auto max-w-full',
                  [
                    seg('Privacy Policy', LegalTab.privacy, '/privacy-policy'),
                    seg('Terms of Use', LegalTab.terms, '/terms-of-use'),
                    seg('About', LegalTab.about, '/about'),
                  ],
                ),
                h1(
                  classes: 'm-0 font-bold text-[28px] md:text-[32px] leading-10 tracking-[-0.6px] $textPrimary',
                  [Component.text(component.title)],
                ),
                if (component.intro != null)
                  p(
                    classes: 'm-0 text-base leading-6 $textSecondary max-w-[796px]',
                    [Component.text(component.intro!)],
                  ),
                for (final s in component.sections)
                  div(
                    id: s.id,
                    classes: 'w-full flex flex-col gap-3 items-start pt-2 scroll-mt-28',
                    [
                      h2(
                        classes: 'm-0 font-semibold text-xl leading-7 tracking-[-0.2px] $textPrimary',
                        [Component.text(s.title)],
                      ),
                      if (s.lead != null)
                        p(classes: 'm-0 text-[15px] leading-[22px] $bodyMuted', [Component.text(s.lead!)]),
                      for (final para in s.paragraphs)
                        p(classes: 'm-0 text-[15px] leading-[22px] $bodyMuted', [Component.text(para)]),
                      for (final b in s.bullets)
                        div(classes: 'flex gap-2.5 items-start w-full', [
                          span(classes: 'mt-[8px] size-1.5 rounded-full shrink-0 $bullet', []),
                          p(
                            classes: 'm-0 flex-1 text-[15px] leading-[22px] $bodyPrimary',
                            [Component.text(b)],
                          ),
                        ]),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
