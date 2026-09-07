import 'package:flutter/material.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';
import 'package:tranyx_mobile/core/widgets/user_badge_widget.dart';

/// Defines a spotlight step in the interactive onboarding walkthrough.
class WalkthroughStepModel {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final GlobalKey? targetKey;
  final Widget? customContent;

  const WalkthroughStepModel({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.targetKey,
    this.customContent,
  });
}

class InteractiveWalkthroughOverlay extends StatefulWidget {
  final Map<String, GlobalKey>? targetKeys;
  final VoidCallback? onDismiss;
  final VoidCallback? onComplete;

  const InteractiveWalkthroughOverlay({
    super.key,
    this.targetKeys,
    this.onDismiss,
    this.onComplete,
  });

  /// Static helper to trigger the walkthrough overlay on demand or first launch
  static Future<void> show(
    BuildContext context, {
    Map<String, GlobalKey>? targetKeys,
    VoidCallback? onDismiss,
    VoidCallback? onComplete,
    bool recordAsSeen = true,
  }) async {
    if (recordAsSeen) {
      await SecureStorageHelper.saveHasSeenOnboarding(true);
    }

    if (!context.mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Walkthrough',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        return InteractiveWalkthroughOverlay(
          targetKeys: targetKeys,
          onDismiss: onDismiss,
          onComplete: onComplete,
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }

  @override
  State<InteractiveWalkthroughOverlay> createState() =>
      _InteractiveWalkthroughOverlayState();
}

class _InteractiveWalkthroughOverlayState
    extends State<InteractiveWalkthroughOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStepIndex = 0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
      value: 1.0,
    );

    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    try {
      _pulseController.repeat(reverse: true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  List<WalkthroughStepModel> _buildSteps() {
    final keys = widget.targetKeys ?? {};
    return [
      // ── Step 1: Something for Everyone ──────────────────────────────────────
      WalkthroughStepModel(
        id: 'step1_everyone',
        title: '🚀 Something for Everyone',
        description:
            'Your next opportunity starts here.\nLooking for work? Need a service? Have something to rent? TRANYX brings opportunities together—all in one place.',
        icon: Icons.explore_outlined,
        targetKey: keys['home'],
        customContent: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF27272A).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildFeatureTile(
                      icon: Icons.work_outline_rounded,
                      title: 'Jobs & Services',
                      desc: 'Find gigs or hire Nyxians',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFeatureTile(
                      icon: Icons.directions_car_outlined,
                      title: 'Vehicle & Space Rentals',
                      desc: 'Rentals with calendar lock',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Discover new possibilities built around what you need and what you can offer.',
                style: TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),

      // ── Step 2: Turn What You Have Into Something More ─────────────────────
      WalkthroughStepModel(
        id: 'step2_turn_assets',
        title: '💡 Turn What You Have Into More',
        description:
            'Skills. Time. Things you own. You have more ways to earn than you think. Turn your skills, time, services, and assets into opportunities.',
        icon: Icons.lightbulb_outline,
        targetKey: keys['jobs'] ?? keys['gigs'],
        customContent: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF27272A).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildFeatureTile(
                      icon: Icons.handyman_outlined,
                      title: 'Offer Expertise',
                      desc: 'Carpentry, Tech, Courier',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFeatureTile(
                      icon: Icons.vpn_key_outlined,
                      title: 'Rent What You Own',
                      desc: 'Vehicles, tools & properties',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
                ),
                child: const Text(
                  'Your opportunity could be worth more than you think.',
                  style: TextStyle(
                    color: Color(0xFFFCD34D),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      // ── Step 3: Safe. Secure. Built for You ─────────────────────────────────
      WalkthroughStepModel(
        id: 'step3_safety',
        title: '🔥 Safe. Secure. Built for You 🛡️',
        description:
            'Transact with confidence. TRANYX uses identity verification, trust badges, and security measures so you know who you are dealing with.',
        icon: Icons.verified_user_outlined,
        targetKey: keys['profile'] ?? keys['verification'],
        customContent: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF27272A).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBadgeRow(
                badge: const UserBadgeWidget(
                  level: VerificationLevel.level1Basic,
                  showLabel: true,
                  size: 13,
                ),
                label: 'Level 1: Basic Gov ID Verified',
                desc: 'Government ID validated with facial liveness match',
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(color: Colors.white10, height: 1),
              ),
              _buildBadgeRow(
                badge: const UserBadgeWidget(
                  level: VerificationLevel.level2Pro,
                  showLabel: true,
                  size: 13,
                ),
                label: 'Level 2: Merchant & Pro Verified',
                desc: 'Registered host & verified business standing',
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(color: Colors.white10, height: 1),
              ),
              _buildBadgeRow(
                badge: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'No Badge',
                    style: TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                label: 'Unverified',
                desc: 'Make informed decisions before proceeding',
              ),
            ],
          ),
        ),
      ),

      // ── Step 4: Make Opportunities Happen ──────────────────────────────────
      WalkthroughStepModel(
        id: 'step4_workflow',
        title: '✨ Make Opportunities Happen',
        description:
            'From discovery to done. Apply for the job. Book the service. Accept the offer. Complete the rental. Get things done—all through TRANYX.',
        icon: Icons.auto_awesome_outlined,
        targetKey: keys['rentals'] ?? keys['transit'],
        customContent: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF27272A).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildFlowStep(number: '1', label: 'Found'),
                  const Icon(Icons.arrow_forward, size: 10, color: Color(0xFF71717A)),
                  _buildFlowStep(number: '2', label: 'Connected'),
                  const Icon(Icons.arrow_forward, size: 10, color: Color(0xFF71717A)),
                  _buildFlowStep(number: '3', label: 'Transact'),
                  const Icon(Icons.arrow_forward, size: 10, color: Color(0xFF71717A)),
                  _buildFlowStep(number: '4', label: 'Done ✓', isSuccess: true),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.star, size: 12, color: Color(0xFFFBBF24)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Live QR code verification, ratings & reputation score',
                        style: TextStyle(
                          color: Color(0xFFA1A1AA),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // ── Step 5: Get Rewarded Along the Way ──────────────────────────────────
      WalkthroughStepModel(
        id: 'step5_rewards',
        title: '🪙 Get Rewarded Along the Way',
        description:
            'Earn Terra Rewards Points as you participate in TRANYX. Convert points into TYXBIT utility tokens powered by the Solana blockchain.',
        icon: Icons.toll_outlined,
        targetKey: keys['wallet'],
        customContent: Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF27272A).withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildFeatureTile(
                      icon: Icons.stars_rounded,
                      title: 'Terra Rewards',
                      desc: '✨ Earn Points',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFeatureTile(
                      icon: Icons.currency_bitcoin,
                      title: 'TYXBIT Tokens',
                      desc: '🪙 Convert Crypto',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildFeatureTile(
                      icon: Icons.account_balance_wallet,
                      title: 'Crypto Wallet',
                      desc: '🔗 Solana MWA',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFeatureTile(
                      icon: Icons.bolt,
                      title: 'Powered by Solana',
                      desc: '⚡ Fast & Low Gas',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildFlowStep({
    required String number,
    required String label,
    bool isSuccess = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isSuccess
            ? const Color(0xFF10B981).withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSuccess ? const Color(0xFF10B981).withValues(alpha: 0.3) : Colors.white12,
        ),
      ),
      child: Text(
        '$number. $label',
        style: TextStyle(
          color: isSuccess ? const Color(0xFF34D399) : const Color(0xFFE4E4E7),
          fontSize: 9.5,
          fontWeight: isSuccess ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBadgeRow({
    required Widget badge,
    required String label,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: badge,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFF4F4F5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                desc,
                style: const TextStyle(
                  color: Color(0xFF71717A),
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureTile({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFA1A1AA)),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF4F4F5),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            desc,
            style: const TextStyle(
              color: Color(0xFF71717A),
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    );
  }

  Rect? _getTargetRect(GlobalKey? key) {
    if (key == null || key.currentContext == null) return null;
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    final offset = renderBox.localToGlobal(Offset.zero);
    return offset & renderBox.size;
  }

  void _nextStep(int totalSteps) {
    if (_currentStepIndex < totalSteps - 1) {
      setState(() {
        _currentStepIndex++;
      });
    } else {
      _dismiss(completed: true);
    }
  }

  void _previousStep() {
    if (_currentStepIndex > 0) {
      setState(() {
        _currentStepIndex--;
      });
    }
  }

  void _dismiss({bool completed = false}) {
    if (completed) {
      widget.onComplete?.call();
    } else {
      widget.onDismiss?.call();
    }
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    final currentStep = steps[_currentStepIndex];
    final targetRect = _getTargetRect(currentStep.targetKey);
    final screenSize = MediaQuery.of(context).size;

    // Calculate spotlight cutout bounds
    Rect cutoutRect;
    if (targetRect != null) {
      cutoutRect = Rect.fromCenter(
        center: targetRect.center,
        width: targetRect.width + 12,
        height: targetRect.height + 12,
      );
    } else {
      cutoutRect = Rect.fromCenter(
        center: Offset(
          screenSize.width / 2,
          screenSize.height * 0.22,
        ),
        width: screenSize.width * 0.88,
        height: 70,
      );
    }

    final hasTarget = targetRect != null;
    final placeBelow = cutoutRect.bottom < (screenSize.height * 0.50);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Soft Matte Scrim with Spotlight Cutout ──────────────────────────
          GestureDetector(
            onTap: () => _dismiss(completed: false),
            child: CustomPaint(
              size: screenSize,
              painter: _SpotlightPainter(
                cutoutRect: cutoutRect,
                pulseValue: _pulseAnimation.value,
                hasTarget: hasTarget,
              ),
            ),
          ),

          // ── Interactive Tap Target overlay ─────────────────────────────
          Positioned(
            left: cutoutRect.left,
            top: cutoutRect.top,
            width: cutoutRect.width,
            height: cutoutRect.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _nextStep(steps.length),
              child: const SizedBox.expand(),
            ),
          ),

          // ── Minimalist Clean Floating Card ────────────────────────────
          Positioned(
            left: 18,
            right: 18,
            top: placeBelow ? (cutoutRect.bottom + 12) : null,
            bottom: !placeBelow
                ? (screenSize.height - cutoutRect.top + 12)
                : null,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B), // Soft matte charcoal
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar: Step Pill & Close Button with spacious layout (no icon)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              'Step ${_currentStepIndex + 1} of ${steps.length}',
                              style: const TextStyle(
                                color: Color(0xFFD4D4D8),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF71717A),
                              size: 19,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _dismiss(completed: false),
                          ),
                        ],
                      ),
                    ),

                    // Title Header with generous spacing
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        currentStep.title,
                        style: const TextStyle(
                          color: Color(0xFFFAFAFA),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),

                    // Description text with comfortable reading line height
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        currentStep.description,
                        style: const TextStyle(
                          color: Color(0xFFA1A1AA),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ),

                    // Custom Content
                    if (currentStep.customContent != null)
                      currentStep.customContent!,

                    const SizedBox(height: 14),

                    // Footer: Step indicator + Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Minimalist Segment Dots
                        Row(
                          children: List.generate(
                            steps.length,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 5),
                              width: _currentStepIndex == index ? 16 : 5,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _currentStepIndex == index
                                    ? const Color(0xFFFAFAFA)
                                    : Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),

                        // Buttons
                        Row(
                          children: [
                            if (_currentStepIndex > 0)
                              TextButton(
                                onPressed: _previousStep,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFA1A1AA),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                ),
                                child: const Text(
                                  'Back',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFAFAFA),
                                foregroundColor: const Color(0xFF18181B),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              onPressed: () => _nextStep(steps.length),
                              child: Text(
                                _currentStepIndex == steps.length - 1
                                    ? "🚀 Let's Go!"
                                    : 'Next →',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for soft matte dimming
class _SpotlightPainter extends CustomPainter {
  final Rect cutoutRect;
  final double pulseValue;
  final bool hasTarget;

  _SpotlightPainter({
    required this.cutoutRect,
    required this.pulseValue,
    required this.hasTarget,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (hasTarget) {
      final cutoutRRect = RRect.fromRectAndRadius(
        cutoutRect,
        const Radius.circular(16),
      );

      final cutoutPath = Path()..addRRect(cutoutRRect);

      final combinedPath = Path.combine(
        PathOperation.difference,
        fullPath,
        cutoutPath,
      );

      canvas.drawPath(combinedPath, backgroundPaint);

      // Subtle muted border around the cutout
      final strokePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.4 * pulseValue)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;

      canvas.drawRRect(cutoutRRect, strokePaint);
    } else {
      canvas.drawPath(fullPath, backgroundPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.cutoutRect != cutoutRect ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.hasTarget != hasTarget;
  }
}
