import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Soft CSS gradient orb (visible color + animated drift).
Component brandOrb(String posCls, String animCls) {
  return div(
    classes: 'brand-orb $animCls pointer-events-none absolute $posCls',
    attributes: {'aria-hidden': 'true'},
    [],
  );
}

/// Shared animated brand metaballs (soft continuous drift).
/// Classes: brand-blob + brand-blob-a/b/c (aliases of w01-blob keyframes).
/// Honors prefers-reduced-motion via styles.css.
Component brandBlob(String src, String posCls, String animCls, {required bool isDark}) {
  return img(
    src: src,
    classes:
        'brand-blob w01-blob $animCls pointer-events-none absolute max-w-none $posCls ${isDark ? "opacity-50" : ""}',
    attributes: {'alt': '', 'aria-hidden': 'true'},
  );
}

Component authFeatureRow(String iconSrc, String label, {required bool isDark}) {
  return div(classes: 'flex gap-3 items-center', [
    div(
      classes:
          '${isDark ? "bg-indigo-500/15" : "bg-[#eef2ff]"} flex items-center justify-center rounded-[10px] shrink-0 size-9',
      [
        img(src: iconSrc, classes: 'size-[18px]', attributes: {'alt': '', 'aria-hidden': 'true'}),
      ],
    ),
    p(
      classes:
          'font-semibold leading-[22px] text-[15px] m-0 ${isDark ? "text-zinc-50" : "text-[#18181b]"}',
      [Component.text(label)],
    ),
  ]);
}

/// Full-bleed auth split layout shared by W01–W04 + forgot.
/// Desktop ≥1024: brand 680 + form. Tablet: top band. Mobile: stack.
/// Blobs always animated unless reduced-motion.
class AuthBrandShell extends StatelessComponent {
  final bool isDark;
  final Component card;
  final Component? cardTablet;
  final Component? cardMobile;
  final Component? belowCard;
  final Component? legal;

  const AuthBrandShell({
    required this.isDark,
    required this.card,
    this.cardTablet,
    this.cardMobile,
    this.belowCard,
    this.legal,
    super.key,
  });

  List<Component> _desktopBlobs() => [
        brandOrb('left-[-80px] top-[320px]', 'brand-orb-a'),
        brandOrb('left-[340px] top-[80px]', 'brand-orb-b'),
        brandOrb('left-[280px] top-[600px]', 'brand-orb-c'),
        brandBlob('/images/w01/05633.svg', 'left-[-60px] top-[380px] size-[420px]', 'brand-blob-a w01-blob-a', isDark: isDark),
        brandBlob('/images/w01/54cd1.svg', 'left-[360px] top-[120px] size-[300px]', 'brand-blob-b w01-blob-b', isDark: isDark),
        brandBlob('/images/w01/1a12a.svg', 'left-[300px] top-[640px] size-[260px]', 'brand-blob-c w01-blob-c', isDark: isDark),
      ];

  List<Component> _tabletBlobs() => [
        brandOrb('left-[400px] top-[-140px]', 'brand-orb-a'),
        brandOrb('left-[560px] top-[40px]', 'brand-orb-b'),
        brandBlob('/images/w01/937b1.svg', 'left-[420px] top-[-120px] size-[360px]', 'brand-blob-a w01-blob-a', isDark: isDark),
        brandBlob('/images/w01/1a12a.svg', 'left-[600px] top-[80px] size-[260px]', 'brand-blob-b w01-blob-b', isDark: isDark),
      ];

  List<Component> _mobileBlobs() => [
        brandOrb('left-[140px] top-[-160px]', 'brand-orb-a'),
        brandBlob('/images/w01/2f57f.svg', 'left-[160px] top-[-140px] size-[300px]', 'brand-blob-a w01-blob-a', isDark: isDark),
      ];

