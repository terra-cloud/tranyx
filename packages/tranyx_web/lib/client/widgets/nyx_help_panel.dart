import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../services/tranyx_firebase_ai.dart';
import '../../services/web_interop.dart';

/// Floating Nyx help chat. Guests get a smaller hourly cap. No account data is sent.
class NyxHelpPanel extends StatefulComponent {
  const NyxHelpPanel();

  @override
  State<NyxHelpPanel> createState() => _NyxHelpPanelState();
}

class _NyxHelpPanelState extends State<NyxHelpPanel> {
  bool _open = false;
  bool _busy = false;
  String _draft = '';
  final List<({bool user, String text})> _turns = [
    (user: false, text: 'Hi, I’m Nyx. Ask how gigs, rentals, escrow, or your Tranyx wallet works.'),
  ];

  Future<void> _send() async {
    final text = _draft.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _draft = '';
      _turns.add((user: true, text: text));
    });
    final signedIn = SessionStorage.idToken != null && SessionStorage.idToken!.isNotEmpty;
    final answer = await TranyxFirebaseAi().reply(
      message: text,
      signedIn: signedIn,
      idToken: SessionStorage.idToken,
    );
    final shown = answer == 'TRANSFER_TO_AGENT'
        ? 'I can hand this to a person from Profile → Support. I can’t see your account from here.'
        : answer;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _turns.add((user: false, text: shown));
    });
  }

  @override
  Component build(BuildContext context) {
    return div(classes: 'fixed bottom-24 right-4 md:bottom-16 md:right-6 z-[70] flex flex-col items-end gap-3', [
      if (_open)
        div(
          classes:
              'w-[min(100vw-2rem,22rem)] h-[26rem] flex flex-col rounded-2xl border border-zinc-800 bg-zinc-950 text-zinc-100 shadow-2xl overflow-hidden',
          [
            div(classes: 'px-4 py-3 border-b border-zinc-800 flex items-center justify-between', [
              div([
                p(classes: 'text-sm font-bold', [.text('Nyx')]),
                p(classes: 'text-[11px] text-zinc-400', [.text('Tranyx help only')]),
              ]),
              button(
                classes: 'text-zinc-400 hover:text-white text-sm px-2',
                events: {'click': (_) => setState(() => _open = false)},
                [.text('Close')],
              ),
            ]),
            div(classes: 'flex-1 overflow-y-auto px-3 py-3 space-y-2', [
              for (final turn in _turns)
                div(
                  classes: turn.user
                      ? 'ml-8 rounded-xl bg-emerald-500/15 border border-emerald-500/20 px-3 py-2 text-sm'
                      : 'mr-8 rounded-xl bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm text-zinc-200',
                  [.text(turn.text)],
                ),
              if (_busy) p(classes: 'text-xs text-zinc-500', [.text('Nyx is typing…')]),
            ]),
            div(classes: 'p-3 border-t border-zinc-800 flex gap-2', [
              input(
                type: InputType.text,
                classes:
                    'flex-1 rounded-xl bg-zinc-900 border border-zinc-800 px-3 py-2 text-sm outline-none focus:border-emerald-500',
                attributes: {
                  'placeholder': 'Ask about gigs, rentals, or your wallet',
                  'value': _draft,
                  'autocomplete': 'off',
                },
                events: {
                  'input': (e) => setState(() => _draft = getInputValue(e.target)),
                },
              ),
              button(
                classes: 'rounded-xl bg-emerald-500 text-zinc-950 text-sm font-bold px-3 disabled:opacity-40',
                events: {'click': (_) => _send()},
                [.text('Send')],
              ),
            ]),
          ],
        ),
      button(
        classes:
            'h-12 px-4 rounded-full bg-emerald-500 text-zinc-950 text-sm font-bold shadow-lg hover:bg-emerald-400',
        attributes: {'aria-label': _open ? 'Close Nyx help' : 'Open Nyx help'},
        events: {'click': (_) => setState(() => _open = !_open)},
        [.text(_open ? 'Hide Nyx' : 'Ask Nyx')],
      ),
    ]);
  }
}
