import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

@client
class PrivacyPolicy extends StatelessComponent {
  const PrivacyPolicy({super.key});

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
            Component.text('Privacy Policy'),
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
            Component.text('Last updated: June 22, 2026. At Tranyx, we prioritize your privacy and are committed to protecting your personal data.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('1. Information We Collect'),
          ]),
          p([
            Component.text('We collect information you provide directly to us when creating an account, posting gigs, renting vehicles, or interacting with the Solana blockchain. This includes:'),
          ]),
          ul(classes: 'list-disc pl-6 space-y-2 text-zinc-400', [
            li([Component.text('Profile Information: Name, email address, phone number, and account type.')]),
            li([Component.text('Web3 Wallet Data: Public keys and wallet signatures for authentication.')]),
            li([Component.text('Usage Details: Transaction history, ratings, and messaging interactions.')]),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('2. How We Use Your Information'),
          ]),
          p([
            Component.text('We use the information we collect to provide, maintain, and improve our services, facilitate secure payments via Xendit and Solana, and prevent fraudulent activity.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('3. Data Sharing & Security'),
          ]),
          p([
            Component.text('We do not sell your personal data. We only share information with third-party service providers (like payment processors and backend cloud databases) to the extent necessary to run the platform. Your wallet interactions are secured on-chain via smart contracts.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('4. Contact Us'),
          ]),
          p([
            Component.text('If you have any questions about this Privacy Policy, please contact us at support@tranyx.app.'),
          ]),
        ]),
      ]),
    ]);
  }
}
