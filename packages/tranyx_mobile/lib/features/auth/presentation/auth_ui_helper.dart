import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';

class AuthUiHelper {
  static Widget buildAuthScaffold({
    required BuildContext context,
    required bool isDarkMode,
    required Widget body,
    String? title,
    Widget? leading,
    List<Widget>? actions,
    bool isLoading = false,
  }) {
    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: title != null
            ? Text(
                title,
                style: TextStyle(
                  color: isDarkMode ? AppColors.darkText : AppColors.lightText,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
        leading: leading,
        actions: actions,
      ),
      body: Stack(
        children: [
          // Animated Metaballs Background
          const Positioned.fill(
            child: _AnimatedMetaballsBackground(),
          ),
          Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32.0,
                        vertical: 40.0,
                      ),
                      decoration: BoxDecoration(
                        color: (isDarkMode ? AppColors.darkCard : Colors.white)
                            .withValues(alpha: isDarkMode ? 0.65 : 0.75),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDarkMode ? 0.3 : 0.08,
                            ),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                        border: Border.all(
                          color: (isDarkMode ? Colors.white : AppColors.indigo)
                              .withValues(alpha: isDarkMode ? 0.12 : 0.18),
                        ),
                      ),
                      child: body,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.indigo),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Widget buildHeader({
    required String title,
    required String subtitle,
    required bool isDarkMode,
    IconData? icon,
    bool showLogo = true,
  }) {
    return Column(
      children: [
        if (showLogo) ...[
          Image.asset(
            'assets/images/logo.png',
            height: 72,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.indigo, AppColors.purple],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon ?? Icons.widgets, color: Colors.white, size: 48),
            ),
          ),
          const SizedBox(height: 32),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: isDarkMode ? AppColors.darkText : AppColors.lightText,
          ),
        ),
        // const SizedBox(height: 12),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDarkMode
                ? AppColors.darkTextMuted
                : AppColors.lightTextMuted,
          ),
        ),
      ],
    );
  }

  static Widget buildGoogleButton({
    required bool isDarkMode,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Image.asset(
          'assets/icons/google.webp',
          width: 24,
          height: 24,
          fit: BoxFit.contain,
        ),
        label: Text(
          "Continue with Google",
          style: TextStyle(
            fontSize: 16,
            color: isDarkMode ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(
            color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  static Widget buildWalletButton({
    required bool isDarkMode,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Image.asset(
          'assets/icons/solana.webp',
          width: 24,
          height: 24,
          fit: BoxFit.contain,
        ),
        label: Text(
          "Continue with Solana Wallet",
          style: TextStyle(
            fontSize: 16,
            color: isDarkMode ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(
            color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  static Widget buildPathCard({
    required String title,
    required String subtitle,
    required Widget icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDarkMode,
    Widget? badge,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDarkMode
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: .3)),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: -2,
                      ),
                      BoxShadow(
                        color: color.withValues(alpha: 0.2),
                        blurRadius: 40,
                        spreadRadius: -5,
                      ),
                    ],
                  ),
                  child: icon,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode
                              ? AppColors.darkText
                              : AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: isDarkMode
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: isDarkMode
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
              ],
            ),
          ),
        ),
        if (badge != null) Positioned(top: -10, right: 20, child: badge),
      ],
    );
  }

  static Widget buildFooter({required bool isDarkMode}) {
    return Column(
      children: [
        Text(
          "POWERED by",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: isDarkMode ? AppColors.darkText : AppColors.lightText,
          ),
        ),
        const SizedBox(height: 12),
        Image.asset('assets/images/terra-logo.png', height: 40),
      ],
    );
  }
}

class _AnimatedMetaballsBackground extends StatefulWidget {
  const _AnimatedMetaballsBackground();

  @override
  State<_AnimatedMetaballsBackground> createState() =>
      __AnimatedMetaballsBackgroundState();
}

class _MetaballSpec {
  final double startXRatio;
  final double startYRatio;
  final double targetXRatio;
  final double targetYRatio;
  final double size;
  final Color color;
  final double speedMultiplier;

  _MetaballSpec({
    required this.startXRatio,
    required this.startYRatio,
    required this.targetXRatio,
    required this.targetYRatio,
    required this.size,
    required this.color,
    required this.speedMultiplier,
  });
}

class __AnimatedMetaballsBackgroundState
    extends State<_AnimatedMetaballsBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_MetaballSpec> _metaballs;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);

    final random = math.Random();
    final count = random.nextInt(4) + 3; // Random 3 to 6 metaballs

    final colorPalette = [
      AppColors.indigo.withValues(alpha: 0.55),
      AppColors.purple.withValues(alpha: 0.55),
      Colors.blue.withValues(alpha: 0.45),
      Colors.pinkAccent.withValues(alpha: 0.45),
      Colors.cyan.withValues(alpha: 0.45),
      Colors.deepPurpleAccent.withValues(alpha: 0.5),
    ];

    _metaballs = List.generate(count, (index) {
      return _MetaballSpec(
        startXRatio: 0.05 + random.nextDouble() * 0.85,
        startYRatio: 0.05 + random.nextDouble() * 0.85,
        targetXRatio: 0.05 + random.nextDouble() * 0.85,
        targetYRatio: 0.05 + random.nextDouble() * 0.85,
        size: 220.0 + random.nextDouble() * 140.0,
        color: colorPalette[index % colorPalette.length],
        speedMultiplier: 0.7 + random.nextDouble() * 0.6,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final rawT = _controller.value;

        return Stack(
          children: _metaballs.map((spec) {
            // Apply unique speed phase per metaball
            final t = ((rawT * spec.speedMultiplier) % 1.0);
            // Smooth sine curve for natural motion
            final smoothT = (1 - math.cos(t * math.pi)) / 2;

            final x = (screenSize.width * spec.startXRatio) +
                ((screenSize.width * (spec.targetXRatio - spec.startXRatio)) * smoothT);
            final y = (screenSize.height * spec.startYRatio) +
                ((screenSize.height * (spec.targetYRatio - spec.startYRatio)) * smoothT);

            return Positioned(
              left: x - (spec.size / 2),
              top: y - (spec.size / 2),
              child: ImageFilterBlob(
                size: spec.size,
                color: spec.color,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class ImageFilterBlob extends StatelessWidget {
  final double size;
  final Color color;

  const ImageFilterBlob({
    super.key,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0.2),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
    );
  }
}
