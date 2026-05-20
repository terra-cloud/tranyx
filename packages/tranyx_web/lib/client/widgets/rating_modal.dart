import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import '../tranyx_app.dart';
import '../../components/ui_helpers.dart';

class RatingModalComponent extends StatefulComponent {
  final TranyxAppState state;
  const RatingModalComponent({required this.state, super.key});

  @override
  State<RatingModalComponent> createState() => _RatingModalComponentState();
}

class _RatingModalComponentState extends State<RatingModalComponent> {
  int _hoveredScore = 0;
  String _comment = '';

  @override
  Component build(BuildContext context) {
    final s = component.state;
    final isDark = s.isDark;

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-md animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-md rounded-3xl border p-6 relative overflow-hidden transition-all duration-300 '
              '${isDark ? "bg-zinc-900 border-zinc-800 text-white" : "bg-white border-zinc-200 text-zinc-800 shadow-2xl"}',
          [
            // Header
            div(classes: 'flex flex-col items-center text-center gap-2 mb-6', [
              div(
                classes: 'p-4 rounded-2xl bg-indigo-500/10 text-indigo-400 mb-2',
                [lIcon('star', cls: 'w-10 h-10 animate-pulse')],
              ),
              h3(classes: 'text-2xl font-bold tracking-tight', [
                Component.text('Rate ${s.ratingTargetName ?? "User"}'),
              ]),
              p(classes: 'text-sm ${isDark ? "text-zinc-400" : "text-zinc-500"} px-4', [
                Component.text('Share your experience to help the community grow and maintain trust.'),
              ]),
            ]),

            // Interactive Star Rating
            div(
              classes: 'flex items-center justify-center gap-3 mb-6',
              [
                for (int i = 1; i <= 5; i++)
                  button(
                    classes: 'p-1 hover:scale-125 transition-transform outline-none',
                    events: {
                      'mouseenter': (_) => setState(() => _hoveredScore = i),
                      'mouseleave': (_) => setState(() => _hoveredScore = 0),
                      'click': (_) => setState(() => s.ratingScore = i),
                    },
                    [
                      _buildStarIcon(i, s.ratingScore, _hoveredScore),
                    ],
                  ),
              ],
            ),

            // Rating Comment Area
            div(classes: 'space-y-2 mb-6', [
              p(
                classes: 'text-xs font-semibold uppercase tracking-wider ${isDark ? "text-zinc-500" : "text-zinc-400"}',
                [Component.text('Optional Review Comment')],
              ),
              textarea(
                classes:
                    'w-full px-4 py-3 text-sm rounded-2xl border outline-none transition-colors resize-none h-24 '
                    '${isDark ? "bg-zinc-800 border-zinc-700 text-white focus:border-indigo-500" : "bg-zinc-50 border-zinc-200 text-zinc-900 focus:border-indigo-500"}',
                attributes: {'placeholder': 'How did the task go? Excellent communication? Professional work?'},
                onInput: (v) => _comment = v,
                [Component.text(_comment)],
              ),
            ]),

            // Buttons
            div(classes: 'flex flex-col gap-2.5', [
              button(
                classes: (s.ratingScore == 0 || s.isSubmittingRating)
                    ? 'w-full py-4 rounded-2xl font-bold text-white bg-indigo-500/50 cursor-not-allowed text-center'
                    : 'w-full py-4 rounded-2xl font-bold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center justify-center gap-2',
                events: (s.ratingScore == 0 || s.isSubmittingRating)
                    ? {}
                    : {'click': (_) => s.handleConfirmRating(s.ratingScore, _comment)},
                [
                  if (s.isSubmittingRating) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                  Component.text(s.isSubmittingRating ? 'Submitting...' : 'Submit Rating'),
                ],
              ),
              button(
                classes:
                    'w-full py-3.5 rounded-2xl font-semibold text-center transition-colors '
                    '${isDark ? "text-zinc-400 hover:text-white bg-zinc-800/40 hover:bg-zinc-800" : "text-zinc-500 hover:text-zinc-700 bg-zinc-50 hover:bg-zinc-100"}',
                events: {'click': (_) => s.handleSkipRating()},
                [Component.text('Skip rating')],
              ),
            ]),
          ],
        ),
      ],
    );
  }

  Component _buildStarIcon(int index, int activeScore, int hoveredScore) {
    final isStarred = index <= (hoveredScore > 0 ? hoveredScore : activeScore);
    return span(
      classes: 'inline-flex items-center justify-center',
      [
        svg(
          [
            polygon(
              [],
              points: '12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2',
            ),
          ],
          attributes: {
            'viewBox': '0 0 24 24',
            'fill': isStarred ? '#fbbf24' : 'none',
            'stroke': isStarred ? '#fbbf24' : 'currentColor',
            'stroke-width': '2',
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
          },
          classes: 'w-8 h-8 ${isStarred ? "text-amber-400" : "text-zinc-500"}',
        ),
      ],
    );
  }
}
