import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/features/auth/presentation/login_view.dart';
import 'package:tranyx_mobile/features/auth/presentation/register_details_view.dart';
import 'package:tranyx_mobile/features/auth/presentation/register_path_view.dart';
import 'package:tranyx_mobile/features/auth/providers/auth_provider.dart';

class AuthView extends ConsumerStatefulWidget {
  const AuthView({super.key});

  @override
  ConsumerState<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends ConsumerState<AuthView> {
  static const _viewOrder = {
    'login': 0,
    'register-path': 1,
    'register-details': 2,
  };

  String? _lastView;
  bool _isForward = true;

  @override
  Widget build(BuildContext context) {
    final authView = ref.watch(authViewProvider);

    if (_lastView != authView) {
      final oldIndex = _viewOrder[_lastView] ?? 0;
      final newIndex = _viewOrder[authView] ?? 0;
      _isForward = newIndex > oldIndex;
      _lastView = authView;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        final bool isIncoming = child.key == ValueKey(authView);

        // Incoming widget animation
        final Tween<Offset> inTween = _isForward
            ? Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ) // From Right
            : Tween<Offset>(
                begin: const Offset(-1.0, 0.0),
                end: Offset.zero,
              ); // From Left

        // Outgoing widget animation
        final Tween<Offset> outTween = _isForward
            ? Tween<Offset>(
                begin: const Offset(-1.0, 0.0),
                end: Offset.zero,
              ) // To Left
            : Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ); // To Right

        return SlideTransition(
          position: (isIncoming ? inTween : outTween).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: _buildChild(authView),
    );
  }

  Widget _buildChild(String authView) {
    switch (authView) {
      case 'login':
        return LoginView(key: const ValueKey('login'));
      case 'register-path':
        return RegisterPathView(key: const ValueKey('register-path'));
      case 'register-details':
        return RegisterDetailsView(key: const ValueKey('register-details'));
      default:
        return LoginView(key: const ValueKey('login'));
    }
  }
}
