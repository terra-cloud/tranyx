import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

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
            Component.text('Last updated: June 22, 2026. At Tranyx, we value your privacy. This Privacy Policy describes how we collect, use, store, and share your information when you use our decentralized peer-to-peer sharing and gig marketplace via our web and mobile applications.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('1. Information We Collect'),
          ]),
          p([
            Component.text('We collect several types of information from and about our users to facilitate our gig marketplace, vehicle rentals, property bookings, and payment routing:'),
          ]),
          ul(classes: 'list-disc pl-6 space-y-2 text-zinc-400', [
            li([Component.text('Account Profile Data: Name, email address, phone number, business details, profile photo, and account type (Employer, Nyxian Worker, or Hybrid).')]),
            li([Component.text('Identity Verification (KYC) Details: Goverment-issued ID cards, driver’s licenses, selfie images, business permits, and background check data to prevent fraudulent activities.')]),
            li([Component.text('Web3 Wallet Data: Public wallet addresses (e.g., Solana, Ethereum, Sui) and cryptographic signatures generated when logging in, establishing escrows, or authorizing payment contracts.')]),
            li([Component.text('Precise Location Data: Real-time GPS coordinate data to trace on-site gigs, facilitate route tracking for vehicle rentals, verify property locations, and perform distance-based search filter calculations.')]),
            li([Component.text('Payment Gateway Details: Transaction logs, billing info, and invoice metadata processed via Xendit or on-chain cryptocurrency transactions.')]),
            li([Component.text('Marketplace Interactions: Chat history, work agreements, gig applications, escrow release milestones, and user reviews/ratings.')]),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('2. How We Use Your Information'),
          ]),
          p([
            Component.text('We process your information for the following business and operational purposes:'),
          ]),
          ul(classes: 'list-disc pl-6 space-y-2 text-zinc-400', [
            li([Component.text('To establish and secure your account, mapping your public wallet address to your user profile.')]),
            li([Component.text('To match gig workers (Nyxians) with employers based on skills, ratings, and location proximity.')]),
            li([Component.text('To verify qualifications and drive credentials for vehicle rentals and rental extension escrows.')]),
            li([Component.text('To process fiat payments and Tyxbit token credits through our payment gateway partner (Xendit).')]),
            li([Component.text('To trace active transit routes, verify geolocation drop-offs, and secure rental properties.')]),
            li([Component.text('To run local safety checks and automated identity verification using our integrated AI tools.')]),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('3. Blockchain & Decentralized Data Public Nature'),
          ]),
          p([
            Component.text('Please note that because Tranyx integrates with the Solana blockchain, all transactions, smart contract state transitions, escrow creation inputs, and public wallet addresses written to the blockchain ledger are permanently recorded, publicly searchable, and cannot be deleted or modified. Off-chain data (such as profile details and chat messages) is stored securely in our database and remains subject to deletion requests.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('4. Data Sharing & Third-Party Service Providers'),
          ]),
          p([
            Component.text('We do not sell your personal data. We disclose your information only to:'),
          ]),
          ul(classes: 'list-disc pl-6 space-y-2 text-zinc-400', [
            li([Component.text('Other marketplace participants (e.g. sharing your contact number or location with a host during an active vehicle rental, or showing your profile/skills to employers).')]),
            li([Component.text('Xendit and other financial service providers to verify payments and credit balances.')]),
            li([Component.text('Cloud database and hosting providers (such as Firebase) to store data, messages, and assets.')]),
            li([Component.text('Government authorities or legal bodies where required to comply with regulatory, tax, or fraud prevention mandates.')]),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('5. Security of Your Data'),
          ]),
          p([
            Component.text('We implement industry-standard security measures, including cryptographic token authorization, local password obfuscation on mobile devices (using SecureStorage), and HTTPS encryption. However, please remember that no transmission method over the internet or decentralized ledger is 100% secure.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('6. User Rights & Data Deletion'),
          ]),
          p([
            Component.text('Depending on your jurisdiction, you may request access to, correction of, or deletion of your off-chain personal data. To delete your account or retrieve your off-chain profile records, please contact our support team. Immutable blockchain logs cannot be removed.'),
          ]),
          h2(classes: 'text-xl font-bold text-white mt-8 mb-3', [
            Component.text('7. Contact Us'),
          ]),
          p([
            Component.text('If you have questions, comments, or complaints about this Privacy Policy, please email us at support@tranyx.app.'),
          ]),
        ]),
      ]),
    ]);
  }
}
