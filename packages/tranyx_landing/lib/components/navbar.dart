import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

@client
class Navbar extends StatefulComponent {
  const Navbar({super.key});

  @override
  State<Navbar> createState() => _NavbarState();
}

class _NavbarState extends State<Navbar> {
  bool _mobileMenuOpen = false;

  void _toggleMobileMenu() {
    setState(() {
      _mobileMenuOpen = !_mobileMenuOpen;
    });
  }

  void _closeMobileMenu() {
    if (_mobileMenuOpen) {
      setState(() {
        _mobileMenuOpen = false;
      });
    }
  }

  @override
  Component build(BuildContext context) {
    return header(
      classes:
          'sticky top-0 z-50 w-full border-b border-zinc-800/80 bg-zinc-950/85 backdrop-blur-xl transition-all duration-200',
      [
        div(classes: 'max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-20 flex items-center justify-between', [
          // Logo & Brand
          a(
            href: '#top',
            events: {'click': (e) => _closeMobileMenu()},
            classes: 'flex items-center gap-3 group focus:outline-none focus:ring-2 focus:ring-indigo-500 rounded-lg p-1',
            [
              img(
                src: '/images/logo.png',
                classes:
                    'w-10 h-10 object-contain group-hover:scale-105 transition-transform duration-300 drop-shadow-[0_0_12px_rgba(99,102,241,0.5)]',
                attributes: {'alt': 'Tranyx Logo', 'width': '40', 'height': '40'},
              ),
              div(classes: 'flex flex-col', [
                div(classes: 'flex items-center gap-2', [
                  span(classes: 'text-2xl font-black text-white tracking-tight', [
                    Component.text('TRANYX'),
                  ]),
                  span(
                    classes:
                        'text-[10px] font-bold uppercase tracking-wider px-1.5 py-0.5 rounded bg-indigo-500/20 text-indigo-400 border border-indigo-500/30',
                    [Component.text('PH')],
                  ),
                ]),
                span(classes: 'text-[11px] text-zinc-400 font-medium -mt-1 hidden sm:inline', [
                  Component.text('Work • Logistics • Escrow'),
                ]),
              ]),
            ],
          ),

          // Desktop Navigation Links
          nav(classes: 'hidden lg:flex items-center gap-1', [
            _buildNavLink('Verticals', '#verticals'),
            _buildNavLink('How It Works', '#how-it-works'),
            _buildNavLink('QR Security', '#qr-security'),
            _buildNavLink('Escrow & Web3', '#escrow'),
            _buildNavLink('Calculator', '#calculator'),
            _buildNavLink('FAQ', '#faq'),
          ]),

          // Action Button: Explore App
          div(classes: 'hidden sm:flex items-center gap-3', [
            a(
              href: 'http://tranyx.app',
              attributes: {
                'target': '_blank',
                'rel': 'noopener noreferrer',
              },
              classes:
                  'relative group overflow-hidden px-6 py-2.5 rounded-full font-bold text-sm text-white bg-gradient-to-r from-indigo-600 via-indigo-500 to-purple-600 hover:from-indigo-500 hover:to-purple-500 transition-all duration-300 shadow-lg shadow-indigo-600/30 hover:shadow-indigo-600/50 hover:scale-105 active:scale-95 flex items-center gap-2',
              [
                span([Component.text('Explore App')]),
                i(
                  classes: 'w-4 h-4 transition-transform group-hover:translate-x-1',
                  attributes: {'data-lucide': 'external-link'},
                  [],
                ),
              ],
            ),
          ]),

          // Mobile Menu Button
          div(classes: 'flex lg:hidden items-center gap-2', [
            a(
              href: 'http://tranyx.app',
              attributes: {
                'target': '_blank',
                'rel': 'noopener noreferrer',
              },
              classes:
                  'sm:hidden px-3.5 py-1.5 rounded-full text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-500 flex items-center gap-1.5',
              [
                Component.text('App'),
                i(classes: 'w-3.5 h-3.5', attributes: {'data-lucide': 'external-link'}, []),
              ],
            ),
            button(
              events: {'click': (e) => _toggleMobileMenu()},
              classes:
                  'p-2 rounded-xl bg-zinc-900 border border-zinc-800 text-zinc-300 hover:text-white hover:bg-zinc-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 transition-colors',
              attributes: {
                'aria-label': 'Toggle navigation menu',
                'aria-expanded': _mobileMenuOpen ? 'true' : 'false',
              },
              [
                i(
                  classes: 'w-6 h-6',
                  attributes: {'data-lucide': _mobileMenuOpen ? 'x' : 'menu'},
                  [],
                ),
              ],
            ),
          ]),
        ]),

        // Mobile Dropdown Menu
        if (_mobileMenuOpen)
          div(
            classes:
                'lg:hidden border-b border-zinc-800 bg-zinc-950/95 backdrop-blur-2xl px-4 pt-3 pb-6 animate-fade-up',
            [
              div(classes: 'flex flex-col space-y-2', [
                _buildMobileNavLink('Verticals', '#verticals'),
                _buildMobileNavLink('How It Works', '#how-it-works'),
                _buildMobileNavLink('Dual QR Security', '#qr-security'),
                _buildMobileNavLink('Smart Escrow & Web3', '#escrow'),
                _buildMobileNavLink('Income Calculator', '#calculator'),
                _buildMobileNavLink('Frequently Asked Questions', '#faq'),
                div(classes: 'pt-3 border-t border-zinc-800/80', [
                  a(
                    href: 'http://tranyx.app',
                    attributes: {
                      'target': '_blank',
                      'rel': 'noopener noreferrer',
                    },
                    classes:
                        'w-full py-3 rounded-xl font-bold text-center text-white bg-gradient-to-r from-indigo-600 to-purple-600 hover:from-indigo-500 hover:to-purple-500 shadow-lg shadow-indigo-600/30 flex items-center justify-center gap-2',
                    [
                      Component.text('Explore Official App (tranyx.app)'),
                      i(classes: 'w-4 h-4', attributes: {'data-lucide': 'external-link'}, []),
                    ],
                  ),
                ]),
              ]),
            ],
          ),
      ],
    );
  }

  Component _buildNavLink(String title, String href) {
    return a(
      href: href,
      classes:
          'px-3.5 py-2 rounded-lg text-sm font-medium text-zinc-300 hover:text-white hover:bg-zinc-900/80 transition-all duration-150',
      [Component.text(title)],
    );
  }

  Component _buildMobileNavLink(String title, String href) {
    return a(
      href: href,
      events: {'click': (e) => _closeMobileMenu()},
      classes:
          'px-4 py-2.5 rounded-lg text-base font-medium text-zinc-300 hover:text-white hover:bg-zinc-900 transition-colors',
      [Component.text(title)],
    );
  }
}
