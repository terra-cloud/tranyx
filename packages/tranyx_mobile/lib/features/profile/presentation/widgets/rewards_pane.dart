import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/profile/providers/profile_provider.dart';
import 'package:tranyx_mobile/features/navigation/providers/navigation_provider.dart';
import 'package:tranyx_mobile/features/transit/providers/transit_repository.dart';

class RewardsPane extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  const RewardsPane({super.key, required this.onBack});

  @override
  ConsumerState<RewardsPane> createState() => _RewardsPaneState();
}

class _RewardsPaneState extends ConsumerState<RewardsPane>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isCheckingQuests = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _triggerOnboardingCheck();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _triggerOnboardingCheck() async {
    final user = ref.read(userProvider);
    if (user == null) return;

    setState(() => _isCheckingQuests = true);
    try {
      final repo = ref.read(transitRepositoryProvider);
      final newlyAwarded = await repo.checkAndAwardOnboardingQuests(user.uid);
      // Refresh profile state only if a new quest was completed/awarded
      if (newlyAwarded) {
        ref.invalidate(userProfileProvider);
      }
    } catch (e) {
      debugPrint('Error checking rewards onboarding: $e');
    } finally {
      if (mounted) {
        setState(() => _isCheckingQuests = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final userProfileAsync = ref.watch(userProfileProvider);
    final user = ref.watch(userProvider);

    final bgGradient = isDarkMode
        ? const LinearGradient(
            colors: [Color(0xFF121212), Color(0xFF1E1E1E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : const LinearGradient(
            colors: [Color(0xFFF9F9FB), Color(0xFFF1F1F5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );

    final cardBg = isDarkMode ? const Color(0xFF1C1C1E) : Colors.white;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(gradient: bgGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 48,
              bottom: 8,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    color: isDarkMode ? Colors.white : Colors.black87,
                    size: 20,
                  ),
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 8),
                Text(
                  "Terra Rewards",
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                if (_isCheckingQuests)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: _triggerOnboardingCheck,
                  ),
              ],
            ),
          ),

          Expanded(
            child: userProfileAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text(
                  "Failed to load profile: $err",
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
              data: (profile) {
                if (profile == null) {
                  return const Center(child: Text("Profile data unavailable."));
                }

                final earned = profile.earnedRewards;

                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  children: [
                    // Balance Card
                    _buildBalanceCard(profile.terraPoints, isDarkMode),
                    const SizedBox(height: 24),

                    // Tab Selection Bar
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF1C1C1E)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        labelColor: isDarkMode ? Colors.white : Colors.black87,
                        unselectedLabelColor: isDarkMode
                            ? Colors.white54
                            : Colors.black45,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        tabs: const [
                          Tab(text: "Active Quests"),
                          Tab(text: "Points History"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Tab Views
                    SizedBox(
                      height: 520,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Tab 1: Quests List
                          _buildQuestsList(earned, isDarkMode, cardBg),

                          // Tab 2: History List
                          _buildHistoryList(
                            user?.uid ?? '',
                            isDarkMode,
                            cardBg,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(int points, bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF4F46E5), Color(0xFF3730A3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Icon(
              Icons.star,
              size: 100,
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "⭐ Terra Rewards Program",
                      style: TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Your Points Balance",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    points.toString(),
                    style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    "TP",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestsList(List<String> earned, bool isDarkMode, Color cardBg) {
    // Group quests by category
    final categories = ["Onboarding", "Services", "Rental"];

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        for (final category in categories) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 10, left: 4),
            child: Text(
              "$category Activities",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDarkMode ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDarkMode
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFE5E5EA),
              ),
            ),
            child: Column(
              children: [
                ...RewardQuest.quests
                    .where((q) => q.category == category)
                    .map(
                      (q) =>
                          _buildQuestTile(q, earned.contains(q.id), isDarkMode),
                    )
                    .toList(),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  void _handleQuestClick(RewardQuest q) {
    if (q.category == 'Services') {
      NavigationNotifier.switchTab(ref, 'jobs');
    } else if (q.category == 'Rental') {
      NavigationNotifier.switchTab(ref, 'transit');
    } else if (q.category == 'Onboarding') {
      if (q.id == 'verify_account' || q.id == 'complete_profile_trust') {
        ref.read(profileViewProvider.notifier).state = 'trust';
      } else if (q.id == 'add_skills_bio') {
        ref.read(profileViewProvider.notifier).state = 'main';
      } else if (q.id == 'deposit_any_amount' || q.id == 'connect_solana_wallet') {
        ref.read(profileViewProvider.notifier).state = 'payment';
      } else if (q.id == 'subscribe_hybrid_pro') {
        ref.read(profileViewProvider.notifier).state = 'subscription';
      }
    }
  }

  Widget _buildQuestTile(RewardQuest quest, bool isCompleted, bool isDarkMode) {
    return InkWell(
      onTap: () => _handleQuestClick(quest),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDarkMode
                  ? const Color(0xFF2C2C2E)
                  : const Color(0xFFE5E5EA),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          quest.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: quest.limit == 'Once'
                              ? const Color(0xFF6366F1).withOpacity(0.1)
                              : const Color(0xFF10B981).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          quest.limit == 'Once' ? 'Once' : 'Repeat',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: quest.limit == 'Once'
                                ? const Color(0xFF6366F1)
                                : const Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "+${quest.points} TP",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFD97706),
                  ),
                ),
                const SizedBox(height: 4),
                isCompleted
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          "✓ Completed",
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          "Pending",
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.grey,
                          ),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList(String uid, bool isDarkMode, Color cardBg) {
    final repo = ref.read(transitRepositoryProvider);

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: repo.getUserPointsHistory(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              "Error loading history: ${snapshot.error}",
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        final history = snapshot.data ?? [];
        if (history.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("📜", style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  "No points transactions logged yet.",
                  style: TextStyle(
                    fontSize: 13,
                    color: isDarkMode ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode
                  ? const Color(0xFF2C2C2E)
                  : const Color(0xFFE5E5EA),
            ),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: history.length,
            separatorBuilder: (context, i) => Divider(
              color: isDarkMode
                  ? const Color(0xFF2C2C2E)
                  : const Color(0xFFE5E5EA),
            ),
            itemBuilder: (context, index) {
              final tx = history[index];
              final date = DateTime.fromMillisecondsSinceEpoch(
                tx['createdAt'] as int? ?? 0,
              );
              final dateStr = DateFormat('MM/dd/yyyy hh:mm a').format(date);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx['title'] ?? 'Points Reward',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDarkMode
                                  ? Colors.white54
                                  : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "+${tx['points']} TP",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