  @override
  Component build(BuildContext context) {
    final pageBg = isDark ? 'bg-zinc-950 text-zinc-50' : 'bg-[#f4f4f5] text-[#18181b]';
    final textPrimary = isDark ? 'text-zinc-50' : 'text-[#18181b]';
    final textSecondary = isDark ? 'text-zinc-400' : 'text-[#52525b]';

    final tabletCard = cardTablet ?? card;
    final mobileCard = cardMobile ?? card;

    final brandCopy = div(classes: 'relative z-10 flex flex-col gap-5 items-start', [
      div(classes: 'font-bold text-[48px] leading-[56px] tracking-[-1.2px] $textPrimary', [
        p(classes: 'm-0', [Component.text('Work. Earn. Rent.')]),
        p(classes: 'm-0', [Component.text('Discover.')]),
      ]),
      p(
        classes: 'm-0 font-normal text-base leading-6 $textSecondary w-full max-w-[480px]',
        [
          Component.text(
            'Find freelance gigs, rent vehicles and properties, and earn securely on the all-in-one P2P platform. Powered by Web3 escrow and verified Nyxians in the Philippines.',
          ),
        ],
      ),
      div(classes: 'flex flex-col gap-3 items-start pt-2', [
        authFeatureRow('/images/w01/c1457.svg', 'Freelance gigs near you', isDark: isDark),
        authFeatureRow('/images/w01/a193d.svg', 'Vehicle & space rentals', isDark: isDark),
        authFeatureRow('/images/w01/d726a.svg', 'Escrow-protected payments', isDark: isDark),
      ]),
    ]);

    final logo = div(classes: 'relative z-10 flex items-center', [
      img(
        src: '/images/w01/fef74.png',
        classes: 'h-10 w-[51px] object-contain',
        attributes: {'alt': 'Tranyx'},
      ),
    ]);

    final overline = p(
      classes:
          'relative z-10 m-0 font-semibold text-[11px] leading-4 tracking-[0.8px] $textSecondary uppercase',
      [Component.text('One Platform. Endless Opportunities.')],
    );

    return div(
      classes: 'w01-signin auth-brand-shell w-full min-h-screen $pageBg font-dm-sans',
      [
        // Desktop ≥1024
        div(
          classes: 'hidden lg:flex w-full min-h-screen items-stretch',
          [
            div(
              classes:
                  'auth-brand-panel relative w-[680px] shrink-0 flex flex-col justify-between overflow-hidden px-[72px] py-16',
              [
                ..._desktopBlobs(),
                logo,
                brandCopy,
                overline,
              ],
            ),
            div(
              classes: 'flex flex-1 flex-col gap-6 items-center justify-center min-w-0 px-12 py-10 $pageBg',
              [
                card,
                if (belowCard != null) belowCard!,
                if (legal != null) legal!,
              ],
            ),
          ],
        ),

        // Tablet 640–1023
        div(
          classes: 'hidden sm:flex lg:hidden w-full min-h-screen flex-col',
          [
            div(
              classes:
                  'auth-brand-panel relative w-full h-[300px] shrink-0 overflow-hidden px-14 py-10 flex flex-col gap-4 items-start',
              [
                ..._tabletBlobs(),
                div(classes: 'relative z-10 flex items-center', [
                  img(
                    src: '/images/w01/fef74.png',
                    classes: 'h-9 w-[46px] object-contain',
                    attributes: {'alt': 'Tranyx'},
                  ),
                ]),
                p(
                  classes:
                      'relative z-10 m-0 font-bold text-[32px] leading-10 tracking-[-0.6px] $textPrimary',
                  [Component.text('Work. Earn. Rent. Discover.')],
                ),
                p(
                  classes: 'relative z-10 m-0 font-normal text-base leading-6 $textSecondary max-w-[520px]',
                  [
                    Component.text(
                      'Find freelance gigs, rent vehicles and properties, and earn securely on the all-in-one P2P platform.',
                    ),
                  ],
                ),
              ],
            ),
            div(
              classes: 'flex flex-1 flex-col gap-5 items-center w-full pt-10 px-6 pb-10 $pageBg',
              [
                tabletCard,
                if (belowCard != null) belowCard!,
                if (legal != null) legal!,
              ],
            ),
          ],
        ),

        // Mobile <640
        div(
          classes:
              'flex sm:hidden relative w-full min-h-screen flex-col gap-5 items-start px-4 pt-6 pb-8 overflow-hidden $pageBg',
          [
            ..._mobileBlobs(),
            div(classes: 'relative z-10 flex items-center', [
              img(
                src: '/images/w01/fef74.png',
                classes: 'h-8 w-[41px] object-contain',
                attributes: {'alt': 'Tranyx'},
              ),
            ]),
            p(
              classes:
                  'relative z-10 m-0 font-bold text-2xl leading-8 tracking-[-0.4px] $textPrimary',
              [Component.text('Work. Earn. Rent. Discover.')],
            ),
            div(classes: 'relative z-10 w-full', [mobileCard]),
            if (belowCard != null) div(classes: 'relative z-10 w-full', [belowCard!]),
            if (legal != null) div(classes: 'relative z-10 w-full flex justify-center', [legal!]),
          ],
        ),
      ],
    );
  }
}
