/// Comprehensive Offline Domain Knowledge Base for Nyx AI Assistant (Tranyx Platform).
/// Contains structured domain knowledge and localized responses across English, Tagalog, and Waray-Waray.
class NyxDomainKnowledgeBase {
  NyxDomainKnowledgeBase._();

  /// Out-of-scope response message
  static const String outOfScopeResponse =
      'OUT_OF_SCOPE: I am Nyx, the AI assistant exclusively for Tranyx. I can only assist with Tranyx gigs, vehicle & property rentals, escrow, delivery tracking, wallets, and platform features.';

  /// Comprehensive knowledge entries for Tranyx ecosystem
  static const Map<String, List<String>> knowledgeEntries = {
    'gigs': [
      'Employers post gigs by entering a title, category, budget (PHP), date requirement, and description in the Jobs tab.',
      'Funds are locked in Escrow upon hiring a Nyxian worker and released upon verified job completion.',
      'Nyxians can apply to active listings with custom bids or counter-offers and a cover note.',
      'Standard jobs completion requires the Nyxian to mark done, employer to generate a QR code, and Nyxian to scan the code.',
    ],
    'delivery_tracker': [
      'Tracked jobs (hasTracker = true) use a 5-step delivery state machine:',
      '1. Nyxian arrives at pickup location.',
      '2. Nyxian pays cashier and uploads official receipt photo.',
      '3. Package is marked in transit with live GPS tracking.',
      '4. Nyxian arrives at dropoff location.',
      '5. Nyxian generates a completion QR code for the recipient to scan, triggering instant escrow payout.',
    ],
    'transit': [
      'The Transit tab features vehicle rentals (cars, motorcycles, scooters) and real estate rentals (condos, houses, commercial space).',
      'Renters can request bookings with daily rates in SOL or TYXBIT tokens.',
      'Hosts review booking requests and digital contracts before activating the rental.',
    ],
    'wallets': [
      'Tranyx supports Phantom, Solflare, and Trust Wallet with 1:1 user-to-wallet verification.',
      'Linked accounts are managed under Profile -> Trust & Verification -> Linked Accounts.',
      'SOL tokens are used for Solana blockchain gas fees and instant crypto rental payments.',
      'TYXBIT tokens provide platform rewards, discounted fees, and rental payments.',
    ],
    'kyc': [
      'Verification Tiers: Tier 1 (Phone & Email), Tier 2 (Government ID & Selfie), Tier 3 (Skill Accreditation & Bonded Badge).',
      'Accepted Philippine Primary IDs: PhilID (National ID), UMID, SSS, Driver\'s License, Passport, PRC ID, Postal ID, Voter\'s ID.',
      'Bonded & Protected status unlocks priority job applications and reduced platform service fees.',
    ],
  };

