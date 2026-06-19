import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';
import 'package:tranyx_mobile/features/auth/presentation/auth_view.dart';
import 'package:tranyx_mobile/features/navigation/presentation/sidebar.dart';
import 'package:tranyx_mobile/features/navigation/presentation/header.dart';
import 'package:tranyx_mobile/features/navigation/presentation/bottom_nav.dart';
import 'package:tranyx_mobile/features/navigation/providers/navigation_provider.dart';
import 'package:tranyx_mobile/features/home/presentation/home_view.dart';
import 'package:tranyx_mobile/features/jobs/presentation/jobs_view.dart';
import 'package:tranyx_mobile/features/transit/presentation/transit_view.dart';
import 'package:tranyx_mobile/features/profile/presentation/profile_view.dart';
import 'package:tranyx_mobile/features/auth/presentation/register_complete_profile_view.dart';
import 'package:tranyx_mobile/core/providers/ui_providers.dart';
import 'package:tranyx_mobile/core/providers/fcm_provider.dart';

class MainWrapper extends ConsumerStatefulWidget {
  const MainWrapper({super.key});

  @override
  ConsumerState<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends ConsumerState<MainWrapper> {
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _bottomNavKey = GlobalKey();

  void _updateHeights() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final headerBox =
          _headerKey.currentContext?.findRenderObject() as RenderBox?;
      if (headerBox != null) {
        ref.read(mainHeaderHeightProvider.notifier).state =
            headerBox.size.height;
      }

      final navBox =
          _bottomNavKey.currentContext?.findRenderObject() as RenderBox?;
      if (navBox != null) {
        ref.read(mainBottomNavHeightProvider.notifier).state =
            navBox.size.height;
      }
    });
  }

  @override
  void dispose() {
    ref.read(fcmProvider).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final isAuthenticated = ref.watch(authStateProvider);
    final activeTab = ref.watch(activeTabProvider);

    _updateHeights();

    return Scaffold(
      backgroundColor: isDarkMode ? AppColors.darkBg : AppColors.lightBg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isTablet = constraints.maxWidth >= 768;

          if (!isAuthenticated) {
            return const AuthView();
          }

          final userProfileAsync = ref.watch(userProfileProvider);
          return userProfileAsync.when(
            loading: () => const Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: CircularProgressIndicator()),
            ),
            error: (err, stack) =>
                Scaffold(body: Center(child: Text("Error: $err"))),
            data: (profile) {
              if (profile == null) {
                return const RegisterCompleteProfileView();
              }

              // Initialize FCM once profile is available
              Future.microtask(() {
                if (context.mounted) {
                  ref.read(fcmProvider).initialize(context);
                }
              });


              Widget activeContent;
              switch (activeTab) {
                case 'home':
                  activeContent = HomeView(isTablet: isTablet);
                  break;
                case 'jobs':
                  activeContent = JobsView(isTablet: isTablet);
                  break;
                case 'transit':
                  activeContent = TransitView(isTablet: isTablet);
                  break;
                case 'profile':
                  activeContent = ProfileView(isTablet: isTablet);
                  break;
                default:
                  activeContent = const SizedBox.shrink();
              }

              return Row(
                children: [
                  if (isTablet) const Sidebar(),
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            Header(key: _headerKey, isTablet: isTablet),
                            Expanded(
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                padding: EdgeInsets.only(
                                  left: 24,
                                  right: 24,
                                  top: 24,
                                  bottom: isTablet ? 40 : 100,
                                ),
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: isTablet ? 1100 : 600,
                                    ),
                                    child: activeContent,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!isTablet)
                          Positioned(
                            key: _bottomNavKey,
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: const BottomNav(),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
