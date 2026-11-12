import 'package:jaspr/jaspr.dart';

import '../client/widgets/legal_shell.dart';

@client
class TermsOfUse extends StatelessComponent {
  const TermsOfUse({super.key});

  @override
  Component build(BuildContext context) {
    return LegalShell(
      tab: LegalTab.terms,
      title: 'Terms of Use',
      intro:
          'Welcome to Tranyx. By accessing or using our platform, website, or mobile application, you agree to be bound by these Terms of Use. Please read them carefully.',
      sections: const [
        LegalSectionData(
          id: 'terms-1',
          title: '1. Acceptance & Scope of Terms',
          paragraphs: [
            'These Terms of Use govern your access to the Tranyx P2P gig and sharing marketplace across all web services, mobile clients, and environment flavors (including development, UAT, and production environments). By connecting a Web3 wallet (such as Phantom, Solflare, Backpack, or Trust Wallet) or logging in via email, you accept these terms in full.',
          ],
        ),
        LegalSectionData(
          id: 'terms-2',
          title: '2. User Accounts, Verification & KYC',
          paragraphs: [
            'To participate in the marketplace as a Nyxian worker, vehicle host, or property host, you may be required to complete our Know Your Customer (KYC) identity verification flow. This includes uploading a valid government ID, a driver’s license (for vehicle rentals), business permits, and submitting to background checks. You agree to provide accurate, current, and complete details. We reserve the right to suspend accounts that fail verification or provide falsified records.',
          ],
        ),
        LegalSectionData(
          id: 'terms-3',
          title: '3. Decentralized Marketplace, Rentals & Escrow Rules',
          lead: 'Tranyx operates as a peer-to-peer matching and sharing platform. The following guidelines apply to all interactions:',
          bullets: [
            'Jobs & Gigs: Employers are responsible for defining clear job descriptions and milestones. Workers (Nyxians) are responsible for completing the milestones as agreed.',
            'Escrow Accounts: Funds for gigs, property bookings, and vehicle rentals are held securely in escrow contracts (on-chain or via fiat ledger balances). Escrows are released upon verified milestone completion or rental checkout validation.',
            'Vehicle & Property Rentals: Hosts must ensure that vehicle listings and properties are in safe, clean, and rentable condition. Renters must hold valid driving credentials and adhere strictly to terms of rental agreements and return rules.',
          ],
        ),
        LegalSectionData(
          id: 'terms-4',
          title: '4. Payments, Tyxbit Tokens & Transaction Fees',
          lead: 'All financial settlements on the platform are handled via:',
          bullets: [
            'Internal Tyxbit Balances: Used for platform ledger balances, escrows, and service settlements.',
            'On-chain Transactions (Solana/USDT): Used for Web3 wallet payments and blockchain escrows.',
            'Fees: Users are responsible for all gas, network, and processing fees associated with blockchain transactions, escrows, and deposit/withdrawal channels.',
          ],
        ),
        LegalSectionData(
          id: 'terms-5',
          title: '5. Location Tracking & Conduct',
          paragraphs: [
            'Certain features of the app (such as route tracking for vehicle rentals and active tracked gig progress) require real-time GPS location tracking. You agree to keep location permissions active for the duration of these tasks. Location spoofing, manipulation, or unauthorized tracking bypasses will result in immediate termination of the active service contract and permanent account suspension.',
          ],
        ),
        LegalSectionData(
          id: 'terms-6',
          title: '6. Disclaimers & Limitation of Liability',
          paragraphs: [
            'Tranyx is a decentralized matching directory. We do not employ users, broker leases, or manage rental fleets directly. All agreements and disputes regarding gigs, vehicle conditions, property bookings, or service quality are strictly between the peer-to-peer contract parties. Tranyx is provided "as-is" without any warranties, and we are not liable for any direct, indirect, on-chain smart contract, or vehicle/property damages.',
          ],
        ),
        LegalSectionData(
          id: 'terms-7',
          title: '7. Account Suspension & Termination',
          paragraphs: [
            'We reserve the right, in our sole discretion, to suspend or terminate your access to the platform for any breach of these terms, fraud, payment defaults, or safety violations.',
          ],
        ),
        LegalSectionData(
          id: 'terms-8',
          title: '8. Modifications to Terms',
          paragraphs: [
            'We may update these Terms of Use at any time. We will indicate changes by updating the revision date at the top. Your continued use of the platform after updates indicates your agreement to the new terms.',
          ],
        ),
      ],
    );
  }
}
