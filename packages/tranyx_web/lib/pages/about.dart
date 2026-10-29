import 'package:jaspr/jaspr.dart';

import '../client/widgets/legal_shell.dart';

@client
class About extends StatelessComponent {
  const About({super.key});

  @override
  Component build(BuildContext context) {
    return LegalShell(
      tab: LegalTab.about,
      title: 'About Tranyx',
      intro:
          'One Platform. Endless Opportunities. Find freelance gigs, rent vehicles and properties, and earn securely on the all-in-one P2P platform. Powered by Web3 escrow and verified Nyxians in the Philippines.',
      sections: const [
        LegalSectionData(
          id: 'about-1',
          title: 'What we offer',
          bullets: [
            'Freelance gigs near you — match with local work as a verified Nyxian.',
            'Vehicle & space rentals — list or book vehicles and properties peer-to-peer.',
            'Escrow-protected payments — settle securely with Web3 escrow and Tyxbit balances.',
          ],
        ),
        LegalSectionData(
          id: 'about-2',
          title: 'Built for the Philippines',
          paragraphs: [
            'Tranyx is designed for Nyxians and employers across the Philippines — combining gig work, rentals, and escrow in one marketplace.',
          ],
        ),
        LegalSectionData(
          id: 'about-3',
          title: 'Contact',
          paragraphs: [
            'Questions about the platform? Email support@tranyx.app. For Privacy and Terms, use the tabs above.',
          ],
        ),
      ],
    );
  }
}
