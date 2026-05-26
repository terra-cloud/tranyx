// Shared Jaspr UI helpers.
// Rules:
// - Use Component.text('...') — NOT text('...')
// - build() returns Component (single root)
// - CSS class strings are plain Tailwind tokens — no Dart calls inside them
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

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

/// Logo component utilizing the new logo.svg.
Component svgLogo({String size = 'w-8 h-8'}) {
  return img(
    src: '/images/logo.svg',
    classes: '$size object-contain',
    attributes: {'alt': 'Tranyx Logo'},
  );
}

/// A high-fidelity inline SVG Google icon.
Component googleSvgIcon({String size = 'w-5 h-5'}) {
  return svg(
    classes: size,
    attributes: {
      'viewBox': '0 0 24 24',
      'fill': 'none',
      'xmlns': 'http://www.w3.org/2000/svg',
    },
    [
      path(
        attributes: {
          'd':
              'M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z',
          'fill': '#4285F4',
        },
        [],
      ),
      path(
        attributes: {
          'd':
              'M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z',
          'fill': '#34A853',
        },
        [],
      ),
      path(
        attributes: {
          'd':
              'M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z',
          'fill': '#FBBC05',
        },
        [],
      ),
      path(
        attributes: {
          'd':
              'M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z',
          'fill': '#EA4335',
        },
        [],
      ),
    ],
  );
}

/// A high-fidelity inline SVG Phantom Wallet icon.
Component phantomSvgIcon({String size = 'w-5 h-5'}) {
  return svg(
    classes: size,
    attributes: {
      'viewBox': '0 0 32 32',
      'fill': 'none',
      'xmlns': 'http://www.w3.org/2000/svg',
    },
    [
      path(
        attributes: {
          'fill-rule': 'evenodd',
          'clip-rule': 'evenodd',
          'd':
              'M21.2 12.3c-.6-.6-1.5-.9-2.5-1.1-2-.3-3.9.7-4.7 2.5l-.4 1c-.1.4-.6.6-1 .6-.9-.1-1.6.4-1.8 1.3-.1.7.3 1.4 1 1.6.4.1.6.4.6.8v3.8c0 .9.7 1.6 1.6 1.6.8 0 1.5-.6 1.6-1.4l.3-2.3c0-.4.4-.7.8-.7.4 0 .7.3.7.7l-.1 2.4c0 .9.6 1.7 1.6 1.7.9 0 1.7-.7 1.7-1.6l.2-4.8c0-.1 0-.3.1-.4.9-.9 2.1-1.4 3.4-1.4.8 0 1.5-.5 1.6-1.3.2-1.3-.5-2.6-1.8-2.9zM15.5 16.5c-.5 0-.9-.4-.9-.9s.4-.9.9-.9.9.4.9.9-.4.9-.9.9zm3.7 0c-.5 0-.9-.4-.9-.9s.4-.9.9-.9.9.4.9.9-.4.9-.9.9z',
          'fill': '#AB9FF2',
        },
        [],
      ),
    ],
  );
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
  bool isPassword = false,
  bool isPasswordVisible = false,
  void Function()? onTogglePassword,
}) {
  final borderCls = isDark
      ? 'bg-zinc-900 border-zinc-800 focus-within:border-indigo-500'
      : 'bg-white border-zinc-200 focus-within:border-indigo-500 shadow-sm';

  final inputId = label.isNotEmpty
      ? label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      : 'input_${placeholder.hashCode}';

  return div(classes: 'p-4 rounded-2xl border transition-colors $borderCls', [
    if (label.isNotEmpty)
      span(
        classes: 'block text-xs font-medium mb-1 ${isDark ? 'text-zinc-500' : 'text-zinc-400'}',
        [Component.text(label)],
      ),
    div(classes: 'flex items-center justify-between', [
      div(classes: 'flex items-center flex-1', [
        if (iconName.isNotEmpty) lIcon(iconName, cls: 'w-5 h-5 mr-3 ${isDark ? 'text-zinc-600' : 'text-zinc-400'}'),
        input<String>(
          classes:
              'bg-transparent border-none outline-none w-full text-sm md:text-base font-medium ${isDark ? 'text-zinc-200' : 'text-zinc-900'}',
          type: (isPassword && isPasswordVisible)
              ? InputType.text
              : (type == 'password' ? InputType.password : (type == 'email' ? InputType.email : InputType.text)),
          value: value,
          attributes: {
            'placeholder': placeholder,
            if (type == 'date') 'type': 'date',
            'id': inputId,
            'name': inputId,
          },
          onInput: onChange,
        ),
      ]),
      if (isPassword && onTogglePassword != null)
        button(
          classes: 'p-1 rounded-lg hover:bg-zinc-500/10 focus:outline-none ml-2 transition-colors cursor-pointer border-0',
          events: {'click': (_) => onTogglePassword()},
          [
            lIcon(
              isPasswordVisible ? 'eye-off' : 'eye',
              cls: 'w-4 h-4 ${isDark ? 'text-zinc-500 hover:text-zinc-300' : 'text-zinc-400 hover:text-zinc-600'}',
            ),
          ],
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

/// Sub-view header with back button and title.
Component subViewHeader({
  required String title,
  required bool isDark,
  required void Function() onBack,
}) {
  return div(classes: 'flex items-center gap-4 mb-8', [
    button(
      classes:
          'p-2 rounded-full transition-all border flex items-center justify-center '
          '${isDark ? "bg-zinc-800/80 border-zinc-700/60 text-zinc-300 hover:bg-zinc-750 hover:text-white" : "bg-zinc-100 border-zinc-200 text-zinc-600 hover:bg-zinc-150 hover:text-zinc-800"}',
      events: {'click': (_) => onBack()},
      [lIcon('arrow-left', cls: 'w-5 h-5')],
    ),
    h2(classes: 'text-2xl md:text-3xl font-extrabold tracking-tight', [Component.text(title)]),
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
