import 'package:flutter_riverpod/legacy.dart';
import 'package:tranyx_mobile/core/services/biometric_service.dart';

class BiometricNotifier extends StateNotifier<bool> {
  BiometricNotifier() : super(false) {
    _loadState();
  }

  Future<void> _loadState() async {
    final enabled = await BiometricService.isBiometricEnabled();
    state = enabled;
  }

  Future<void> setEnabled(bool value) async {
    await BiometricService.setBiometricEnabled(value);
    state = value;
  }
}

final biometricEnabledProvider = StateNotifierProvider<BiometricNotifier, bool>((ref) {
  return BiometricNotifier();
});
