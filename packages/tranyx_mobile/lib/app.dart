import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/core/router/app_router.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/biometric_provider.dart';
import 'package:tranyx_mobile/core/widgets/biometric_lock_screen.dart';
import 'package:tranyx_mobile/core/services/biometric_service.dart';
import 'flavors.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _isColdStart = true;
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // final router = ref.read(routerProvider);
      // ref.read(deepLinkServiceProvider).initialize(router);
      _isColdStart = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // ref.read(deepLinkServiceProvider).dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPaused = true;
    }

    if (state == AppLifecycleState.resumed && !_isColdStart) {
      if (_wasPaused && !_isLocked && !BiometricService.isAuthenticating) {
        _wasPaused = false;
        final biometricEnabled = ref.read(biometricEnabledProvider);
        if (biometricEnabled) {
          setState(() {
            _isLocked = true;
          });
        }
      } else {
        _wasPaused = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final isDarkMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: F.title,
      debugShowCheckedModeBanner: F.appFlavor == Flavor.dev,
      routerConfig: router,
      theme: _buildTheme(Brightness.light, context),
      darkTheme: _buildTheme(Brightness.dark, context),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        final withBanner = _flavorBanner(child: child!, show: kDebugMode);
        if (_isLocked) {
          return Stack(
            children: [
              withBanner,
              BiometricLockScreen(
                isDarkMode: isDarkMode,
                onUnlocked: () {
                  setState(() {
                    _isLocked = false;
                  });
                },
              ),
            ],
          );
        }
        return withBanner;
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness, context) {
    final isDark = brightness == Brightness.dark;
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: AppColors.indigo,
      fontFamily: "DMSans",
    );
    final baseTextTheme = Theme.of(context).textTheme;

    return baseTheme.copyWith(
      textTheme: baseTextTheme.copyWith(
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        displaySmall: baseTextTheme.displaySmall?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          color: isDark ? AppColors.darkText : AppColors.lightText,
        ),
      ),

      // textTheme: GoogleFonts.dmSansTextTheme(baseTheme.textTheme).apply(
      //   bodyColor: isDark ? AppColors.darkText : AppColors.lightText,
      //   displayColor: isDark ? AppColors.darkText : AppColors.lightText,
      // ),
      scaffoldBackgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      cardTheme: CardThemeData(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
    );
  }

  Widget _flavorBanner({required Widget child, bool show = true}) => show
      ? Banner(
          location: BannerLocation.topStart,
          message: F.name.toUpperCase(),
          color: F.appFlavor == Flavor.production
              ? Colors.transparent
              : (F.appFlavor == Flavor.uat ? Colors.amber : Colors.green)
                    .withAlpha(150),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 10.0,
            letterSpacing: 1.0,
          ),
          textDirection: TextDirection.ltr,
          child: child,
        )
      : child;
}
