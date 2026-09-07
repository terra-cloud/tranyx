import 'models.dart';

class TranyxFaqItem {
  final String title;
  final String icon;
  final String category;
  final String answer;

  const TranyxFaqItem({
    required this.title,
    required this.icon,
    required this.category,
    required this.answer,
  });
}

class TranyxFaqData {
  TranyxFaqData._();

  static List<TranyxFaqItem> getFaqsForAccountType(AccountType type) {
    switch (type) {
      case AccountType.employer:
        return employerFaqs;
      case AccountType.nyxian:
        return nyxianFaqs;
      case AccountType.hybrid:
        return hybridFaqs;
    }
  }

  static const List<TranyxFaqItem> employerFaqs = [
    TranyxFaqItem(
      title: 'How do I create a new job listing on Tranyx?',
      icon: 'briefcase',
      category: 'Gigs & Hiring',
      answer:
          'Under the Jobs tab, click the "+ New" button at the top (or the "+ Create New Listing" button at the bottom of your listings on web, or the "+" button on mobile) to launch the creation wizard. Select a category, enter your job title, date requirement, budget (in PHP ₱), and description (or use our AI Auto-write tool). If you need a courier or delivery with live GPS tracking, toggle "Has Tracker" and specify pickup and drop-off points. Once created, qualified Nyxian workers can apply with custom bids.',
    ),
    TranyxFaqItem(
      title: 'How does payment and Escrow work?',
      icon: 'credit-card',
      category: 'Escrow & Payments',
      answer:
          'When you hire an applicant, the agreed budget is securely locked in Tranyx Escrow. Funds are never released until you verify completion. For standard gigs, you generate a completion QR code for the worker to scan once they mark the job done. For tracked deliveries, the worker completes 5 verified checkpoints and generates a QR code for you to scan. Once scanned, escrow instantly releases payout to the worker.',
    ),
    TranyxFaqItem(
      title: 'How do I list and manage vehicle or property rentals?',
      icon: 'car',
      category: 'Transit Rentals',
      answer:
          'Under the Transit tab, switch to the "Host" section and tap "List a Vehicle" or "List a Property". Set your daily rates in SOL or TYXBIT tokens, upload photos, and configure vehicle specs or property amenities. When renters submit booking requests, you review their verification status and approve the booking. Once approved, the renter signs the digital contract to activate the rental.',
    ),
    TranyxFaqItem(
      title: 'What are the Trust & Verification (KYC) tiers?',
      icon: 'shield-check',
      category: 'Trust & KYC',
      answer:
          'Tranyx features 3 Trust Tiers: Tier 1 verifies your email and phone number; Tier 2 verifies your primary Government ID (PhilID/National ID, UMID, Driver\'s License, Passport, SSS, PRC, Postal ID) with a live selfie check; Tier 3 awards the Bonded & Protected status. Higher verification tiers dramatically boost worker trust and qualify you for higher-value contracts.',
    ),
    TranyxFaqItem(
      title: 'How do I link and verify my Web3 wallet?',
      icon: 'wallet',
      category: 'Wallets & Web3',
      answer:
          'Navigate to Profile -> Trust & Verification -> Linked Accounts. Tranyx supports Phantom, Solflare, and Trust Wallet with strict 1:1 user-to-wallet verification to ensure account security. Your connected wallet allows you to receive instant crypto rental payouts in SOL or earn TYXBIT rewards.',
    ),
    TranyxFaqItem(
      title: 'How are disputes resolved?',
      icon: 'alert-circle',
      category: 'Disputes & Support',
      answer:
          'If an issue or disagreement occurs, you can raise a dispute directly from your active job or rental card. Our Tranyx moderation team will review chat records, delivery checkpoint receipts, and deliverables to settle the escrow payout fairly and protect both parties.',
    ),
  ];

