// Shared Jaspr UI helpers.
// Rules:
// - Use Component.text('...') — NOT text('...')
// - build() returns Component (single root)
// - CSS class strings are plain Tailwind tokens — no Dart calls inside them
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

/// Renders a Lucide icon via <i data-lucide="name" class="..."></i>
/// The MutationObserver in index.html auto-renders them via Lucide JS.
Component lIcon(String name, {String cls = 'w-5 h-5'}) {
  return span(
    classes: 'inline-flex items-center justify-center lucide-wrapper',
    [
      i(
        [],
        classes: cls,
        attributes: {'data-lucide': name},
      ),
    ],
  );
}

/// Gradient logo hexagon badge.
Component svgLogo({String size = 'w-8 h-8'}) {
  return div(classes: 'p-3 rounded-2xl logo-gradient flex items-center justify-center', [
    lIcon('hexagon', cls: '$size text-white'),
  ]);
}

/// Styled text input field with optional label and leading icon.
Component inputField({
  String label = '',
  String placeholder = '',
  String iconName = '',
  String type = 'text',
  String value = '',
  bool isDark = true,
  void Function(String)? onChange,
}) {
  final borderCls = isDark
      ? 'bg-zinc-900 border-zinc-800 focus-within:border-indigo-500'
      : 'bg-white border-zinc-200 focus-within:border-indigo-500 shadow-sm';

  return div(classes: 'p-4 rounded-2xl border transition-colors $borderCls', [
    if (label.isNotEmpty)
      span(
        classes: 'block text-xs font-medium mb-1 ${isDark ? 'text-zinc-500' : 'text-zinc-400'}',
        [Component.text(label)],
      ),
    div(classes: 'flex items-center', [
      if (iconName.isNotEmpty) lIcon(iconName, cls: 'w-5 h-5 mr-3 ${isDark ? 'text-zinc-600' : 'text-zinc-400'}'),
      input<String>(
        classes:
            'bg-transparent border-none outline-none w-full text-sm md:text-base font-medium ${isDark ? 'text-zinc-200' : 'text-zinc-900'}',
        type: type == 'password' ? InputType.password : (type == 'email' ? InputType.email : InputType.text),
        value: value,
        attributes: {
          'placeholder': placeholder,
        },
        onInput: onChange,
      ),
    ]),
  ]);
}

/// Pill/tag label.
Component tagChip(String label, bool isDark) {
  return span(
    classes:
        'px-4 py-2 rounded-lg text-sm font-medium ${isDark ? 'bg-zinc-800 text-zinc-300' : 'bg-zinc-100 text-zinc-700'}',
    [Component.text(label)],
  );
}

/// Badge with custom classes.
Component badge(String label, String cls) {
  return span(
    classes: 'px-2.5 py-1 rounded-md text-[10px] font-bold uppercase tracking-wider $cls',
    [Component.text(label)],
  );
}

/// Account type badge.
Component accountBadge(String acType) {
  final cls = acType == 'hybrid'
      ? 'bg-amber-500/20 text-amber-500'
      : acType == 'employer'
      ? 'bg-blue-500/20 text-blue-500'
      : 'bg-green-500/20 text-green-500';
  final label = acType == 'nyxian' ? 'Nyxian Worker' : '${acType[0].toUpperCase()}${acType.substring(1)} View';
  return badge(label, cls);
}

/// Sub-view header with back button (hidden on md+) and title.
Component subViewHeader({
  required String title,
  required bool isDark,
  required void Function() onBack,
}) {
  return div(classes: 'flex items-center gap-4 mb-8', [
    button(
      classes:
          'md:hidden p-2 rounded-full transition-colors ${isDark ? 'bg-zinc-800 text-zinc-300' : 'bg-zinc-200 text-zinc-600'}',
      events: {'click': (_) => onBack()},
      [lIcon('arrow-left')],
    ),
    h2(classes: 'text-2xl md:text-3xl font-bold tracking-tight', [Component.text(title)]),
  ]);
}

/// Verification row item.
Component verificationItem({required String title, required String status, required bool isDark}) {
  final verified = status == 'Verified';
  return div(
    classes:
        'flex items-center justify-between p-5 rounded-2xl border ${isDark ? 'bg-zinc-900 border-zinc-800' : 'bg-white border-zinc-200 shadow-sm'}',
    [
      span(
        classes: 'font-medium text-base ${isDark ? 'text-zinc-200' : 'text-zinc-800'}',
        [Component.text(title)],
      ),
      if (verified)
        span(
          classes: 'flex items-center gap-1.5 text-xs font-bold text-green-500 bg-green-500/10 px-3 py-1.5 rounded-md',
          [lIcon('shield-check', cls: 'w-4 h-4'), Component.text(' VERIFIED')],
        )
      else
        span(
          classes: 'text-xs font-bold text-amber-500 bg-amber-500/10 px-3 py-1.5 rounded-md',
          [Component.text('PENDING')],
        ),
    ],
  );
}

/// FAQ row button.
Component supportFaq({required String title, String iconName = 'file-text', required bool isDark}) {
  return button(
    classes:
        'w-full flex items-center justify-between p-5 rounded-2xl border transition-all text-left ${isDark ? 'bg-zinc-900 border-zinc-800 hover:bg-zinc-800' : 'bg-white border-zinc-200 shadow-sm hover:shadow-md'}',
    [
      div(classes: 'flex items-center gap-4', [
        lIcon(iconName, cls: 'w-5 h-5 ${isDark ? 'text-zinc-500' : 'text-zinc-400'}'),
        span(
          classes: 'font-medium text-base ${isDark ? 'text-zinc-200' : 'text-zinc-800'}',
          [Component.text(title)],
        ),
      ]),
      lIcon('chevron-right', cls: 'w-5 h-5 ${isDark ? 'text-zinc-700' : 'text-zinc-300'}'),
    ],
  );
}

/// Segmented control — pass selected value and list of (label, value) pairs.
Component segmentedControl({
  required List<(String label, String value)> options,
  required String selected,
  required bool isDark,
  required void Function(String) onChange,
}) {
  return div(
    classes:
        'flex p-1 rounded-2xl ${isDark ? 'bg-zinc-900 border border-zinc-800' : 'bg-zinc-100 border border-zinc-200'}',
    [
      for (final opt in options)
        button(
          classes:
              'flex-1 py-2.5 text-xs font-semibold rounded-xl transition-all ${selected == opt.$2 ? (isDark ? 'bg-zinc-800 text-white shadow-sm' : 'bg-white text-zinc-900 shadow-sm') : (isDark ? 'text-zinc-500 hover:text-zinc-300' : 'text-zinc-500 hover:text-zinc-700')}',
          events: {'click': (_) => onChange(opt.$2)},
          [Component.text(opt.$1)],
        ),
    ],
  );
}
