import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';

class SessionExpiredModalComponent extends StatelessComponent {
  final TranyxAppState state;
  const SessionExpiredModalComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;

    return div(
      classes: 'fixed inset-0 z-[10000] flex items-center justify-center p-4 bg-black/60 backdrop-blur-md animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-md rounded-3xl border p-6 relative overflow-hidden transition-all duration-300 '
              '${isDark ? "bg-zinc-900/95 border-zinc-800 text-white" : "bg-white/95 border-zinc-200 text-zinc-800 shadow-2xl"}',
          [
            // Premium background gradient flare
            div(
              [],
              classes: 'absolute top-0 right-0 w-32 h-32 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none',
            ),

            // Header/Icon
            div(classes: 'flex flex-col items-center text-center gap-2 mb-6 mt-4 relative z-10', [
              div(
                classes: 'p-4 rounded-full bg-amber-500/15 text-amber-500 mb-2 border border-amber-500/20',
                [lIcon('alert-triangle', cls: 'w-10 h-10 animate-pulse')],
              ),
              h3(classes: 'text-2xl font-bold tracking-tight', [
                Component.text('Session Expired'),
              ]),
              p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"} px-4 leading-relaxed', [
                Component.text('your session has expired, please relogin'),
              ]),
            ]),

            // Action Button
            div(classes: 'flex flex-col gap-2.5 relative z-10', [
              button(
                classes:
                    'w-full py-4 rounded-2xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2 border-0 cursor-pointer',
                events: {
                  'click': (_) {
                    s.setState(() {
                      s.showSessionExpiredModal = false;
                    });
                    s.handleLogout();
                  }
                },
                [
                  Component.text('Relogin'),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }
}