  static const List<TranyxFaqItem> nyxianFaqs = [
    TranyxFaqItem(
      title: 'How do I apply for gigs and submit bids?',
      icon: 'briefcase',
      category: 'Gigs & Applications',
      answer:
          'Browse available listings under the Jobs tab. When you find a gig matching your skills, tap "Proceed to Apply". You can bid at the standard rate or submit a counter-offer. Use our "Auto-Draft" AI button to instantly generate a tailored, professional cover note highlighting your experience and tool readiness.',
    ),
    TranyxFaqItem(
      title: 'How and when do I receive my Escrow payout?',
      icon: 'credit-card',
      category: 'Escrow & Payouts',
      answer:
          'Your payout is 100% secured in Escrow as soon as you are hired. For standard gigs, tap "Mark as Done" and scan the Employer\'s completion QR code. For delivery tracker gigs, complete the checkpoints (Arrived at Pickup -> Paid Cashier & Receipt Upload -> In Transit -> Arrived at Dropoff) and generate a completion QR code for the recipient to scan. Once scanned, funds are instantly released to your wallet balance!',
    ),
    TranyxFaqItem(
      title: 'How do withdrawals work on Tranyx?',
      icon: 'wallet',
      category: 'Withdrawals',
      answer:
          'You can withdraw your earnings directly on-chain to your linked Solana wallet (Phantom, Solflare, Trust Wallet) under Profile -> Balance -> Withdraw. Withdrawals are processed through our automated treasury with on-chain cryptographic ledger logging in SOL, TYXBIT, or USDT.',
    ),
    TranyxFaqItem(
      title: 'How do I unlock the Bonded & Protected badge?',
      icon: 'shield-check',
      category: 'Trust & Badges',
      answer:
          'Go to Profile -> Trust & Verification. Completing Tier 2 ID verification (Government ID + Selfie) and Tier 3 Skill Accreditation unlocks the Bonded & Protected badge. Bonded workers enjoy top ranking in search results, priority job matching, and reduced platform service fees.',
    ),
    TranyxFaqItem(
      title: 'How does Nyx AI Support work and what are the limits?',
      icon: 'sparkles',
      category: 'AI Support',
      answer:
          'Nyx AI is your 24/7 assistant fluent in English, Tagalog, and Waray-Waray. Users have 5 free conversational support questions per session, with 1 free token recovering every hour. Generative features like auto-drafting cover notes and job descriptions remain completely free and unlimited.',
    ),
  ];

  static const List<TranyxFaqItem> hybridFaqs = [
    TranyxFaqItem(
      title: 'What is a Hybrid PRO account?',
      icon: 'zap',
      category: 'Account Types',
      answer:
          'A Hybrid PRO account gives you the flexibility to act as both an Employer (posting jobs and hosting rentals) and a Nyxian worker (applying for gigs and renting transit) using a single, unified account and wallet balance.',
    ),
    TranyxFaqItem(
      title: 'How do I toggle between Employer and Worker modes?',
      icon: 'refresh-cw',
      category: 'Navigation',
      answer:
          'You can switch your active perspective anytime using the role toggle in your Profile or top navigation bar. This dynamically adjusts your dashboard views, action cards, and active contracts without needing to log out.',
    ),
    TranyxFaqItem(
      title: 'Are my earnings and ratings shared between roles?',
      icon: 'star',
      category: 'Ratings & Balance',
      answer:
          'Your wallet balance is unified, allowing you to seamlessly use earnings from completed gigs to fund escrow for your own job postings. However, your reputation is accurately separated into "Employer Rating" and "Worker Rating" based on reviews from your counterparties.',
    ),
    TranyxFaqItem(
      title: 'Do I need separate identity verifications for each role?',
      icon: 'shield-check',
      category: 'Trust & KYC',
      answer:
          'No. A single Tier 2/Tier 3 identity verification validates your global profile. Verified badges and bonded status apply across both your Employer and Nyxian interfaces.',
    ),
    TranyxFaqItem(
      title: 'How do fees work on a Hybrid PRO account?',
      icon: 'wallet',
      category: 'Fees & Rewards',
      answer:
          'Posting gigs as an employer incurs standard escrow funding. Payouts received as a worker are credited in full. Holding TYXBIT utility tokens or achieving Bonded status grants platform service fee discounts across both hiring and rental transactions.',
    ),
  ];
}
