import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';

class ThemeNotifier extends StateNotifier<bool> with WidgetsBindingObserver {
  ThemeNotifier()
    : super(
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
      ) {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _userOverridden = false;

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (!_userOverridden) {
      state =
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
  }

  void toggleTheme() {
    _userOverridden = true;
    state = !state;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final themeModeProvider = StateNotifierProvider<ThemeNotifier, bool>((ref) {
  return ThemeNotifier();
});
