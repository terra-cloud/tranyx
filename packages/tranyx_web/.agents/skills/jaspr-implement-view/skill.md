# Skill: Implement a Jaspr View Component

## Purpose
Guides an agent through implementing a full-fidelity Jaspr `StatelessComponent` view for the Tranyx web dashboard, matching the React reference prototype.

## Rules
1. Always `import 'package:jaspr/dom.dart'` and `import 'package:jaspr/jaspr.dart'`
2. Use `Component.text('...')` — never call `text(...)` directly
3. `build()` must return a single root `Component`
4. Use `lIcon(name, cls: 'w-5 h-5')` from `ui_helpers.dart` for all Lucide icons
5. All Tailwind classes are plain strings — no Dart calls inside them
6. Conditional rendering: use Dart `if (condition) widget` inside list literals
7. State access: receive `TranyxAppState state` as constructor param and call `state.setState(() { ... })`
8. No local state in StatelessComponent — push all state mutations up to `TranyxAppState`

## File Template
```dart
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';
import '../../state/app_state.dart';

class XxxViewComponent extends StatelessComponent {
  final TranyxAppState state;
  const XxxViewComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    // build the UI...
    return div(classes: '...', [...]);
  }
}
```

## Dark Mode Convention
- Dark card: `bg-zinc-900 border-zinc-800`
- Light card: `bg-white border-zinc-200 shadow-sm`
- Dark text: `text-zinc-200`, secondary: `text-zinc-500`
- Light text: `text-zinc-800`, secondary: `text-zinc-400`

## Icon Names (Lucide)
Common names: `home`, `briefcase`, `car`, `user`, `moon`, `sun`, `search`, `bell`, `hexagon`,
`chevron-right`, `star`, `map-pin`, `building`, `arrow-right`, `settings`, `credit-card`,
`shield`, `help-circle`, `log-out`, `crown`, `mail`, `lock`, `user-circle`, `arrow-left`,
`shield-check`, `file-text`, `plus`, `alert-circle`, `message-square`, `phone`,
`check-circle-2`, `clock`, `timer`, `menu`, `camera`, `send`, `sparkles`, `loader-2`,
`hourglass`, `paintbrush`, `layout-grid`, `wrench`, `bug`, `key`, `shirt`, `flower-2`,
`waves`, `package`, `utensils`, `truck`, `heart`, `activity`, `code`, `pen-tool`,
`calculator`, `palette`, `scale`, `graduation-cap`, `headset`, `wind`, `monitor`,
`trending-up`, `stethoscope`, `book-open`, `edit-2`, `globe`, `wallet`, `refresh-cw`,
`droplet`, `hammer`, `zap`
