import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

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
          a(
            href: '/',
            classes: 'px-4 py-2 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-zinc-300 text-sm font-bold transition-all flex items-center gap-2',
            [
              Component.text('← Back to Home'),
            ],
          ),
        ]),
        div(classes: 'space-y-6 text-zinc-300 leading-relaxed text-sm md:text-base', [
          p([
            Component.text('Welcome to Tranyx. By accessing or using our platform, website, or mobile application, you agree to be bound by these Terms of Use. Please read them carefully.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('1. Acceptance & Scope of Terms'),
          ]),
          p([
            Component.text('These Terms of Use govern your access to the Tranyx P2P gig and sharing marketplace across all web services, mobile clients, and environment flavors (including development, UAT, and production environments). By connecting a Web3 wallet (such as Phantom, Solflare, Backpack, or Trust Wallet) or logging in via email, you accept these terms in full.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('2. User Accounts, Verification & KYC'),
          ]),
          p([
            Component.text('To participate in the marketplace as a Nyxian worker, vehicle host, or property host, you may be required to complete our Know Your Customer (KYC) identity verification flow. This includes uploading a valid government ID, a driver’s license (for vehicle rentals), business permits, and submitting to background checks. You agree to provide accurate, current, and complete details. We reserve the right to suspend accounts that fail verification or provide falsified records.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('3. Decentralized Marketplace, Rentals & Escrow Rules'),
          ]),
          p([
            Component.text('Tranyx operates as a peer-to-peer matching and sharing platform. The following guidelines apply to all interactions:'),
          ]),
          ul(classes: 'list-disc pl-6 space-y-2 text-zinc-400', [
            li([Component.text('Jobs & Gigs: Employers are responsible for defining clear job descriptions and milestones. Workers (Nyxians) are responsible for completing the milestones as agreed.')]),
            li([Component.text('Escrow Accounts: Funds for gigs, property bookings, and vehicle rentals are held securely in escrow contracts (on-chain or via fiat ledger balances). Escrows are released upon verified milestone completion or rental checkout validation.')]),
            li([Component.text('Vehicle & Property Rentals: Hosts must ensure that vehicle listings and properties are in safe, clean, and rentable condition. Renters must hold valid driving credentials and adhere strictly to terms of rental agreements and return rules.')]),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('4. Payments, Tyxbit Tokens & Transaction Fees'),
          ]),
          p([
            Component.text('All financial settlements on the platform are handled via:'),
          ]),
          ul(classes: 'list-disc pl-6 space-y-2 text-zinc-400', [
            li([Component.text('Fiat Gateways (Xendit): Used for credit cards, e-wallets, or bank transfers to top up your TYX (Tyxbit) fiat-denominated ledger balance.')]),
            li([Component.text('On-chain Transactions (Solana/USDT): Used for Web3 wallet payments and blockchain escrows.')]),
            li([Component.text('Fees: Users are responsible for all gas, network, and processing fees associated with blockchain transactions, escrows, and deposit/withdrawal channels.')]),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('5. Location Tracking & Conduct'),
          ]),
          p([
            Component.text('Certain features of the app (such as route tracking for vehicle rentals and active tracked gig progress) require real-time GPS location tracking. You agree to keep location permissions active for the duration of these tasks. Location spoofing, manipulation, or unauthorized tracking bypasses will result in immediate termination of the active service contract and permanent account suspension.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('6. Disclaimers & Limitation of Liability'),
          ]),
          p([
            Component.text('Tranyx is a decentralized matching directory. We do not employ users, broker leases, or manage rental fleets directly. All agreements and disputes regarding gigs, vehicle conditions, property bookings, or service quality are strictly between the peer-to-peer contract parties. Tranyx is provided "as-is" without any warranties, and we are not liable for any direct, indirect, on-chain smart contract, or vehicle/property damages.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('7. Account Suspension & Termination'),
          ]),
          p([
            Component.text('We reserve the right, in our sole discretion, to suspend or terminate your access to the platform for any breach of these terms, fraud, payment defaults, or safety violations.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('8. Modifications to Terms'),
          ]),
          p([
            Component.text('We may update these Terms of Use at any time. We will indicate changes by updating the revision date at the top. Your continued use of the platform after updates indicates your agreement to the new terms.'),
          ]),
        ]),
      ]),
    ]);
  }
}
