import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

class Header extends StatelessComponent {
  const Header({super.key});

  @override
  Component build(BuildContext context) {
    var activePath = context.url;

    return header(classes: 'sticky top-0 z-50 w-full border-b border-zinc-800/50 bg-zinc-950/80 backdrop-blur-xl', [
      div(classes: 'max-w-7xl mx-auto px-4 h-20 flex items-center justify-between', [
        // Logo
        Link(
          to: '/',
          classes: 'flex items-center gap-2 group',
          children: [
            img(
              src: '/images/logo.png',
              classes:
                  'w-9 h-9 object-contain group-hover:scale-105 transition-transform drop-shadow-sm',
              attributes: {'alt': 'Tranyx Logo'},
            ),
            span(classes: 'text-2xl font-black text-white tracking-tighter', [
              Component.text('TRANYX'),
            ]),
          ],
        ),

        // Navigation
        nav(classes: 'hidden md:flex items-center gap-1', [
          for (var route in [
            (label: 'Dashboard', path: '/'),
            (label: 'Post a Gig', path: '/post-job'),
            (label: 'About', path: '/about'),
          ])
            Link(
              to: route.path,
              classes:
                  'px-4 py-2 rounded-lg text-sm font-medium transition-all '
                  '${activePath == route.path ? 'text-white bg-zinc-900' : 'text-zinc-400 hover:Component.text-zinc-200 hover:bg-zinc-900/50'}',
              child: Component.text(route.label),
            ),
        ]),

        // Actions
        div(classes: 'flex items-center gap-4', [
          button(
            classes: 'hidden sm:block text-zinc-400 hover:text-zinc-200 transition-colors text-sm font-medium',
            [
              Component.text('Login'),
            ],
          ),
          Link(
            to: '/post-job',
            classes:
                'px-6 py-2.5 rounded-full bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-bold transition-all shadow-lg shadow-indigo-500/20 active:scale-95',
            child: Component.text('Post a Gig'),
          ),
        ]),
      ]),
    ]);
  }
}