  /// Query the offline domain knowledge base using natural language query matching
  static String queryKnowledge(String query, {String? userRole, double? escrowBalance}) {
    final clean = query.toLowerCase().trim();

    // Detect language
    final bool isWaray = clean.contains('waray') ||
        clean.contains('maupay') ||
        clean.contains('hin-o') ||
        clean.contains('kayo') ||
        clean.contains('diin') ||
        clean.contains('pira') ||
        clean.contains('kandi') ||
        clean.contains('kamo') ||
        clean.contains('nimo');

    final bool isTagalog = clean.contains('paano') ||
        clean.contains('saan') ||
        clean.contains('magkano') ||
        clean.contains('sino') ||
        clean.contains('bakit') ||
        clean.contains('kailan') ||
        clean.contains('nito') ||
        clean.contains('ako');

    // Scope verification check
    final bool isInScope = clean.contains('gig') ||
        clean.contains('job') ||
        clean.contains('work') ||
        clean.contains('trabaho') ||
        clean.contains('apply') ||
        clean.contains('post') ||
        clean.contains('employer') ||
        clean.contains('nyxian') ||
        clean.contains('bid') ||
        clean.contains('cover') ||
        clean.contains('delivery') ||
        clean.contains('tracker') ||
        clean.contains('receipt') ||
        clean.contains('pickup') ||
        clean.contains('dropoff') ||
        clean.contains('cashier') ||
        clean.contains('hatod') ||
        clean.contains('transit') ||
        clean.contains('vehicle') ||
        clean.contains('car') ||
        clean.contains('motorcycle') ||
        clean.contains('scooter') ||
        clean.contains('rent') ||
        clean.contains('property') ||
        clean.contains('condo') ||
        clean.contains('house') ||
        clean.contains('sarakyan') ||
        clean.contains('kotse') ||
        clean.contains('arkila') ||
        clean.contains('balay') ||
        clean.contains('wallet') ||
        clean.contains('sol') ||
        clean.contains('phantom') ||
        clean.contains('solflare') ||
        clean.contains('trust') ||
        clean.contains('token') ||
        clean.contains('tyxbit') ||
        clean.contains('kwarta') ||
        clean.contains('gas') ||
        clean.contains('link') ||
        clean.contains('account') ||
        clean.contains('kyc') ||
        clean.contains('id') ||
        clean.contains('verify') ||
        clean.contains('verification') ||
        clean.contains('bonded') ||
        clean.contains('identity') ||
        clean.contains('philid') ||
        clean.contains('umid') ||
        clean.contains('passport') ||
        clean.contains('driver') ||
        clean.contains('sss') ||
        clean.contains('prc') ||
        clean.contains('kilala') ||
        clean.contains('hi') ||
        clean.contains('hello') ||
        clean.contains('kumusta') ||
        clean.contains('maupay') ||
        clean.contains('hey') ||
        clean.contains('tranyx') ||
        clean.contains('escrow') ||
        clean.contains('nyx') ||
        clean.contains('support') ||
        clean.contains('fee') ||
        clean.contains('payout') ||
        clean.contains('payment') ||
        clean.contains('balance') ||
        clean.contains('profile') ||
        clean.contains('reward') ||
        clean.contains('quest') ||
        clean.contains('agent');

    if (!isInScope) {
      return outOfScopeResponse;
    }

    // 1. Delivery & Tracker Queries
    if (clean.contains('delivery') || clean.contains('tracker') || clean.contains('receipt') || clean.contains('pickup') || clean.contains('hatod')) {
      if (isWaray) {
        return 'Mga Gig nga may Tracker: Kadto ha pickup, pagbayad ha cashier ngan i-upload an resibo. Kun maabot ha dropoff, maghimo hin QR code para i-scan han nakarawat para mangawas an Escrow payout!';
      } else if (isTagalog) {
        return 'Para sa Tracked Delivery Gigs: Pumunta sa pickup point, magbayad sa cashier at i-upload ang larawan ng resibo. Pagdating sa dropoff, mag-generate ng QR code para i-scan ng nakatanggap upang ma-release ang Escrow payout!';
      }
      return 'For Tracked Delivery Gigs: Arrive at pickup, pay the cashier and upload the receipt photo. Once at dropoff, generate a QR code for the recipient to scan and release Escrow payout instantly!';
    }

    // 2. Escrow & Payout Queries
    if (clean.contains('escrow') || clean.contains('release') || clean.contains('payout') || clean.contains('bayad') || clean.contains('bayaran')) {
      if (isWaray) {
        return 'Kun tapos na an trabaho ha Tranyx, i-mamark han Nyxian nga tapos na, maghihimo an Employer hin QR code, ngan i-iscan ini han Nyxian para diretso nga ma-release an Escrow payout ha iya wallet!';
      } else if (isTagalog) {
        return 'Kapag tapos na ang trabaho sa Tranyx, i-mamark ng Nyxian ang job as "Completed", bubuo ang Employer ng QR code, at i-iscan ito ng Nyxian upang agarang ma-release ang Escrow payout diretso sa kanyang wallet!';
      }
      return 'When a job is completed on Tranyx, the Nyxian marks the job as done, the Employer generates a completion QR code, and the Nyxian scans it to instantly release the Escrow funds into their wallet!';
    }

    // 3. Gigs & Job Matching Queries
    if (clean.contains('gig') || clean.contains('job') || clean.contains('work') || clean.contains('trabaho') || clean.contains('apply') || clean.contains('post') || clean.contains('pustar') || clean.contains('patrabaho')) {
      if (clean.contains('post') || clean.contains('create') || clean.contains('employer') || clean.contains('magpost') || clean.contains('pag-himo')) {
        if (isWaray) {
          return 'Paghimo hin Bag-o nga Listing: Kadto ha Jobs tab ngan pusa an "+ New" o "+ Create New Listing" ha ubos (o an "+" button ha mobile). Isurat an pamunoan, kategorya, ngan badyet ha PHP (₱). Awtomatiko nga nakatagak ha Escrow an kwarta para talwas!';
        } else if (isTagalog) {
          return 'Para gumawa ng bagong listing: Pumunta sa Jobs tab at i-click ang "+ New" o "+ Create New Listing" sa ibaba (o ang "+" button sa mobile). Ilagay ang pamagat, kategorya, at badyet sa PHP (₱). Ligtas na nakatago sa Escrow ang pondo kapag kumuha ka ng manggagawa!';
        }
        return 'To create a new listing as an Employer, go to the Jobs tab and click "+ New" (or "+ Create New Listing" at the bottom of the list on web, or the "+" button on mobile). Enter the title, category, budget (₱), and description. Funds are safely locked in Escrow upon hiring a worker!';
      }

      if (isWaray) {
        return 'Para mag-apply hin trabaho: Kitaa an mga Gig ha Jobs tab, pili hin gig, ngan pusa an "Proceed to Apply". Puydi ka magsumite hin bid ngan pamunoan nga sulat!';
      } else if (isTagalog) {
        return 'Para mag-apply sa Gig: Tingnan ang active jobs sa Jobs tab, pumili ng gig, at i-tap ang "Proceed to Apply". Maaari kang mag-submit ng bid at cover note!';
      }
      return 'To apply for gigs as a Nyxian worker, browse active jobs in the Jobs tab, select a listing, and tap "Proceed to Apply". You can bid at standard rates or submit counter-offers with a cover note.';
    }

    // 3. Transit & Vehicles/Property Rental Queries
    if (clean.contains('vehicle') || clean.contains('car') || clean.contains('transit') || clean.contains('rent') || clean.contains('property') || clean.contains('condo') || clean.contains('sarakyan') || clean.contains('kotse') || clean.contains('arkila') || clean.contains('balay')) {
      if (isWaray) {
        return 'Puydi ka mag-arkila o mag-post hin sarakyan ngan balay ha Transit tab! An mga renter puydi mag-book gamit an SOL o TYXBIT tokens pag-aprobar han host.';
      } else if (isTagalog) {
        return 'Maaari kang mag-arkila o mag-post ng sasakyan at bahay sa Transit tab gamit ang SOL o TYXBIT tokens! Ang renters ay pwedeng mag-book gamit ang SOL o TYXBIT tokens kapag na-aprubahan ng host.';
      }
      return 'You can list or rent vehicles and real estate under the Transit tab! Renters can send booking requests using SOL or TYXBIT tokens. Once approved by the host, sign the digital contract to activate your booking.';
    }

    // 4. Wallet & Token Queries
    if (clean.contains('wallet') || clean.contains('sol') || clean.contains('phantom') || clean.contains('solflare') || clean.contains('trust') || clean.contains('token') || clean.contains('kwarta')) {
      if (isWaray) {
        return 'Nasuporta an Tranyx ha Phantom, Solflare, ngan Trust Wallet nga may 1:1 account verification ha Profile -> Trust & Verification -> Linked Accounts.';
      } else if (isTagalog) {
        return 'Suportado ng Tranyx ang Phantom, Solflare, at Trust Wallet na may 1:1 account verification sa Profile -> Trust & Verification -> Linked Accounts.';
      }
      return 'Tranyx supports Phantom, Solflare, and Trust Wallet with 1:1 user-to-wallet verification. You can manage linked accounts under Profile -> Trust & Verification -> Linked Accounts.';
    }

    // 5. KYC & Trust Verification Queries
    if (clean.contains('kyc') || clean.contains('id') || clean.contains('verify') || clean.contains('verification') || clean.contains('bonded') || clean.contains('identity') || clean.contains('kilala')) {
      if (isWaray) {
        return 'An KYC verification nakaka-unlock han Bonded badge ngan mas mabuho nga fees! Mag-submit hin PhilID, UMID, Driver\'s License, o Passport ha Profile -> Trust & Verification.';
      } else if (isTagalog) {
        return 'Ang KYC verification ay nag-u-unlock ng Bonded badge at mas mababang fees! Mag-submit ng PhilID, UMID, Driver\'s License, o Passport sa Profile -> Trust & Verification.';
      }
      return 'KYC verification unlocks the Bonded & Protected badge and reduced platform fees! Submit a valid PhilID, UMID, Driver\'s License, or Passport under Profile -> Trust & Verification.';
    }

    // 6. Greetings & General Help
    if (clean.contains('hi') || clean.contains('hello') || clean.contains('kumusta') || clean.contains('maupay') || clean.contains('hey')) {
      if (isWaray) {
        return 'Maupay nga adlaw! Ako si Nyx, an im Tranyx assistant. Anano an akon maitutulong ha im mga gig, rentals, o wallet yana?';
      } else if (isTagalog) {
        return 'Kumusta! Ako si Nyx, ang iyong Tranyx assistant. Anong maipaglilingkod ko sa iyong mga gig, arkilahan, o wallet ngayon?';
      }
      return 'Kumusta! I\'m Nyx, your Tranyx assistant. How can I help guide you with your gigs, rentals, or wallet setup today?';
    }

    // 7. Fallback to Live Agent Escalation
    return 'TRANSFER_TO_AGENT';
  }
}
