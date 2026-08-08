class RewardQuest {
  final String id;
  final String title;
  final String category;
  final int points;
  final String limit;
  final String? notes;

  const RewardQuest({
    required this.id,
    required this.title,
    required this.category,
    required this.points,
    required this.limit,
    this.notes,
  });

  static const List<RewardQuest> quests = [
    // Onboarding
    RewardQuest(
        id: 'register_account',
        title: 'Register Account',
        category: 'Onboarding',
        points: 500,
        limit: 'Once',
        notes: 'Award after email verification'),
    RewardQuest(
        id: 'verify_account',
        title: 'Verify Account',
        category: 'Onboarding',
        points: 500,
        limit: 'Once',
        notes: 'Award after email and phone verification'),
    RewardQuest(
        id: 'complete_profile_trust',
        title: 'Complete Profile Trust and Verification',
        category: 'Onboarding',
        points: 2000,
        limit: 'Once',
        notes: 'Strengthens platform trust'),
    RewardQuest(
        id: 'add_skills_bio',
        title: 'Add Skills & Bio',
        category: 'Onboarding',
        points: 100,
        limit: 'Once'),
    RewardQuest(
        id: 'deposit_any_amount',
        title: 'Deposit any amount to Wallet',
        category: 'Onboarding',
        points: 500,
        limit: 'Once'),
    RewardQuest(
        id: 'connect_solana_wallet',
        title: 'Connect Any Solana Wallet',
        category: 'Onboarding',
        points: 200,
        limit: 'Once'),
    RewardQuest(
        id: 'subscribe_hybrid_pro',
        title: 'Subscribe to Hybrid PRO',
        category: 'Onboarding',
        points: 15000,
        limit: 'Once',
        notes: 'Unlock dual permissions and premium rewards'),

    // Employer
    RewardQuest(
        id: 'post_first_service',
        title: 'Post First Service',
        category: 'Services',
        points: 500,
        limit: 'Once'),
    RewardQuest(
        id: 'hire_applicant',
        title: 'Hire an Applicant',
        category: 'Services',
        points: 500,
        limit: 'Once'),
    RewardQuest(
        id: 'employer_complete_transaction',
        title: 'Complete transaction as employer',
        category: 'Services',
        points: 500,
        limit: 'Unlimited',
        notes: 'This will apply to 2nd job posting onwards'),

    // Jobseeker
    RewardQuest(
        id: 'apply_first_job',
        title: 'Apply First Job',
        category: 'Services',
        points: 500,
        limit: 'Once'),
    RewardQuest(
        id: 'be_hired',
        title: 'Be hired',
        category: 'Services',
        points: 500,
        limit: 'Once'),
    RewardQuest(
        id: 'jobseeker_complete_transaction',
        title: 'Complete transaction as Nyxian',
        category: 'Services',
        points: 500,
        limit: 'Unlimited',
        notes: 'This will apply to 2nd application onwards'),

    // Rental Host
    RewardQuest(
        id: 'post_property',
        title: 'Post Property',
        category: 'Rental',
        points: 500,
        limit: 'Unlimited'),
    RewardQuest(
        id: 'host_complete_transaction',
        title: 'Complete Transaction as a Lessor/Host',
        category: 'Rental',
        points: 500,
        limit: 'Unlimited'),

    // Rental Client
    RewardQuest(
        id: 'rent_property',
        title: 'Rent property',
        category: 'Rental',
        points: 500,
        limit: 'Unlimited'),
    RewardQuest(
        id: 'client_complete_transaction',
        title: 'Complete transaction as a Lessee/Renter',
        category: 'Rental',
        points: 500,
        limit: 'Unlimited'),
  ];
}
