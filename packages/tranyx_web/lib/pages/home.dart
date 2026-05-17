import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

@client
class Home extends StatefulComponent {
  const Home({super.key});

  @override
  State<Home> createState() => HomeState();
}

class HomeState extends State<Home> {
  @override
  Component build(BuildContext context) {
    return div(classes: 'min-h-[calc(100vh-80px)] flex flex-col', [
      // Hero Section
      section(classes: 'relative py-24 overflow-hidden', [
        // Background effects
        div(
          classes:
              'absolute top-0 left-1/2 -translate-x-1/2 w-full max-w-4xl h-96 bg-indigo-600/10 blur-[120px] rounded-full -z-10',
          [],
        ),

        div(classes: 'max-w-7xl mx-auto px-4 text-center', [
          div(
            classes:
                'inline-flex items-center gap-2 px-4 py-2 rounded-full bg-indigo-500/10 border border-indigo-500/20 text-indigo-400 text-xs font-bold mb-8 animate-fade-up',
            [
              span(classes: 'w-2 h-2 rounded-full bg-indigo-500 animate-pulse', []),
              Component.text('NEW DASHBOARD FOR EMPLOYERS'),
            ],
          ),

          h1(
            classes: 'text-5xl md:text-7xl font-black text-white mb-8 tracking-tight animate-fade-up',
            [
              Component.text('Find the perfect '),
              span(classes: 'text-transparent bg-clip-text logo-gradient', [
                Component.text('Nyxian'),
              ]),
              br(),
              Component.text('for your next project.'),
            ],
          ),

          p(classes: 'text-zinc-400 text-xl max-w-2xl mx-auto mb-12 animate-fade-up', [
            Component.text(
              'From home repairs to software development, connect with skilled workers instantly. Secure payments, verified profiles, and seamless project management.',
            ),
          ]),

          div(classes: 'flex flex-col sm:flex-row items-center justify-center gap-4 animate-fade-up', [
            Link(
              to: '/post-job',
              classes:
                  'w-full sm:w-auto px-8 py-4 rounded-2xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-lg transition-all shadow-xl shadow-indigo-500/25 flex items-center justify-center gap-3',
              children: [
                Component.text('Post a Gig Now'),
                i([], classes: 'w-5 h-5', attributes: {'data-lucide': 'arrow-right'}),
              ],
            ),
            button(
              classes:
                  'w-full sm:w-auto px-8 py-4 rounded-2xl bg-zinc-900 border border-zinc-800 text-zinc-300 font-bold text-lg hover:bg-zinc-800 transition-all',
              [Component.text('Browse Nyxians')],
            ),
          ]),
        ]),
      ]),

      // Stats/Trust Section
      section(classes: 'py-16 border-t border-zinc-900', [
        div(classes: 'max-w-7xl mx-auto px-4 grid grid-cols-2 md:grid-cols-4 gap-8', [
          _buildStat('10k+', 'Verified Nyxians'),
          _buildStat('50k+', 'Gigs Completed'),
          _buildStat('4.9/5', 'Average Rating'),
          _buildStat('24/7', 'Support Available'),
        ]),
      ]),
    ]);
  }

  Component _buildStat(String value, String label) {
    return div(classes: 'text-center animate-fade-up', [
      div(classes: 'text-3xl font-black text-white mb-1', [Component.text(value)]),
      div(classes: 'text-sm text-zinc-500 font-medium', [Component.text(label)]),
    ]);
  }
}
