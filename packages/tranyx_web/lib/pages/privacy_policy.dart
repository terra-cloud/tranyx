import 'package:jaspr/jaspr.dart';

import '../client/widgets/legal_shell.dart';

@client
class PrivacyPolicy extends StatelessComponent {
  const PrivacyPolicy({super.key});

  @override
  Component build(BuildContext context) {
    return LegalShell(
      tab: LegalTab.privacy,
      title: 'Privacy Policy',
      intro:
          'Last updated: June 22, 2026. At Tranyx, we value your privacy. This Privacy Policy describes how we collect, use, store, and share your information when you use our decentralized peer-to-peer sharing and gig marketplace via our web and mobile applications.',
      sections: const [
        LegalSectionData(
          id: 'privacy-1',
          title: '1. Information We Collect',
          lead:
              'We collect several types of information from and about our users to facilitate our gig marketplace, vehicle rentals, property bookings, and payment routing:',
          bullets: [
            'Account Profile Data: Name, email address, phone number, business details, profile photo, and account type (Employer, Nyxian Worker, or Hybrid).',
            'Identity Verification (KYC) Details: Goverment-issued ID cards, driver’s licenses, selfie images, business permits, and background check data to prevent fraudulent activities.',
            'Web3 Wallet Data: Public wallet addresses (e.g., Solana, Ethereum, Sui) and cryptographic signatures generated when logging in, establishing escrows, or authorizing payment contracts.',
            'Precise Location Data: Real-time GPS coordinate data to trace on-site gigs, facilitate route tracking for vehicle rentals, verify property locations, and perform distance-based search filter calculations.',
            'Payment Details: Transaction logs, billing info, and payment metadata processed via on-chain cryptocurrency and internal balance transactions.',
            'Marketplace Interactions: Chat history, work agreements, gig applications, escrow release milestones, and user reviews/ratings.',
          ],
        ),
        LegalSectionData(
          id: 'privacy-2',
          title: '2. How We Use Your Information',
          lead: 'We process your information for the following business and operational purposes:',
          bullets: [
            'To establish and secure your account, mapping your public wallet address to your user profile.',
            'To match gig workers (Nyxians) with employers based on skills, ratings, and location proximity.',
            'To verify qualifications and drive credentials for vehicle rentals and rental extension escrows.',
            'To process Tyxbit balance operations, on-chain payments, and escrow releases.',
            'To trace active transit routes, verify geolocation drop-offs, and secure rental properties.',
            'To run local safety checks and automated identity verification using our integrated AI tools.',
          ],
        ),
        LegalSectionData(
          id: 'privacy-3',
          title: '3. Blockchain & Decentralized Data Public Nature',
          paragraphs: [
            'Please note that because Tranyx integrates with the Solana blockchain, all transactions, smart contract state transitions, escrow creation inputs, and public wallet addresses written to the blockchain ledger are permanently recorded, publicly searchable, and cannot be deleted or modified. Off-chain data (such as profile details and chat messages) is stored securely in our database and remains subject to deletion requests.',
          ],
        ),
        LegalSectionData(
          id: 'privacy-4',
          title: '4. Data Sharing & Third-Party Service Providers',
          lead: 'We do not sell your personal data. We disclose your information only to:',
          bullets: [
            'Other marketplace participants (e.g. sharing your contact number or location with a host during an active vehicle rental, or showing your profile/skills to employers).',
            'Financial and verification service providers to verify transactions and manage platform safety.',
            'Cloud database and hosting providers (such as Firebase) to store data, messages, and assets.',
            'Government authorities or legal bodies where required to comply with regulatory, tax, or fraud prevention mandates.',
          ],
        ),
        LegalSectionData(
          id: 'privacy-5',
          title: '5. Security of Your Data',
          paragraphs: [
            'We implement industry-standard security measures, including cryptographic token authorization, local password obfuscation on mobile devices (using SecureStorage), and HTTPS encryption. However, please remember that no transmission method over the internet or decentralized ledger is 100% secure.',
          ],
        ),
        LegalSectionData(
          id: 'privacy-6',
          title: '6. User Rights & Data Deletion',
          paragraphs: [
            'Depending on your jurisdiction, you may request access to, correction of, or deletion of your off-chain personal data. To delete your account or retrieve your off-chain profile records, please contact our support team. Immutable blockchain logs cannot be removed.',
          ],
        ),
        LegalSectionData(
          id: 'privacy-7',
          title: '7. Contact Us',
          paragraphs: [
            'If you have questions, comments, or complaints about this Privacy Policy, please email us at support@tranyx.app.',
          ],
        ),
      ],
    );
  }
}
