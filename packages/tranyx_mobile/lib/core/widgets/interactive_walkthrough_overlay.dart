import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
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
      transitionDuration: const Duration(milliseconds: 300),
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
      duration: const Duration(milliseconds: 1500),
      value: 1.0,
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Only start infinite loop in non-test mode or forward
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
      WalkthroughStepModel(
        id: 'verification',
        title: 'Trust & Verification Badges',
        description:
            'Tranyx strictly identifies counterparties with verified badges so you always know who you are transacting with.',
        icon: Icons.shield_rounded,
        targetKey: keys['profile'] ?? keys['verification'],
        customContent: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const UserBadgeWidget(
                    level: VerificationLevel.level1Basic,
                    showLabel: true,
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Level 1: Basic Gov ID Verified',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const UserBadgeWidget(
                    level: VerificationLevel.level2Pro,
                    showLabel: true,
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Level 2: Merchant & Pro Verified',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'No Badge',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Unverified: Zero badges shown',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      WalkthroughStepModel(
        id: 'rentals',
        title: 'Rentals & Calendar Availability',
        description:
            'Explore vehicles and properties with persistent calendar availability. Booked dates are locked, and clean start dates automatically optimize rates.',
        icon: Icons.directions_car_outlined,
        targetKey: keys['rentals'] ?? keys['transit'],
      ),
      WalkthroughStepModel(
        id: 'jobs',
        title: 'Jobs & Live Execution Tracking',
        description:
            'Post or browse gigs with live filtering. Bidding is open to all Nyxians, and real-time live execution updates strictly activate once hired.',
        icon: Icons.work_outline,
        targetKey: keys['jobs'],
      ),
      WalkthroughStepModel(
        id: 'wallet',
        title: 'MWA Web3 Wallet & Fiat Ledger',
        description:
            'Connect your Solana wallet via Mobile Wallet Adapter to sign smart contract transactions and view unified GCash & token ledgers.',
        icon: Icons.account_balance_wallet_outlined,
        targetKey: keys['wallet'],
      ),
    ];
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
    final padding = MediaQuery.of(context).padding;

    // Calculate spotlight cutout bounds
    Rect cutoutRect;
    if (targetRect != null) {
      cutoutRect = Rect.fromCenter(
        center: targetRect.center,
        width: targetRect.width + 16,
        height: targetRect.height + 16,
      );
    } else {
      // Default fallback centered position for virtual spotlight
      cutoutRect = Rect.fromCenter(
        center: Offset(
          screenSize.width / 2,
          screenSize.height * 0.35,
        ),
        width: screenSize.width * 0.85,
        height: 140,
      );
    }

    // Determine tooltip vertical placement (above or below target)
    final placeBelow = cutoutRect.bottom < (screenSize.height * 0.55);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ── Dimmed Scrim with Spotlight Cutout ──────────────────────────
          GestureDetector(
            onTap: () => _dismiss(completed: false),
            child: CustomPaint(
              size: screenSize,
              painter: _SpotlightPainter(
                cutoutRect: cutoutRect,
                pulseValue: _pulseAnimation.value,
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

          // ── Floating Tooltip Card ──────────────────────────────────────
          Positioned(
            left: 20,
            right: 20,
            top: placeBelow ? (cutoutRect.bottom + 16) : null,
            bottom: !placeBelow
                ? (screenSize.height - cutoutRect.top + 16)
                : null,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1B4B), // Deep indigo
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.purple.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.purple.withValues(alpha: 0.35),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row with Icon & Step Count
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.purple.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            currentStep.icon,
                            color: AppColors.purpleLight,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Step ${_currentStepIndex + 1} of ${steps.length}',
                                style: TextStyle(
                                  color: AppColors.purpleLight,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                currentStep.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white60,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _dismiss(completed: false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Description text
                    Text(
                      currentStep.description,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),

                    // Custom Step Content (e.g. Badges)
                    if (currentStep.customContent != null)
                      currentStep.customContent!,

                    const SizedBox(height: 20),

                    // Navigation Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Step Dots
                        Row(
                          children: List.generate(
                            steps.length,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 6),
                              width: _currentStepIndex == index ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _currentStepIndex == index
                                    ? AppColors.purpleLight
                                    : Colors.white24,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),

                        // Action buttons
                        Row(
                          children: [
                            if (_currentStepIndex > 0)
                              TextButton(
                                onPressed: _previousStep,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                ),
                                child: const Text('Back'),
                              ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.purple,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                              ),
                              onPressed: () => _nextStep(steps.length),
                              child: Text(
                                _currentStepIndex == steps.length - 1
                                    ? 'Got It'
                                    : 'Next',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
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

/// Custom painter to dim the screen and punch out a rounded spotlight hole
class _SpotlightPainter extends CustomPainter {
  final Rect cutoutRect;
  final double pulseValue;

  _SpotlightPainter({
    required this.cutoutRect,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.78)
      ..style = PaintingStyle.fill;

    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cutoutRRect = RRect.fromRectAndRadius(
      cutoutRect,
      const Radius.circular(18),
    );

    final cutoutPath = Path()..addRRect(cutoutRRect);

    // Difference between full screen and cutout
    final combinedPath = Path.combine(
      PathOperation.difference,
      fullPath,
      cutoutPath,
    );

    canvas.drawPath(combinedPath, backgroundPaint);

    // Draw glowing pulsing outline around the cutout
    final glowPaint = Paint()
      ..color = AppColors.purple.withValues(alpha: 0.6 * pulseValue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * pulseValue;

    canvas.drawRRect(cutoutRRect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.cutoutRect != cutoutRect ||
        oldDelegate.pulseValue != pulseValue;
  }
}
