import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/color_extension.dart';
import 'package:tranyx_mobile/features/auth/presentation/auth_ui_helper.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/core/providers/phantom_provider.dart';

class RegisterPathView extends ConsumerWidget {
  const RegisterPathView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);

    return AuthUiHelper.buildAuthScaffold(
      context: context,
      isDarkMode: isDarkMode,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back,
          color: isDarkMode
              ? AppColors.darkTextMuted
              : AppColors.lightTextMuted,
        ),
        onPressed: () => ref.read(authViewProvider.notifier).state = 'login',
      ),
      actions: [
        IconButton(
          icon: Icon(
            isDarkMode ? Icons.light_mode : Icons.dark_mode,
            color: isDarkMode
                ? AppColors.darkTextMuted
                : AppColors.lightTextMuted,
          ),
          onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
        ),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthUiHelper.buildHeader(
            title: "Join Tranyx",
            subtitle: "Choose your path to get started.",
            isDarkMode: isDarkMode,
          ),
          Consumer(
            builder: (context, ref, _) {
              final pendingWalletKey = ref.watch(pendingWalletPublicKeyProvider);
              if (pendingWalletKey == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.indigo.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link, color: AppColors.indigo),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Wallet connected:\n${pendingWalletKey.substring(0, 6)}...${pendingWalletKey.substring(pendingWalletKey.length - 4)} (will be linked on sign up)",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white : AppColors.lightText,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 48),
          AuthUiHelper.buildPathCard(
            title: "I Want to Hire",
            subtitle: "Post jobs, find freelancers",
            icon: ImageIcon(
              const AssetImage("assets/icons/employer.png"),
              color: isDarkMode
                  ? AppColors.blue.lighten(.2)
                  : AppColors.blue.darken(.1),
              size: 28,
            ),
            color: AppColors.blue,
            onTap: () {
              ref.read(pendingAccountTypeProvider.notifier).state =
                  AccountType.employer;
              ref.read(authViewProvider.notifier).state = 'register-details';
            },
            isDarkMode: isDarkMode,
          ),
          const SizedBox(height: 20),
          AuthUiHelper.buildPathCard(
            title: "I Want to Work (Nyxian)",
            subtitle: "Find gigs, offer services, and earn",
            icon: ImageIcon(
              const AssetImage("assets/icons/nyxian.png"),
              color: isDarkMode
                  ? AppColors.green.lighten(.2)
                  : AppColors.green.darken(.1),
              size: 28,
            ),
            color: AppColors.green,
            onTap: () {
              ref.read(pendingAccountTypeProvider.notifier).state =
                  AccountType.nyxian;
              ref.read(authViewProvider.notifier).state = 'register-details';
            },
            isDarkMode: isDarkMode,
          ),
          const SizedBox(height: 20),
          AuthUiHelper.buildPathCard(
            title: "Hybrid Account",
            subtitle: "Hire and work seamlessly",
            badge: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.amber.withValues(alpha: 0.6),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                "PRO",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            icon: ImageIcon(
              const AssetImage("assets/icons/hybrid.png"),
              color: isDarkMode
                  ? AppColors.amber.lighten(.2)
                  : AppColors.amber.darken(.1),
              size: 28,
            ),
            color: AppColors.amber,
            onTap: () {
              ref.read(pendingAccountTypeProvider.notifier).state =
                  AccountType.hybrid;
              ref.read(authViewProvider.notifier).state = 'register-details';
            },
            isDarkMode: isDarkMode,
          ),
          const SizedBox(height: 40),
          GestureDetector(
            onTap: () => ref.read(authViewProvider.notifier).state = 'login',
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: isDarkMode
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  const TextSpan(text: "Already have an account? "),
                  TextSpan(
                    text: "Login",
                    style: TextStyle(
                      color: isDarkMode ? Colors.white : AppColors.indigo,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
          AuthUiHelper.buildFooter(isDarkMode: isDarkMode),
        ],
      ),
    );
  }
}
