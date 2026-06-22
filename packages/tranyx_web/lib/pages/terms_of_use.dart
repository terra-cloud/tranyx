import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

@client
class TermsOfUse extends StatelessComponent {
  const TermsOfUse({super.key});

  @override
  Component build(BuildContext context) {
    return section(classes: 'py-20 px-4 min-h-[calc(100vh-80px)] flex flex-col items-center justify-center relative overflow-hidden', [
      // Background glow
      div(
        classes:
            'absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full max-w-4xl h-96 bg-indigo-600/10 blur-[120px] rounded-full -z-10',
        [],
      ),
      div(classes: 'w-full max-w-4xl bg-zinc-900/60 backdrop-blur-xl border border-zinc-800/80 rounded-3xl p-8 md:p-12 shadow-2xl relative z-10 animate-fade-up', [
        div(classes: 'flex justify-between items-center mb-8 pb-6 border-b border-zinc-800', [
          h1(classes: 'text-3xl md:text-4xl font-black text-white tracking-tight', [
            Component.text('Terms of Use'),
          ]),
          Link(
            to: '/',
            classes: 'px-4 py-2 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-zinc-300 text-sm font-bold transition-all flex items-center gap-2',
            children: [
              Component.text('← Back to Home'),
            ],
          ),
        ]),
        div(classes: 'space-y-6 text-zinc-300 leading-relaxed text-sm md:text-base', [
          p([
            Component.text('Welcome to Tranyx. By accessing or using our platform, website, or mobile application, you agree to be bound by these Terms of Use.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('1. User Conduct & Accounts'),
          ]),
          p([
            Component.text('You must be at least 18 years old to use this platform. You are responsible for maintaining the confidentiality of your account credentials and blockchain wallet keys. Any fraudulent or illegal activity will result in immediate suspension.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('2. Payments & Transaction Fees'),
          ]),
          p([
            Component.text('All payments made on Tranyx are processed securely via Solana blockchain or Xendit. Users are responsible for paying any transaction gas fees or processing fees associated with gigs, rentals, and escrows.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('3. Disclaimers & Limitation of Liability'),
          ]),
          p([
            Component.text('Tranyx is a decentralized platform connecting independent workers (Nyxians) with employers. We do not employ users and are not responsible for the performance, quality, or legality of gigs and rentals.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('4. Modifications to Terms'),
          ]),
          p([
            Component.text('We reserve the right to modify these Terms of Use at any time. Changes will be posted on this page with an updated revision date. Continued use of the platform constitutes agreement to the updated terms.'),
          ]),
        ]),
      ]),
    ]);
  }
}
